// Fiche participant (00422): the standard fields an outing can ask for, with
// their label and keyboard. Shared by the group form and the fixed-date sign-up.
export const STD_LABELS: Record<string, { key: string; fallback: string; keyboard?: 'number-pad' }> = {
  shoe_size: { key: 'booking.fShoe', fallback: 'Pointure', keyboard: 'number-pad' },
  height: { key: 'booking.fHeight', fallback: 'Taille (cm)', keyboard: 'number-pad' },
  weight: { key: 'booking.fWeight', fallback: 'Poids (kg)', keyboard: 'number-pad' },
  age: { key: 'booking.fAge', fallback: 'Âge', keyboard: 'number-pad' },
  level: { key: 'booking.fLevel', fallback: 'Niveau' },
};
