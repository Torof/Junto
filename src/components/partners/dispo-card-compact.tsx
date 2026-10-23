import { memo, useMemo } from 'react';
import { View, StyleSheet } from 'react-native';
import { AppText } from '@/components/app-text';
import { useTranslation } from 'react-i18next';
import dayjs from 'dayjs';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius, shadows } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import type { DiscoveryCard } from '@/services/discovery-service';
import { UserAvatar } from '@/components/user-avatar';
import { ReliabilityRing } from '@/components/reliability-ring';
import { PressableScale } from '@/components/pressable-scale';
import { SportIcon } from '@/components/sport-icon';
import { sportCategoryColor } from '@/utils/sport-category-color';
import { reliabilityColorForTier } from '@/utils/reliability-color';
import { INTENT_LABEL } from '@/constants/discovery-vibes';

export const formatPeriod = (start: string, end: string) =>
  `${dayjs(start).format('D MMM')} – ${dayjs(end).format('D MMM')}`;

// Compact match card (Partenaires refonte 2026-10-23): enough to want more —
// photo, name, reliability, distance, dates, sports, one line — the full card
// opens on tap. Fixed width in the carousel, full width in « Tout voir ».
export const DispoCardCompact = memo(function DispoCardCompact({ card, categoryOf, width, showVibes, onPress }: {
  card: DiscoveryCard;
  categoryOf: (sportKey: string) => string | undefined;
  width?: number;
  // Découverte page: the vibes line under the intro (the home stays shorter).
  showVibes?: boolean;
  onPress: () => void;
}) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const relColor = reliabilityColorForTier(card.reliability_tier, colors);
  const stateLabel = card.is_demo
    ? t('partenaires.stateDemo', { defaultValue: 'Démo' })
    : card.contact_state === 'connected'
      ? t('partenaires.stateConnected', { defaultValue: 'En contact' })
      : card.contact_state === 'pending'
        ? t('discovery.contactedShort', { defaultValue: 'Envoyée' })
        : card.contact_state === 'pending_received'
          ? t('partenaires.stateReceived', { defaultValue: 'Te demande' })
          : null;

  return (
    <PressableScale style={[styles.card, width ? { width } : null]} onPress={onPress} accessibilityRole="button">
      <View style={styles.head}>
        <ReliabilityRing tier={card.reliability_tier} size={48} strokeWidth={3} showLabel={false}>
          <UserAvatar name={card.display_name} avatarUrl={card.avatar_url} size={48} />
        </ReliabilityRing>
        <View style={styles.headText}>
          <AppText style={styles.name} numberOfLines={1}>{card.display_name}</AppText>
          {card.reliability_tier ? (
            <AppText style={[styles.tier, { color: relColor }]} numberOfLines={1}>{t(`reliability.tier.${card.reliability_tier}`)}</AppText>
          ) : null}
        </View>
        {stateLabel ? (
          <View style={styles.state}><AppText style={styles.stateText}>{stateLabel}</AppText></View>
        ) : null}
      </View>

      <AppText style={styles.meta} numberOfLines={1}>
        {t('discovery.atKm', { defaultValue: 'à {{km}} km', km: Math.round(card.distance_km) })}
        {' · '}
        {formatPeriod(card.window_start, card.window_end)}
      </AppText>

      <View style={styles.pills}>
        {card.sport_keys.slice(0, 3).map((k) => {
          const c = sportCategoryColor(categoryOf(k), colors.cta);
          return (
            <View key={k} style={[styles.pill, { backgroundColor: c + '1A' }]}>
              <SportIcon sportKey={k} size={13} color={c} />
              <AppText style={[styles.pillText, { color: c }]} numberOfLines={1}>{t(`sports.${k}`, { defaultValue: k })}</AppText>
            </View>
          );
        })}
      </View>

      {card.about ? (
        <AppText style={styles.about} numberOfLines={2}>« {card.about} »</AppText>
      ) : null}
      {(showVibes || !card.about) && card.intent && card.intent.length > 0 ? (
        <AppText style={styles.about} numberOfLines={1}>
          {card.intent.slice(0, 3).map((it) => t(`discovery.intent.${it}`, { defaultValue: INTENT_LABEL[it] })).join('   ')}
        </AppText>
      ) : null}
    </PressableScale>
  );
});

const createStyles = (colors: AppColors) => StyleSheet.create({
  card: {
    backgroundColor: colors.surface,
    borderRadius: 18,
    padding: spacing.md - 2,
    gap: spacing.sm + 2,
    ...shadows.cardFirm,
  },
  head: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm + 2 },
  headText: { flex: 1, minWidth: 0, gap: 2 },
  name: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '700' },
  tier: { fontSize: fontSizes.xs, fontWeight: '600' },
  state: { backgroundColor: colors.surfaceAlt, borderRadius: radius.full, paddingHorizontal: spacing.sm, paddingVertical: 3 },
  stateText: { color: colors.textSecondary, fontSize: 11, fontWeight: '700' },
  meta: { color: colors.textSecondary, fontSize: fontSizes.sm - 1 },
  pills: { flexDirection: 'row', flexWrap: 'wrap', gap: 6 },
  pill: { flexDirection: 'row', alignItems: 'center', gap: 4, borderRadius: radius.full, paddingHorizontal: 9, paddingVertical: 5, maxWidth: '100%' },
  pillText: { fontSize: fontSizes.xs, fontWeight: '600' },
  about: { color: colors.textPrimary, fontSize: fontSizes.sm - 1, lineHeight: 19 },
});
