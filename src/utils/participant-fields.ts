// Fiche participant (00422): the standard fields an outing can ask for, with
// their label and keyboard. Shared by the group form and the fixed-date sign-up.
export const STD_LABELS: Record<string, { key: string; fallback: string; keyboard?: 'number-pad' }> = {
  shoe_size: { key: 'booking.fShoe', fallback: 'Pointure', keyboard: 'number-pad' },
  height: { key: 'booking.fHeight', fallback: 'Taille (cm)', keyboard: 'number-pad' },
  weight: { key: 'booking.fWeight', fallback: 'Poids (kg)', keyboard: 'number-pad' },
  age: { key: 'booking.fAge', fallback: 'Âge', keyboard: 'number-pad' },
  level: { key: 'booking.fLevel', fallback: 'Niveau' },
};

// Entries keep their position (participant 2 stays participant 2): a blank
// participant is an empty object, and only the blank tail is dropped. The
// database counts only the filled ones (00578).
export const isFilledEntry = (e: object | null | undefined) => !!e && Object.keys(e).length > 0;
export function trimBlankTail<T extends object>(entries: T[]): T[] {
  let n = entries.length;
  while (n > 0 && !isFilledEntry(entries[n - 1])) n--;
  return entries.slice(0, n);
}
export const filledCount = (info: object[] | null | undefined) => (info ?? []).filter(isFilledEntry).length;
