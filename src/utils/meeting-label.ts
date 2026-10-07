// « Commune · précision » for a rendez-vous (mig 00441), without saying the
// same thing twice: « Briançon · Briançon gare » reads as a stutter, so when
// one part already contains the other (accents and case ignored) only the
// more specific one is kept. Null when there is nothing to say.
const fold = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim();

export function formatMeetingLabel(locality: string | null | undefined, name: string | null | undefined): string | null {
  const loc = locality?.trim() || null;
  const prec = name?.trim() || null;
  if (loc && prec) {
    const l = fold(loc);
    const p = fold(prec);
    if (p.includes(l)) return prec;
    if (l.includes(p)) return loc;
    return `${loc} · ${prec}`;
  }
  return loc ?? prec;
}

// Past this length the value no longer fits beside its label on a phone and
// wraps mid-row — the caller moves it to its own line instead.
export const MEETING_LABEL_INLINE_MAX = 28;
