// Edge function: snap a set of hand-placed waypoints onto real trails.
//
// The trace builder places waypoints tap-by-tap; for each new segment it
// sends the two endpoints here and gets back the geometry of the path that
// actually follows the trail (OpenRouteService `foot-hiking`, OSM data).
//
// Why a proxy (not a direct client call):
//   - the ORS API key stays server-side (never in the app bundle);
//   - only authenticated Junto users can spend our free quota (JWT gate);
//   - input is validated + size-capped before it ever reaches ORS.
//
// Contract:
//   POST { coordinates: [[lng,lat], ...] }   (2..MAX points, in order)
//   200  { ok: true,  geometry: { type:'LineString', coordinates:[[lng,lat],...] } }
//   200  { ok: false, reason: 'no_route' }   → client draws a straight segment
//   400  invalid input · 401 unauthenticated · 502 upstream error
//
// Deployment: `supabase functions deploy snap-trail`  (JWT verification ON —
// we WANT only logged-in users). Requires secrets: ORS_API_KEY (+ the
// SUPABASE_URL / SUPABASE_ANON_KEY that Supabase injects automatically).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;
const ORS_API_KEY = Deno.env.get('ORS_API_KEY');

// One request routes a short segment (usually 2 points). Cap generously to
// allow a small batch re-snap, but never let a caller ship us a huge polyline.
const MAX_POINTS = 50;
// How far ORS may look for a routable trail around each point (metres). Beyond
// this the point is "off-trail" → ORS errors → we fall back to a straight line.
const SNAP_RADIUS_M = 400;

const ORS_URL = 'https://api.openrouteservice.org/v2/directions/foot-hiking/geojson';

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

function isValidCoord(c: unknown): c is [number, number] {
  return (
    Array.isArray(c) &&
    c.length >= 2 &&
    typeof c[0] === 'number' && typeof c[1] === 'number' &&
    Number.isFinite(c[0]) && Number.isFinite(c[1]) &&
    c[0] >= -180 && c[0] <= 180 && c[1] >= -90 && c[1] <= 90
  );
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });

  // 1) Auth gate — verify the caller's JWT (protects our ORS quota).
  const authHeader = req.headers.get('Authorization') ?? '';
  if (!authHeader.startsWith('Bearer ')) return json({ error: 'Unauthorized' }, 401);
  const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData.user) return json({ error: 'Unauthorized' }, 401);

  if (!ORS_API_KEY) {
    console.error('[snap-trail] ORS_API_KEY secret is not set');
    return json({ error: 'Snap unavailable' }, 503);
  }

  // 2) Per-user rate limit FIRST — before we buffer/parse any body, so an
  // over-quota or looping caller can't force unbounded parses. (200 snaps/hour;
  // protects the shared ORS quota.)
  const { error: rlErr } = await userClient.rpc('consume_snap_trail_quota');
  if (rlErr) return json({ ok: false, reason: 'rate_limited' }, 429);

  // 3) Read + validate input. Cap the body by ACTUAL length, not the spoofable/
  // omittable Content-Length header: read as text, reject >20 KB, THEN parse —
  // so JSON.parse never runs on an oversized payload (≤50 short coords fit well
  // under 20 KB). req.text() buffering itself is bounded by the platform ceiling
  // and now by the rate limit above.
  let raw: string;
  try {
    raw = await req.text();
  } catch {
    return json({ error: 'Invalid body' }, 400);
  }
  if (raw.length > 20_000) return json({ error: 'Payload too large' }, 413);
  let payload: { coordinates?: unknown };
  try {
    payload = JSON.parse(raw);
  } catch {
    return json({ error: 'Invalid JSON' }, 400);
  }
  const coords = payload.coordinates;
  if (!Array.isArray(coords) || coords.length < 2 || coords.length > MAX_POINTS) {
    return json({ error: `coordinates must be an array of 2..${MAX_POINTS} points` }, 400);
  }
  if (!coords.every(isValidCoord)) {
    return json({ error: 'coordinates must be [lng,lat] within valid ranges' }, 400);
  }
  // Normalise to [lng,lat] (drop any elevation the client might send).
  const cleanCoords = (coords as number[][]).map((c) => [c[0], c[1]]);

  // 4) Call ORS foot-hiking. radiuses bounds the snap distance per point.
  let orsRes: Response;
  try {
    orsRes = await fetch(ORS_URL, {
      method: 'POST',
      headers: {
        Authorization: ORS_API_KEY,
        'Content-Type': 'application/json',
        Accept: 'application/geo+json',
      },
      body: JSON.stringify({
        coordinates: cleanCoords,
        radiuses: cleanCoords.map(() => SNAP_RADIUS_M),
        instructions: false,
        elevation: false,
      }),
    });
  } catch (e) {
    console.error(`[snap-trail] ORS fetch threw: ${e}`);
    return json({ error: 'Upstream unreachable' }, 502);
  }

  if (!orsRes.ok) {
    // ORS 404 / error code 2010 = a point is beyond any routable trail. That's
    // an expected, non-error case for us → tell the client to straight-line it.
    let code: number | undefined;
    try { code = (await orsRes.clone().json())?.error?.code; } catch { /* ignore */ }
    if (orsRes.status === 404 || code === 2010) {
      return json({ ok: false, reason: 'no_route' });
    }
    const text = await orsRes.text().catch(() => '');
    console.error(`[snap-trail] ORS ${orsRes.status}: ${text.slice(0, 300)}`);
    return json({ error: 'Snap failed' }, 502);
  }

  // 4) Extract the LineString geometry from the GeoJSON FeatureCollection.
  let geo: { features?: Array<{ geometry?: { type?: string; coordinates?: unknown } }> };
  try {
    geo = await orsRes.json();
  } catch {
    return json({ error: 'Bad upstream response' }, 502);
  }
  const geometry = geo.features?.[0]?.geometry;
  if (!geometry || geometry.type !== 'LineString' || !Array.isArray(geometry.coordinates)) {
    return json({ ok: false, reason: 'no_route' });
  }

  return json({ ok: true, geometry: { type: 'LineString', coordinates: geometry.coordinates } });
});
