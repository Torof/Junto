// Shared vibe vocabulary (the 25 closed values) — used by Discovery dispos AND
// channels. Labels carry an emoji; i18n key `discovery.intent.<key>` overrides
// them at render (kept global so both features reuse the same translations).

export type VibeKey =
  | 'discovery' | 'progression' | 'performance' | 'detente' | 'conviviality'
  | 'dog' | 'child' | 'group' | 'solo' | 'active' | 'calm' | 'early'
  | 'nature' | 'challenge' | 'photo' | 'mixed' | 'same_level' | 'beginners'
  | 'long_outing' | 'after_work' | 'regular' | 'adapted' | 'training'
  | 'experienced' | 'competition';

export const VIBE_LABEL: Record<VibeKey, string> = {
  discovery: '🧭 Découverte', progression: '📈 Progression', performance: '🔥 Performance',
  detente: '🍃 Détente', conviviality: '🤝 Convivialité',
  dog: '🐕 Chien', child: '👶 Enfant', group: '👥 En groupe', solo: '🧍 Solo',
  active: '⚡ Actif', calm: '😌 Calme', early: '🌅 Matinal',
  nature: '🌲 Nature', challenge: '🎯 Défi', photo: '📷 Photo',
  mixed: '⚥ Groupe mixte', same_level: '🎚️ Même niveau', beginners: '🌱 Débutants bienvenus',
  long_outing: '🥾 Sortie longue', after_work: '🌆 Après le boulot', regular: '🔁 Partenaire régulier',
  adapted: '♿ Handi / adapté', training: '💪 Entraînement', experienced: '🎖️ Expérimenté',
  competition: '🏁 Prépa compét',
};

// Grouped for pickers (compose / channel form). groupKey → i18n discovery.vibeGroup.<groupKey>.
export const VIBE_GROUPS: { groupKey: string; group: string; items: VibeKey[] }[] = [
  { groupKey: 'ambiance', group: 'Ambiance', items: ['discovery', 'progression', 'performance', 'detente', 'conviviality', 'nature', 'challenge', 'photo'] },
  { groupKey: 'compagnie', group: 'Compagnie', items: ['dog', 'child', 'group', 'solo', 'mixed', 'same_level', 'beginners'] },
  { groupKey: 'rythme', group: 'Rythme', items: ['active', 'calm', 'early', 'long_outing', 'after_work', 'regular'] },
  { groupKey: 'profil', group: 'Profil / accès', items: ['adapted', 'training', 'experienced', 'competition'] },
];
