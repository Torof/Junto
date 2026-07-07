import { useMemo, useState } from 'react';
import { View, Text, Pressable, StyleSheet, Modal } from 'react-native';
import { useTranslation } from 'react-i18next';
import dayjs from 'dayjs';
import 'dayjs/locale/fr';
import Svg, { Circle } from 'react-native-svg';
import { Camera, Plus, HelpCircle } from 'lucide-react-native';
import { fontSizes, spacing, radius, shadows } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { UserAvatar } from './user-avatar';

export interface ProfileHeroStats {
  completed_activities: number;
  created_activities: number;
  joined_activities: number;
}

interface Props {
  displayName: string;
  avatarUrl: string | null;
  // Pass `reliabilityPct` only on own profile (raw value is private).
  // For other users, pass `reliabilityTier` — the ring fills to the band
  // midpoint and the label shows the tier name instead of a percentage.
  reliabilityPct?: number | null;
  reliabilityTier?: string | null;
  stats: ProfileHeroStats | null;
  joinedAt: string | null;
  city?: string | null;
  onAvatarPress?: () => void;
  isUploading?: boolean;
}

const RING_SIZE = 80;

// Trust-pillar tier color for a reliability percentage. Exported so the
// Organisation tab's GroupCard can render the same tier ring around
// driver avatars where the actual decision happens.
export function ringColorFor(pct: number): string {
  if (pct >= 75) return '#7EC8A3';
  if (pct >= 40) return '#F26B2E';
  return '#E5524E';
}

function tierToPct(tier: string): number | null {
  switch (tier) {
    case 'excellent': return 95;
    case 'good': return 82;
    case 'fair': return 62;
    case 'poor': return 30;
    default: return null;
  }
}

export function reliabilityTierFromScore(score: number | null): string {
  if (score === null) return 'new';
  if (score >= 90) return 'excellent';
  if (score >= 75) return 'good';
  if (score >= 50) return 'fair';
  return 'poor';
}

