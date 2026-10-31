// Edge function: e-mail askandgo when a pro application is waiting for review.
// Called by the pro_profiles trigger notify_pro_application (mig 00561) on a new
// application and on a corrected one after a refusal.
// Deployment: supabase functions deploy notify-pro-application --no-verify-jwt
//
// Auth: same shared secret as send-push (`PUSH_WEBHOOK_SECRET`, header
// `x-junto-push-secret`). The trigger only sends the user_id: the application
// is re-read here with the service key, so nothing in the mail comes from the
// request itself.
//
// Secrets: RESEND_API_KEY (required). Optional: PRO_APPLICATION_MAIL_TO
// (default contact@askandgo.io), MAIL_FROM (default askandgo <noreply@askandgo.io>).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SECRET = Deno.env.get('PUSH_WEBHOOK_SECRET');
const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY');
const MAIL_TO = Deno.env.get('PRO_APPLICATION_MAIL_TO') ?? 'contact@askandgo.io';
const MAIL_FROM = Deno.env.get('MAIL_FROM') ?? 'askandgo <noreply@askandgo.io>';

// Same labels as the app (src/i18n/fr.json › pro.profession).
const PROFESSIONS: Record<string, string> = {
  mountain_guide: 'Guide de haute montagne',
  mountain_leader: 'Accompagnateur en montagne',
  climbing_instructor: "Moniteur d'escalade",
  canyoning_instructor: 'Moniteur de canyoning',
  whitewater_instructor: "Moniteur d'eau vive",
  diving_instructor: 'Moniteur de plongée',
  surf_instructor: 'Moniteur de surf / voile',
  paragliding_instructor: 'Moniteur de parapente',
  ski_instructor: 'Moniteur de ski',
  mtb_instructor: 'Moniteur de VTT',
  wellness_instructor: 'Professeur de yoga / bien-être',
  school_office: 'Bureau / école',
  other: 'Autre',
};

function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function esc(v: unknown): string {
  return String(v ?? '')
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });

  const provided = req.headers.get('x-junto-push-secret') ?? '';
  if (!SECRET || !constantTimeEqual(provided, SECRET)) {
    return new Response('Forbidden', { status: 403 });
  }
  if (!RESEND_API_KEY) return new Response('Mail not configured', { status: 503 });

  let userId: string;
  let resubmission = false;
  try {
    const body = await req.json();
    userId = String(body.user_id ?? '');
    resubmission = body.resubmission === true;
  } catch {
    return new Response('Invalid JSON', { status: 400 });
  }
  if (!/^[0-9a-f-]{36}$/i.test(userId)) return new Response('Missing fields', { status: 400 });

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  const { data: pro, error } = await supabase
    .from('pro_profiles')
    .select('display_name, company_name, real_name, profession, tagline, description, email, phone, website, instagram, facebook, primary_location_name, status, created_at')
    .eq('user_id', userId)
    .maybeSingle();
  if (error) return new Response('Lookup failed', { status: 500 });
  // Only a still-pending application is mailed (it may have moved since the trigger).
  if (!pro || pro.status !== 'pending') return new Response('Nothing to send', { status: 200 });

  const rows: [string, unknown][] = [
    ['Raison sociale', pro.company_name],
    ['Nom de la page', pro.display_name],
    ['Responsable', pro.real_name],
    ['Métier', pro.profession ? (PROFESSIONS[pro.profession] ?? pro.profession) : null],
    ['Lieu', pro.primary_location_name],
    ['Accroche', pro.tagline],
    ['Description', pro.description],
    ['E-mail', pro.email],
    ['Téléphone', pro.phone],
    ['Site', pro.website],
    ['Instagram', pro.instagram],
    ['Facebook', pro.facebook],
  ];
  const table = rows
    .filter(([, v]) => v != null && String(v).trim() !== '')
    .map(([k, v]) => `<tr><td style="padding:6px 12px 6px 0;color:#6B6259;vertical-align:top;white-space:nowrap">${esc(k)}</td><td style="padding:6px 0;white-space:pre-wrap">${esc(v)}</td></tr>`)
    .join('');

  const name = pro.company_name || pro.display_name;
  const subject = `${resubmission ? 'Demande pro corrigée' : 'Nouvelle demande pro'} : ${name}`.replace(/[\r\n]+/g, ' ');
  const html = `<div style="font-family:Helvetica,Arial,sans-serif;font-size:15px;color:#1F1A15;max-width:600px">
<p>${resubmission ? 'Une demande pro refusée a été corrigée et renvoyée' : 'Une nouvelle demande pro attend ta validation'}.</p>
<table style="border-collapse:collapse;font-size:14px">${table}</table>
<p style="margin-top:20px">À valider dans l'app : Paramètres › Administration › Demandes pro.</p>
</div>`;

  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { Authorization: `Bearer ${RESEND_API_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ from: MAIL_FROM, to: [MAIL_TO], subject, html }),
  });
  if (!res.ok) {
    console.error('resend', res.status, await res.text());
    return new Response('Mail failed', { status: 502 });
  }
  return new Response('ok', { status: 200 });
});
