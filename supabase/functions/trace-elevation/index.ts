// Edge function: give a 2D trace its altitudes, from the IGN Géoplateforme
// altimetry service (RGE ALTI, 1 m in the Alps, free, no key).
//
// A GPX imported from Strava / Komoot / Garmin already carries <ele>; a trace
// drawn in-app does not. The client sends the bare coordinates here, gets one
// altitude per point back, stores the 3D trace — and the server then derives
// the elevation gain in SQL (trace_elevation_gain_m, mig 00452), the same way
// for every trace whatever its origin.
//
// Why a proxy (not a direct client call): IGN needs no key, but a per-user
// quota keeps Junto from becoming an anonymous altimetry relay, and the input
// is validated + size-capped before it leaves us.
//
// Contract:
//   POST { coordinates: [[lng,lat], ...] }   (1..MAX points, in order — the
//                                             draw modal enriches segment by
//                                             segment, the first one is a dot)
//   200  { ok: true,  z: number[] }          one altitude (m, integer) per point
//   200  { ok: false, reason: 'no_coverage' }  > 10 % of the points outside
//                                              IGN coverage (France + DOM/COM)
//   400  invalid input · 401 unauthenticated · 429 quota · 502 upstream error
//
// Deployment: `supabase functions deploy trace-elevation` (JWT verification
// ON). No secret required.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;

// activities.trace_geojson is CHECKed at 2..10000 points.
const MAX_POINTS = 10000;
// IGN caps a request at 5000 points → at most two upstream calls per trace.
const IGN_BATCH = 5000;
const IGN_URL = 'https://data.geopf.fr/altimetrie/1.0/calcul/alti/rest/elevation.json';
// IGN returns this for a point outside its coverage.
const IGN_NO_DATA = -99999;
// 10000 short coordinate pairs weigh ~400 KB; anything bigger is not a trace.
const MAX_BODY_BYTES = 512 * 1024;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

function isValidCoord(c: unknown): c is number[] {
  return (
    Array.isArray(c) &&
    c.length >= 2 &&
    typeof c[0] === 'number' && typeof c[1] === 'number' &&
    Number.isFinite(c[0]) && Number.isFinite(c[1]) &&
    c[0] >= -180 && c[0] <= 180 && c[1] >= -90 && c[1] <= 90
  );
}

// One IGN call: altitudes for up to IGN_BATCH points, in order.
async function ignElevations(coords: number[][]): Promise<number[]> {
  const res = await fetch(IGN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
    body: JSON.stringify({
      lon: coords.map((c) => c[0].toFixed(6)).join('|'),
      lat: coords.map((c) => c[1].toFixed(6)).join('|'),
      resource: 'ign_rge_alti_wld',
      delimiter: '|',
      zonly: 'true',
    }),
  });
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new Error(`IGN ${res.status}: ${text.slice(0, 200)}`);
  }
  const data = (await res.json()) as { elevations?: unknown };
  const list = Array.isArray(data.elevations) ? data.elevations : null;
  if (!list || list.length !== coords.length) {
    throw new Error(`IGN returned ${list?.length ?? 'no'} elevations for ${coords.length} points`);
  }
  // zonly=true → plain numbers; tolerate the extended {z} shape anyway.
  return list.map((e) => {
    const z = typeof e === 'number' ? e : (e as { z?: unknown })?.z;
    return typeof z === 'number' && Number.isFinite(z) ? z : IGN_NO_DATA;
  });
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });

  // 1) Auth gate — verify the caller's JWT.
  const authHeader = req.headers.get('Authorization') ?? '';
  if (!authHeader.startsWith('Bearer ')) return json({ error: 'Unauthorized' }, 401);
  const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData.user) return json({ error: 'Unauthorized' }, 401);

  // 2) Per-user quota FIRST — before any body is buffered or parsed
  // (150 calls / rolling hour, mig 00454; suspended users refused there too).
  const { error: rlErr } = await userClient.rpc('consume_trace_elevation_quota');
  if (rlErr) return json({ ok: false, reason: 'rate_limited' }, 429);

  // 3) Read + validate input, capped by ACTUAL length before JSON.parse.
  let text: string;
  try {
    text = await req.text();
  } catch {
    return json({ error: 'Unreadable body' }, 400);
  }
  if (text.length > MAX_BODY_BYTES) return json({ error: 'Body too large' }, 400);
  let coords: unknown;
  try {
    coords = (JSON.parse(text) as { coordinates?: unknown })?.coordinates;
  } catch {
    return json({ error: 'Invalid JSON' }, 400);
  }
  if (!Array.isArray(coords) || coords.length < 1 || coords.length > MAX_POINTS) {
    return json({ error: `coordinates must hold 1..${MAX_POINTS} points` }, 400);
  }
  if (!coords.every(isValidCoord)) {
    return json({ error: 'coordinates must be [lng,lat] within valid ranges' }, 400);
  }
  const clean = (coords as number[][]).map((c) => [c[0], c[1]]);

  // 4) IGN, by batches of 5000, in order.
  const z: number[] = [];
  try {
    for (let i = 0; i < clean.length; i += IGN_BATCH) {
      z.push(...(await ignElevations(clean.slice(i, i + IGN_BATCH))));
    }
  } catch (e) {
    console.error(`[trace-elevation] ${e}`);
    return json({ error: 'Altimetry unavailable' }, 502);
  }

  // 5) Coverage: IGN only knows France + DOM/COM. A few holes are tolerated
  // (the SQL gain ignores them); a trace mostly outside gets no altitudes.
  const missing = z.filter((v) => v <= IGN_NO_DATA).length;
  if (missing > clean.length * 0.1) return json({ ok: false, reason: 'no_coverage' });

  return json({ ok: true, z: z.map((v) => (v <= IGN_NO_DATA ? null : Math.round(v))) });
});
