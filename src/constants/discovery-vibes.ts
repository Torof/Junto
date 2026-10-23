import type { DispoIntent } from '@/services/discovery-service';

// Vibe pills (« ce que tu cherches ») — the one place the app keeps emoji in
// the interface (Scott 2026-10-23): they describe a person, not the app, and
// the touch of colour is wanted. Labels are the i18n fallbacks.
export const INTENT_LABEL: Record<DispoIntent, string> = {
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

// Same group order as the compose picker (ambiance → compagnie → rythme → profil).
export const VIBE_FILTER_GROUPS: { key: string; items: DispoIntent[] }[] = [
  { key: 'ambiance', items: ['discovery', 'progression', 'performance', 'detente', 'conviviality', 'nature', 'challenge', 'photo'] },
  { key: 'compagnie', items: ['dog', 'child', 'group', 'solo', 'mixed', 'same_level', 'beginners'] },
  { key: 'rythme', items: ['active', 'calm', 'early', 'long_outing', 'after_work', 'regular'] },
  { key: 'profil', items: ['adapted', 'training', 'experienced', 'competition'] },
];

// The six universes, in the order of the « Explorer par sport » grid.
export const UNIVERSES = ['mountain', 'on-foot', 'water', 'air', 'cycling', 'wellness'] as const;
export type Universe = (typeof UNIVERSES)[number];