export function ProfileHero({
  displayName, avatarUrl, reliabilityPct, reliabilityTier, stats,
  joinedAt, city, onAvatarPress, isUploading = false,
}: Props) {
  const { t, i18n } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const [showHelp, setShowHelp] = useState(false);

  const effectivePct = reliabilityPct ?? (reliabilityTier ? tierToPct(reliabilityTier) : null);
  const hasScore = effectivePct != null;
  const color = hasScore ? ringColorFor(effectivePct) : colors.textMuted;

  const r = (RING_SIZE - 8) / 2;
  const c = 2 * Math.PI * r;
  const pct = hasScore ? Math.max(0, Math.min(100, effectivePct)) : 0;
  const dashOffset = c * (1 - pct / 100);

  // When showing tier (other users), display the tier label instead of a precise %
  const showRawPct = reliabilityPct != null;
  const tierLabel = reliabilityTier ? t(`reliability.tier.${reliabilityTier}`) : null;

  const memberLine = joinedAt
    ? `${t('profil.memberSince', { date: dayjs(joinedAt).locale(i18n.language).format('MMM YYYY') })}${city ? ` · ${city}` : ''}`
    : city ?? '';

  return (
    <View style={styles.card}>
      <View style={styles.row}>
        {/* Ring + avatar + explicit edit affordance */}
        <View style={styles.avatarCol}>
        <Pressable
          onPress={onAvatarPress}
          disabled={!onAvatarPress || isUploading}
          style={[styles.ringWrap, isUploading && { opacity: 0.5 }]}
        >
          <Svg width={RING_SIZE} height={RING_SIZE}>
            {/* Track */}
            <Circle
              cx={RING_SIZE / 2} cy={RING_SIZE / 2} r={r}
              fill="none" stroke={colors.surfaceAlt} strokeWidth={4}
            />
            {/* Filled arc */}
            {hasScore && pct > 0 && (
              <Circle
                cx={RING_SIZE / 2} cy={RING_SIZE / 2} r={r}
                fill="none" stroke={color} strokeWidth={3.5}
                strokeDasharray={`${c}`}
                strokeDashoffset={dashOffset}
                strokeLinecap="round"
                transform={`rotate(-90 ${RING_SIZE / 2} ${RING_SIZE / 2})`}
              />
            )}
          </Svg>

          {/* Center disc with avatar */}
          <View style={styles.avatarDisc}>
            {avatarUrl ? (
              <UserAvatar name={displayName} avatarUrl={avatarUrl} size={68} />
            ) : onAvatarPress ? (
              <View style={styles.uploadPlaceholder}>
                <Camera size={24} color={colors.textSecondary} strokeWidth={2} />
                <View style={styles.plusBadge}>
                  <Plus size={10} color="#FFFFFF" strokeWidth={3} />
                </View>
              </View>
            ) : (
              <Text style={styles.avatarFallback}>🏔️</Text>
            )}
          </View>

          {/* % pill at bottom */}
          {hasScore && (
            <View style={[styles.pctPill, { backgroundColor: color, shadowColor: color }]}>
              <Text style={styles.pctPillText}>{showRawPct ? `${pct}%` : tierLabel}</Text>
            </View>
          )}
        </Pressable>
        {/* Explicit affordance — the tap target used to be invisible. */}
        {onAvatarPress && (
          <Pressable onPress={onAvatarPress} disabled={isUploading} hitSlop={6} style={styles.editPhotoBtn}>
            <Text style={styles.editPhotoText}>{t('profil.editPhoto', { defaultValue: 'Modifier la photo' })}</Text>
          </Pressable>
        )}
        </View>

        {/* Right side: score + stats */}
        <View style={{ flex: 1, minWidth: 0 }}>
          {/* Label on its own line, the reliability value on the next. */}
          <View style={styles.scoreLabelRow}>
            <Text style={styles.scoreLabel}>{t('reliability.label').toUpperCase()}</Text>
            <Pressable onPress={() => setShowHelp(true)} hitSlop={8} style={styles.helpButton}>
              <HelpCircle size={14} color={colors.textMuted} strokeWidth={2} />
            </Pressable>
          </View>
          {hasScore ? (
            // Big label = tier name when available, else fall back to %.
            // The pctPill on the avatar ring keeps the raw % when available.
            <Text style={[styles.scoreBig, { color }]}>{tierLabel ?? `${pct}%`}</Text>
          ) : (
            <Text style={[styles.scoreBig, { color: colors.textMuted }]}>—</Text>
          )}

          {memberLine !== '' && (
            <Text style={styles.memberLine}>{memberLine}</Text>
          )}

          <View style={styles.statsRow}>
            <StatCell value={stats?.completed_activities ?? 0} labelKey="profil.completed" accent="#7EC8A3" styles={styles} t={t} />
            <View style={styles.statDivider} />
            <StatCell value={stats?.created_activities ?? 0} labelKey="profil.created" accent="#F26B2E" styles={styles} t={t} />
            <View style={styles.statDivider} />
            <StatCell value={stats?.joined_activities ?? 0} labelKey="profil.joined" accent="#4B7CB8" styles={styles} t={t} />
          </View>
        </View>
      </View>

      <Modal visible={showHelp} animationType="fade" transparent onRequestClose={() => setShowHelp(false)}>
        <Pressable style={styles.helpBackdrop} onPress={() => setShowHelp(false)}>
          <Pressable style={styles.helpCard} onPress={(e) => e.stopPropagation()}>
            <Text style={styles.helpTitle}>{t('reliability.helpTitle')}</Text>
            <Text style={styles.helpBody}>{t('reliability.helpIntro')}</Text>
            <Text style={styles.helpHeading}>{t('reliability.helpHowHeading')}</Text>
            <Text style={styles.helpBody}>{t('reliability.helpHow')}</Text>
            <Text style={styles.helpHeading}>{t('reliability.helpStartHeading')}</Text>
            <Text style={styles.helpBody}>{t('reliability.helpStart')}</Text>
            <Pressable style={styles.helpDismiss} onPress={() => setShowHelp(false)}>
              <Text style={styles.helpDismissText}>{t('reliability.helpDismiss')}</Text>
            </Pressable>
          </Pressable>
        </Pressable>
      </Modal>
    </View>
  );
}

