#!/usr/bin/env node
// Junto DB test runner.
//
//   node scripts/db-test.mjs            run every supabase/tests/*.test.sql
//   node scripts/db-test.mjs identite   run the files whose name contains "identite"
//
// Each test file is wrapped with supabase/tests/_prelude.sql into ONE `DO`
// block that always ends by raising its results, so the database is never
// changed. After the run, the runner checks that no test account survived.
// Runs against the project the Supabase CLI is linked to (via the Management
// API) — no Docker, no local Postgres needed.
//
// Exit code 1 if any check fails, if a known hole unexpectedly passes (xpass:
// the test must be updated), if a file crashes, or if any residue is found.

import { readFileSync, readdirSync, writeFileSync, mkdtempSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { join, dirname } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const testsDir = join(root, 'supabase', 'tests');
const filter = process.argv[2] ?? '';
const prelude = readFileSync(join(testsDir, '_prelude.sql'), 'utf8');
const files = readdirSync(testsDir).filter((f) => f.endsWith('.test.sql') && f.includes(filter)).sort();
const work = mkdtempSync(join(tmpdir(), 'junto-dbtest-'));

// The suite runs against whatever project the repo is LINKED to. Say which one,
// and refuse when JUNTO_DB_REF names another (migration: never prove the wrong base).
let linkedRef = '?';
try { linkedRef = readFileSync(join(root, 'supabase', '.temp', 'project-ref'), 'utf8').trim(); } catch { /* not linked */ }
console.log(`target project: ${linkedRef}`);
if (process.env.JUNTO_DB_REF && process.env.JUNTO_DB_REF !== linkedRef) {
  console.error(`refusing: JUNTO_DB_REF=${process.env.JUNTO_DB_REF} but the repo is linked to ${linkedRef}`);
  process.exit(2);
}

function runSql(sql) {
  const file = join(work, 'q.sql');
  writeFileSync(file, sql);
  try {
    return execFileSync('npx', ['supabase', 'db', 'query', '--experimental', '--linked', '-f', file], {
      cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 64 * 1024 * 1024,
    });
  } catch (e) {
    return `${e.stdout ?? ''}${e.stderr ?? ''}`;
  }
}

const colour = { pass: '\x1b[32m', fail: '\x1b[31m', xfail: '\x1b[33m', xpass: '\x1b[35m', reset: '\x1b[0m' };
const totals = { pass: 0, fail: 0, xfail: 0, xpass: 0, crashed: 0 };

for (const f of files) {
  const body = readFileSync(join(testsDir, f), 'utf8');
  const sql = `DO $junto_test$
BEGIN
${prelude}
${body}
PERFORM pg_temp.as_('db');
RAISE EXCEPTION 'JUNTO_TEST_RESULT %', replace(encode(convert_to(
  (SELECT coalesce(json_agg(r ORDER BY n), '[]'::json)::text FROM pg_temp.junto_results r), 'UTF8'), 'base64'), E'\\n', '');
END $junto_test$;`;
  const out = runSql(sql);
  const m = out.match(/JUNTO_TEST_RESULT ([A-Za-z0-9+/=]+)/);
  console.log(`\n▶ ${f}`);
  if (!m) {
    totals.crashed++;
    console.log(`${colour.fail}  CRASH${colour.reset} ${out.replace(/\s+/g, ' ').slice(0, 600)}`);
    continue;
  }
  const results = JSON.parse(Buffer.from(m[1], 'base64').toString('utf8'));
  for (const r of results) {
    totals[r.status]++;
    if (r.status === 'pass') continue; // keep the report short: only what needs attention
    const tag = r.known ? ` [${r.known}]` : '';
    console.log(`  ${colour[r.status]}${r.status.toUpperCase()}${colour.reset} ${r.name}${tag} — ${r.detail ?? ''}`);
  }
  const p = results.filter((r) => r.status === 'pass').length;
  console.log(`  ${p}/${results.length} passed`);
}

const residue = runSql(`SELECT count(*) AS n FROM auth.users WHERE email LIKE '%@junto.test'`);
const residueCount = Number((residue.match(/"n":\s*(\d+)/) ?? [])[1] ?? NaN);

console.log('\n──────────');
console.log(`pass ${totals.pass} · fail ${totals.fail} · known holes (xfail) ${totals.xfail} · fixed? (xpass) ${totals.xpass} · crashed ${totals.crashed}`);
console.log(residueCount === 0 ? 'residue: 0 test account left ✓' : `${colour.fail}residue check: ${Number.isNaN(residueCount) ? 'could not run' : residueCount + ' test accounts left!'}${colour.reset}`);
process.exit(totals.fail || totals.xpass || totals.crashed || residueCount !== 0 ? 1 : 0);
