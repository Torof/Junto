import { useEffect, useMemo, useRef } from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import BottomSheet, { BottomSheetView } from '@gorhom/bottom-sheet';
import { Image } from 'expo-image';
import dayjs from 'dayjs';
import 'dayjs/locale/fr';
import { useTranslation } from 'react-i18next';
import { Calendar, BarChart2, Users, ChevronRight } from 'lucide-react-native';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import { type NearbyActivity } from '@/services/activity-service';
import { type NearbyPro } from '@/services/pro-service';
import { type ProOffering } from '@/services/pro-offering-service';
import { getSportIcon } from '@/constants/sport-icons';
import { sportCategoryColor } from '@/utils/sport-category-color';
import { formatDifficultySignal } from '@/constants/sport-levels';
import { getRemainingPlaces } from '@/utils/activity-status';

// Google-style preview that slides up on a pin tap (replaces the old
// pin-anchored tooltip). The map stays visible behind it; drag down to
// dismiss. "Voir plus" opens the full page. Content + height adapt to the
// pin type (UA info-led/no image, RA + PP show their photo).
export type PinPreviewSelection =
  | { kind: 'activity'; data: NearbyActivity }
  | { kind: 'pro'; data: NearbyPro }
  | { kind: 'offering'; data: ProOffering };

interface Props {
  selection: PinPreviewSelection | null;
  onClose: () => void;
  onSeeMore: (selection: PinPreviewSelection) => void;
}

function ratingLabel(avg?: number | null, count?: number | null): string | null {
  if (!count || avg == null) return null;
  const n = Number(avg);
  const a = Number.isInteger(n) ? String(n) : n.toFixed(1).replace(/\.0$/, '');
  return `${a} ★ (${count})`;
}