function StatCell({
  value, labelKey, accent, styles, t,
}: {
  value: number;
  labelKey: string;
  accent: string;
  styles: ReturnType<typeof createStyles>;
  t: (k: string) => string;
}) {
  return (
    <View style={styles.stat}>
      <Text style={styles.statValue}>{value}</Text>
      <Text style={[styles.statLabel, { color: accent }]} numberOfLines={1}>
        {t(labelKey)}
      </Text>
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  card: {
    backgroundColor: colors.surface,
    borderRadius: 18,
    borderWidth: 1, borderColor: colors.line,
    padding: spacing.md,
    paddingBottom: spacing.md - 2,
    marginBottom: spacing.md,
    position: 'relative',
    ...shadows.card,
  },
  row: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: spacing.md - 2,
    position: 'relative',
  },
  avatarCol: {
    alignItems: 'center',
    flexShrink: 0,
  },
  editPhotoBtn: {
    marginTop: 12,
    paddingHorizontal: 10,
    paddingVertical: 3,
    borderRadius: radius.full,
    borderWidth: 1,
    borderColor: colors.cta,
    borderStyle: 'dashed',
  },
  editPhotoText: {
    color: colors.cta,
    fontSize: 11,
    fontWeight: '700',
  },
  ringWrap: {
    width: RING_SIZE,
    height: RING_SIZE,
    flexShrink: 0,
    position: 'relative',
    // Pull up a touch to compensate for the pctPill hanging below the ring
    // box, which otherwise makes the avatar feel lower than the text.
    marginTop: -5,
  },
  avatarDisc: {
    position: 'absolute',
    top: 6, left: 6, right: 6, bottom: 6,
    borderRadius: (RING_SIZE - 12) / 2,
    overflow: 'hidden',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.surfaceAlt,
  },
  avatarFallback: { fontSize: 32, lineHeight: 36 },
  uploadPlaceholder: {
    width: '100%', height: '100%',
    alignItems: 'center', justifyContent: 'center',
  },
  plusBadge: {
    position: 'absolute',
    bottom: 2, right: 2,
    width: 20, height: 20, borderRadius: 10,
    backgroundColor: colors.cta,
    alignItems: 'center', justifyContent: 'center',
    borderWidth: 2, borderColor: colors.surface,
  },
  pctPill: {
    position: 'absolute',
    bottom: -5,
    alignSelf: 'center',
    left: 0, right: 0,
    marginHorizontal: 'auto',
    paddingHorizontal: 8, paddingVertical: 2,
    borderRadius: 999,
    shadowOffset: { width: 0, height: 3 },
    shadowOpacity: 0.5,
    shadowRadius: 6,
    elevation: 4,
    alignItems: 'center',
    minWidth: 38,
  },
  pctPillText: {
    color: '#FFFFFF',
    fontSize: 10,
    fontWeight: '800',
    letterSpacing: -0.01,
    textAlign: 'center',
  },

  scoreLabelRow: {
    flexDirection: 'row', alignItems: 'center', gap: 6,
  },
  scoreBig: {
    fontSize: 26,
    fontWeight: '800',
    letterSpacing: -0.03,
    lineHeight: 30,
    marginBottom: 2,
  },
  scoreLabel: {
    color: colors.textSecondary,
    fontSize: 10,
    fontWeight: '600',
    letterSpacing: 1.2,
    textTransform: 'uppercase',
  },
  memberLine: {
    color: colors.textMuted,
    fontSize: 11.5,
    marginBottom: spacing.sm,
  },
  statsRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
  },
  statDivider: {
    width: 1, height: 28,
    backgroundColor: colors.line,
  },
  stat: { flex: 1, minWidth: 0, alignItems: 'flex-start' },
  statValue: {
    color: colors.textPrimary,
    fontSize: 20,
    fontWeight: '800',
    letterSpacing: -0.02,
    lineHeight: 22,
  },
  // Fixed size for all three (no adjustsFontSizeToFit — that shrank the
  // longer labels independently, so they rendered at different sizes).
  statLabel: {
    fontSize: 11.5,
    fontWeight: '700',
    letterSpacing: 0.2,
    marginTop: 3,
  },

  helpButton: {
    paddingVertical: 2,
    paddingHorizontal: 1,
    alignSelf: 'center',
  },

  helpBackdrop: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.55)',
    alignItems: 'center',
    justifyContent: 'center',
    padding: spacing.lg,
  },
  helpCard: {
    backgroundColor: colors.surface,
    borderRadius: radius.lg,
    borderWidth: 1,
    borderColor: colors.line,
    padding: spacing.lg,
    width: '100%',
    maxWidth: 420,
    gap: 8,
  },
  helpTitle: {
    color: colors.textPrimary,
    fontSize: fontSizes.lg,
    fontWeight: '800',
    marginBottom: 4,
  },
  helpHeading: {
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
    fontWeight: '700',
    marginTop: 8,
  },
  helpBody: {
    color: colors.textSecondary,
    fontSize: fontSizes.sm,
    lineHeight: 20,
  },
  helpDismiss: {
    alignSelf: 'center',
    marginTop: spacing.md,
    backgroundColor: colors.cta + '1F',
    borderRadius: 999,
    paddingVertical: 10,
    paddingHorizontal: 28,
  },
  helpDismissText: {
    color: colors.cta,
    fontSize: fontSizes.sm,
    fontWeight: '700',
  },
});
