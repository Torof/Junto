#!/usr/bin/env node
// Compare two catalog snapshots (scripts/catalog-snapshot.sql).
//   node scripts/catalog-diff.mjs snapshot           → print the linked project's snapshot JSON
//   node scripts/catalog-diff.mjs old.json new.json  → list every difference; exit 1 if any
// Allowed differences (decided in MIGRATION_PLAN) go in scripts/catalog-allowed.json
// as {"k", "n", "old", "new"} entries: old/new are the EXACT expected fingerprints
// ("" = absent on that side) or {"re": "…"} regexes. A matching kind+name with any
// other content is still reported. Nothing else may differ.
import { readFileSync, writeFileSync, mkdtempSync, existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { join, dirname } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
// JUNTO_DB_WORKDIR: folder linked to another project (migration rehearsal).
const dbDir = process.env.JUNTO_DB_WORKDIR ?? root;
try { console.error(`target project: ${readFileSync(join(dbDir, 'supabase', '.temp', 'project-ref'), 'utf8').trim()}`); } catch { /* not linked */ }

function snapshot(extraSqlBefore = '') {
  const sql = readFileSync(join(root, 'scripts', 'catalog-snapshot.sql'), 'utf8');
  const file = join(mkdtempSync(join(tmpdir(), 'junto-cat-')), 'q.sql');
  writeFileSync(file, extraSqlBefore + sql);
  const out = execFileSync('npx', ['supabase', 'db', 'query', '--experimental', '--linked', '-f', file],
    { cwd: dbDir, encoding: 'utf8', maxBuffer: 256 * 1024 * 1024 });
  const json = JSON.parse(out.slice(out.indexOf('{')));
  const rows = json.rows[json.rows.length - 1].snapshot;
  return typeof rows === 'string' ? JSON.parse(rows) : rows;
}

// Self-test: inject known changes inside a transaction that always aborts
// (DO block ending in RAISE), snapshot, and check the diff reports each one.
function mutatedSnapshot() {
  const sql = readFileSync(join(root, 'scripts', 'catalog-snapshot.sql'), 'utf8').trim().replace(/;$/, '');
  const body = `DO $selftest$
DECLARE s text;
BEGIN
  GRANT INSERT ON public.app_config TO anon;
  ALTER FUNCTION public.get_activity_detail(uuid) SET search_path = pg_temp, public;
  EXECUTE (SELECT format('DROP POLICY %I ON %I.%I', policyname, schemaname, tablename)
           FROM pg_policies WHERE schemaname = 'public' ORDER BY tablename, policyname LIMIT 1);
  SELECT q.snapshot::text INTO s FROM (${sql}) q;
  RAISE EXCEPTION 'JUNTO_SNAPSHOT %', replace(encode(convert_to(s, 'UTF8'), 'base64'), E'\\n', '');
END $selftest$;`;
  const file = join(mkdtempSync(join(tmpdir(), 'junto-cat-')), 'q.sql');
  writeFileSync(file, body);
  let out;
  try {
    out = execFileSync('npx', ['supabase', 'db', 'query', '--experimental', '--linked', '-f', file],
      { cwd: dbDir, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 256 * 1024 * 1024 });
  } catch (e) { out = `${e.stdout ?? ''}${e.stderr ?? ''}`; }
  const m = out.match(/JUNTO_SNAPSHOT ([A-Za-z0-9+/=]+)/);
  if (!m) { console.error(out.slice(0, 800)); process.exit(3); }
  return JSON.parse(Buffer.from(m[1], 'base64').toString('utf8'));
}

const [cmd, a] = process.argv.slice(2);
if (cmd === 'selftest') {
  const base = snapshot();
  const mutated = mutatedSnapshot();
  const after = snapshot();
  const k = (r) => `${r.k}|${r.n}|${r.f}`;
  const B = new Set(base.map(k)); const M = new Set(mutated.map(k)); const A = new Set(after.map(k));
  const changed = [...B].filter((x) => !M.has(x)).length + [...M].filter((x) => !B.has(x)).length;
  const fpOf = (set, kind, name) => set.find((r) => r.k === kind && r.n === name)?.f;
  const grant = fpOf(mutated, 'grant.table', 'public.app_config.anon') !== fpOf(base, 'grant.table', 'public.app_config.anon');
  const cfgChanged = fpOf(mutated, 'function', 'get_activity_detail(uuid)') !== fpOf(base, 'function', 'get_activity_detail(uuid)')
    && fpOf(base, 'function', 'get_activity_detail(uuid)') !== undefined;
  const policyGone = base.filter((r) => r.k === 'policy').length - mutated.filter((r) => r.k === 'policy').length === 1;
  const restored = [...B].every((x) => A.has(x)) && B.size === A.size;
  console.log(`grant detected: ${grant} · search_path change detected: ${!!cfgChanged} · dropped policy detected: ${policyGone} · ${changed} line(s) differ · base restored after rollback: ${restored}`);
  process.exit(grant && cfgChanged && policyGone && restored ? 0 : 1);
}
if (cmd === 'snapshot') {
  process.stdout.write(JSON.stringify(snapshot(), null, 0) + '\n');
  process.exit(0);
}
const load = (p) => JSON.parse(readFileSync(p, 'utf8'));
// PostGIS moves from public to extensions: catalog printing (types, view and
// policy text, signatures) qualifies its objects differently depending on where
// it lives. That prefix is the one allowed difference — strip it on both sides.
const POSTGIS = /\b(?:public|extensions)\.(?="?(?:geography|geometry|box2d|box3d|spatial_ref_sys|geometry_columns|geography_columns|st_[a-z0-9_]+|postgis_[a-z0-9_]+)\b)/g;
const norm = (r) => ({ k: r.k, n: r.n.replace(POSTGIS, ''), f: String(r.f).replace(POSTGIS, '') });
const leftRaw = load(cmd);
const rightRaw = load(a);
// Identity guard: the two snapshots must come from two different projects, and the
// second from the expected one when JUNTO_DB_REF is given — never a false « 0 écart ».
const idOf = (rows) => rows.find((r) => r.k === 'identity')?.f;
const idL = idOf(leftRaw); const idR = idOf(rightRaw);
console.log(`old snapshot: ${idL ?? '?'}\nnew snapshot: ${idR ?? '?'}`);
if (!idL || !idR || idL === idR) { console.error('refusing: both snapshots come from the same project (or carry no identity)'); process.exit(2); }
if (process.env.JUNTO_DB_REF && !idR.includes(process.env.JUNTO_DB_REF)) { console.error(`refusing: new snapshot is not ${process.env.JUNTO_DB_REF}`); process.exit(2); }
const left = leftRaw.filter((r) => r.k !== 'identity').map(norm);
const right = rightRaw.filter((r) => r.k !== 'identity').map(norm);
const allowedPath = join(root, 'scripts', 'catalog-allowed.json');
const allowedList = existsSync(allowedPath) ? load(allowedPath) : [];
const fits = (rule, v) => (rule && typeof rule === 'object' ? new RegExp(rule.re).test(v) : rule === v);
const isAllowed = ([, k, f1, f2]) => allowedList.some((x) => `${x.k}\u0000${x.n}` === k && fits(x.old, f1) && fits(x.new, f2));
const key = (r) => `${r.k}\u0000${r.n}`;
const L = new Map(left.map((r) => [key(r), r.f]));
const R = new Map(right.map((r) => [key(r), r.f]));
const diffs = [];
for (const [k, f] of L) {
  if (!R.has(k)) diffs.push(['missing on new', k, f, '']);
  else if (R.get(k) !== f) diffs.push(['changed', k, f, R.get(k)]);
}
for (const [k, f] of R) if (!L.has(k)) diffs.push(['extra on new', k, '', f]);
const real = diffs.filter((d) => !isAllowed(d));
for (const [what, k, f1, f2] of real) {
  const [kind, name] = k.split('\u0000');
  console.log(`${what.padEnd(15)} ${kind.padEnd(15)} ${name}${f1 || f2 ? `\n    old: ${f1}\n    new: ${f2}` : ''}`);
}
console.log(`\n${left.length} objects old, ${right.length} new — ${real.length} unexpected difference(s), ${diffs.length - real.length} allowed.`);
process.exit(real.length ? 1 : 0);