export function PinPreviewSheet({ selection, onClose, onSeeMore }: Props) {
  const { t, i18n } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const sheetRef = useRef<BottomSheet>(null);

  useEffect(() => {
    if (selection) sheetRef.current?.snapToIndex(0);
    else sheetRef.current?.close();
  }, [selection]);

  return (
    <BottomSheet
      ref={sheetRef}
      index={-1}
      enableDynamicSizing
      enablePanDownToClose
      onClose={onClose}
      backgroundStyle={styles.sheetBg}
      handleIndicatorStyle={styles.grabber}
    >
      <BottomSheetView style={styles.content}>
        {selection?.kind === 'activity' && <ActivityPreview activity={selection.data} />}
        {selection?.kind === 'offering' && <OfferingPreview offering={selection.data} />}
        {selection?.kind === 'pro' && <ProPreview pro={selection.data} />}

        {selection && (
          <Pressable style={styles.cta} onPress={() => onSeeMore(selection)}>
            <Text style={styles.ctaText}>{t('map.seeMore', { defaultValue: 'Voir plus' })}</Text>
            <ChevronRight size={16} color={colors.surface} strokeWidth={2.6} />
          </Pressable>
        )}
      </BottomSheetView>
    </BottomSheet>
  );

  function ActivityPreview({ activity }: { activity: NearbyActivity }) {
    const remaining = getRemainingPlaces(activity.max_participants, activity.participant_count);
    const isFull = remaining <= 0;
    const isOpen = activity.max_participants === null;
    const accent = sportCategoryColor(activity.sport_category, colors.cta);
    const signal = formatDifficultySignal(
      activity.sport_key, activity.level, activity.distance_km, activity.elevation_gain_m, activity.level_max,
    );
    return (
      <View style={styles.body}>
        <View style={styles.titleRow}>
          <Text style={styles.sportEmoji}>{getSportIcon(activity.sport_key)}</Text>
          <Text style={[styles.title, { color: accent }]} numberOfLines={2}>{activity.title}</Text>
        </View>
        <View style={styles.chipsRow}>
          <View style={[styles.sportChip, { backgroundColor: accent + '22', borderColor: accent }]}>
            <Text style={[styles.sportChipText, { color: accent }]} numberOfLines={1}>
              {t(`sports.${activity.sport_key}`, activity.sport_key)}
            </Text>
          </View>
          <View style={[styles.placesChip, isFull && styles.placesChipFull]}>
            <Text style={[styles.placesChipText, isFull && styles.placesChipTextFull]}>
              {isOpen
                ? `${activity.participant_count} · ${t('create.openActivityValue')}`
                : `${activity.participant_count}/${activity.max_participants}`}
            </Text>
          </View>
        </View>
        {activity.objective_name ? (
          <Text style={styles.objective} numberOfLines={1}>📍 {activity.objective_name}</Text>
        ) : null}
        <View style={styles.metaRow}>
          <Calendar size={14} color={colors.textPrimary} strokeWidth={2} />
          <Text style={styles.meta}>
            {dayjs(activity.starts_at).locale(i18n.language).format('ddd D MMM [à] H[h]mm')}
          </Text>
        </View>
        {signal ? (
          <View style={styles.metaRow}>
            <BarChart2 size={14} color={colors.textPrimary} strokeWidth={2} />
            <Text style={styles.meta}>{signal}</Text>
          </View>
        ) : null}
        <View style={styles.metaRow}>
          <Users size={14} color={colors.textPrimary} strokeWidth={2} />
          <Text style={styles.meta} numberOfLines={1}>{activity.creator_name}</Text>
        </View>
      </View>
    );
  }

  function OfferingPreview({ offering }: { offering: ProOffering }) {
    const accent = sportCategoryColor(offering.sport_category, colors.cta);
    const rating = ratingLabel(offering.avg_rating, offering.review_count);
    return (
      <View style={styles.bodyWithImage}>
        {offering.image_url ? (
          <Image source={offering.image_url} style={styles.thumb} contentFit="cover" />
        ) : null}
        <View style={styles.bodyCol}>
          <Text style={styles.kicker}>RENDEZ-VOUS PRO</Text>
          <Text style={[styles.title, { color: accent }]} numberOfLines={2}>{offering.title}</Text>
          {offering.schedule_text ? (
            <View style={styles.metaRow}>
              <Calendar size={14} color={colors.textPrimary} strokeWidth={2} />
              <Text style={styles.meta} numberOfLines={2}>{offering.schedule_text}</Text>
            </View>
          ) : null}
          {rating ? <Text style={styles.rating}>{rating}</Text> : null}
          <Text style={styles.proName} numberOfLines={1}>{offering.pro_name}</Text>
        </View>
      </View>
    );
  }

  function ProPreview({ pro }: { pro: NearbyPro }) {
    const accent = (pro.pin_icon && sportCategoryColor(pro.pin_icon, colors.pinProBackground)) || colors.pinProBackground;
    const rating = ratingLabel(pro.avg_rating, pro.review_count);
    return (
      <View style={styles.bodyWithImage}>
        {pro.pin_image_url ? (
          <Image source={pro.pin_image_url} style={styles.thumb} contentFit="cover" />
        ) : null}
        <View style={styles.bodyCol}>
          <Text style={styles.kicker}>PAGE PRO</Text>
          <Text style={[styles.title, { color: accent }]} numberOfLines={1}>{pro.display_name}</Text>
          {rating ? <Text style={styles.rating}>{rating}</Text> : null}
          {pro.tagline ? <Text style={styles.tagline} numberOfLines={2}>{pro.tagline}</Text> : null}
        </View>
      </View>
    );
  }
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  sheetBg: {
    backgroundColor: colors.surface,
    borderTopLeftRadius: radius.lg,
    borderTopRightRadius: radius.lg,
  },
  grabber: {
    backgroundColor: colors.textMuted,
    width: 40,
  },
  content: {
    paddingHorizontal: spacing.lg,
    paddingBottom: spacing.xl,
    gap: spacing.md,
  },
  body: { gap: spacing.xs },
  bodyWithImage: { flexDirection: 'row', gap: spacing.md },
  bodyCol: { flex: 1, gap: spacing.xs, minWidth: 0 },
  thumb: { width: 92, height: 92, borderRadius: radius.md, backgroundColor: colors.surfaceAlt },
  titleRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
  sportEmoji: { fontSize: 22 },
  title: { fontSize: fontSizes.lg, fontWeight: 'bold', flex: 1 },
  kicker: { fontSize: 10, fontWeight: '800', letterSpacing: 1, color: colors.textSecondary },
  chipsRow: { flexDirection: 'row', alignItems: 'center', gap: 6 },
  sportChip: {
    paddingHorizontal: 8, paddingVertical: 2, borderRadius: 999, borderWidth: 1, flexShrink: 1, minWidth: 0,
  },
  sportChipText: { fontSize: 10, fontWeight: '800', letterSpacing: 0.6, textTransform: 'uppercase' },
  placesChip: { backgroundColor: colors.success + '33', paddingHorizontal: 8, paddingVertical: 2, borderRadius: 999 },
  placesChipFull: { backgroundColor: colors.error + '33' },
  placesChipText: { color: colors.success, fontSize: 9, fontWeight: '700', letterSpacing: 0.6 },
  placesChipTextFull: { color: colors.error },
  objective: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '600' },
  metaRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.xs },
  meta: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '600', flex: 1 },
  rating: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '700' },
  proName: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: '600' },
  tagline: { color: colors.textPrimary, fontSize: fontSizes.sm, fontStyle: 'italic' },
  cta: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 4,
    backgroundColor: colors.cta, borderRadius: radius.md, paddingVertical: spacing.sm,
  },
  ctaText: { color: colors.surface, fontSize: fontSizes.md, fontWeight: '800' },
});
