'use client';

import { useState } from 'react';
import { getSupabase } from '@/lib/supabase';

// iOS waitlist — one e-mail, nothing else. Stored through the
// `join_ios_waitlist` RPC (anonymous, validated and capped server-side).
// Until that function ships, the form explains how to reach us instead.
export default function IosWaitlistForm() {
  const [email, setEmail] = useState('');
  const [state, setState] = useState<'idle' | 'sending' | 'done' | 'error'>('idle');

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    const value = email.trim();
    if (!value || state === 'sending') return;
    setState('sending');
    try {
      const supabase = getSupabase();
      if (!supabase) throw new Error('no client');
      const { error } = await supabase.rpc('join_ios_waitlist', { p_email: value });
      if (error) throw error;
      setState('done');
    } catch {
      setState('error');
    }
  };

  if (state === 'done') {
    return <p style={{ margin: 0, fontSize: 14, color: '#7BD8A5', fontWeight: 600 }}>C&apos;est noté. On t&apos;écrit le jour où l&apos;app arrive sur iPhone.</p>;
  }

  return (
    <form className="l-wait" onSubmit={submit}>
      <label htmlFor="ios-email" style={{ fontSize: 14, fontWeight: 600 }}>Sur iPhone ? On te prévient à la sortie iOS.</label>
      <div className="l-wait-row">
        <input id="ios-email" type="email" required autoComplete="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="toi@exemple.fr" />
        <button type="submit" disabled={state === 'sending'}>{state === 'sending' ? 'Un instant…' : 'Préviens-moi'}</button>
      </div>
      {state === 'error' && (
        <p style={{ margin: 0, fontSize: 13, color: 'rgba(255,255,255,0.8)' }}>
          La liste n&apos;est pas encore ouverte. Écris-nous à <a href="mailto:contact@getjunto.app" style={{ color: '#7BD8A5' }}>contact@getjunto.app</a>, on te préviendra.
        </p>
      )}
    </form>
  );
}
