#!/usr/bin/env node
// Builds supabase/functions/send-push/templates.json from the app's own
// translation files: the `notif` namespace (push titles/bodies per type and
// variant) plus the two half-day labels used by booking params. ONE source of
// truth for in-app and push text — run after editing any src/i18n/*.json, then
// redeploy the function:  npm run push:templates && npx supabase functions deploy send-push --no-verify-jwt
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const LANGS = ['fr', 'en', 'it', 'es', 'de'];
const out = { generatedFrom: 'src/i18n/*.json (npm run push:templates)', languages: {} };
for (const lang of LANGS) {
  const json = JSON.parse(readFileSync(resolve(root, `src/i18n/${lang}.json`), 'utf8'));
  if (!json.notif) throw new Error(`${lang}.json has no "notif" namespace`);
  out.languages[lang] = {
    notif: json.notif,
    period: { am: json.booking?.am ?? 'am', pm: json.booking?.pm ?? 'pm' },
  };
}
const target = resolve(root, 'supabase/functions/send-push/templates.json');
writeFileSync(target, JSON.stringify(out, null, 1) + '\n');
console.log(`templates.json: ${LANGS.length} languages, ${Object.keys(out.languages.fr.notif).length} types → ${target}`);
