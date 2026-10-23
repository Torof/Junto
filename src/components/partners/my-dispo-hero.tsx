import { useMemo } from 'react';
import { View, StyleSheet, useWindowDimensions } from 'react-native';
import { AppText } from '@/components/app-text';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { useQueryClient } from '@tanstack/react-query';
import * as Burnt from 'burnt';
import { Pause } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, fonts, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { discoveryService, type MyDispo } from '@/services/discovery-service';
import { PressableScale } from '@/components/pressable-scale';
import { SportIcon } from '@/components/sport-icon';
import { ContourLines } from '@/components/partners/contour-lines';
import { formatPeriod } from '@/components/partners/dispo-card-compact';
import { sportCategoryColor } from '@/utils/sport-category-color';
import { getFriendlyError } from '@/utils/friendly-error';

export const radiusLabel = (km: number | null, anyLabel: string) => (km ? `${km} km` : anyLabel);

// « Ta dispo », full card (top of the Découverte page) — three states: live
// (pause / edit), paused (put back online / edit), none yet (compose).
export function MyDispoHero({ mine, categoryOf }: {
  mine: MyDispo | null;
  categoryOf: (k: string) => string | undefined;
}) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const router = useRouter();
  const queryClient = useQueryClient();
  const { width: screenW } = useWindowDimensions();
  const heroW = screenW - spacing.md * 2;
  const edit = () => router.push('/(auth)/discovery-compose');

  const setActive = async (on: boolean) => {
    try {
      if (on) await discoveryService.activate(); else await discoveryService.deactivate();
      await queryClient.invalidateQueries({ queryKey: ['my-dispo'] });
      await queryClient.invalidateQueries({ queryKey: ['discovery-cards'] });
    } catch (e) { Burnt.toast({ title: getFriendlyError(e, 'generic') }); }
  };

  if (!mine) {
    return (
      <View style={styles.empty}>
        <AppText style={styles.emptyTitle}>{t('partenaires.noDispoTitle', { defaultValue: 'Pose ta dispo' })}</AppText>
        <AppText style={styles.emptyBody}>{t('discovery.onbBody', { defaultValue: 'Publie ta dispo — un sport, une zone, des dates — et vois qui cherche la même chose.' })}</AppText>
        <PressableScale style={styles.cta} onPress={edit} accessibilityRole="button">
          <AppText style={styles.ctaText}>{t('discovery.composeDispo', { defaultValue: 'Composer ma dispo' })}</AppText>
        </PressableScale>
      </View>
    );
  }

  const live = mine.is_active;
  return (
    <View style={[styles.hero, !live && styles.paused]}>
      <ContourLines width={heroW} height={180} opacity={0.08} />
      <View style={styles.top}>
        <AppText style={styles.title}>
          {live ? t('discovery.myDispoTitle', { defaultValue: 'Ta dispo' }) : t('partenaires.pausedTitle', { defaultValue: 'Ta dispo est en pause' })}
        </AppText>
        {live ? (
          <View style={styles.livePill}><AppText style={styles.livePillText}>{t('discovery.live', { defaultValue: 'En ligne' })}</AppText></View>
        ) : null}
      </View>
      <AppText style={styles.sub} numberOfLines={1}>
        {formatPeriod(mine.window_start, mine.window_end)} · {mine.base_label} · {radiusLabel(mine.radius_km, t('discovery.radiusAny', { defaultValue: 'Peu importe' }))}
      </AppText>
      <View style={styles.sports}>
        {mine.sport_keys.map((k) => (
          <View key={k} style={[styles.sport, { backgroundColor: sportCategoryColor(categoryOf(k), colors.cta) }]}>
            <SportIcon sportKey={k} size={13} color="#FFFFFF" />
            <AppText style={styles.sportText} numberOfLines={1}>{t(`sports.${k}`, { defaultValue: k })}</AppText>
          </View>
        ))}
      </View>
      <View style={styles.actions}>
        {live ? (
          <PressableScale style={[styles.btn, styles.pause]} onPress={() => setActive(false)} accessibilityRole="button">
            <Pause size={14} color="#FFFFFF" fill="#FFFFFF" strokeWidth={2} />
            <AppText style={styles.pauseText}>{t('partenaires.pause', { defaultValue: 'Mettre en pause' })}</AppText>
          </PressableScale>
        ) : (
          <PressableScale style={[styles.btn, styles.resume]} onPress={() => setActive(true)} accessibilityRole="button">
            <AppText style={styles.resumeText}>{t('partenaires.resume', { defaultValue: 'Remettre en ligne' })}</AppText>
          </PressableScale>
        )}
        <PressableScale style={[styles.btn, styles.edit]} onPress={edit} accessibilityRole="button">
          <AppText style={styles.editText}>{t('discovery.edit', { defaultValue: 'Modifier' })}</AppText>
        </PressableScale>
      </View>
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  hero: {
    marginHorizontal: spacing.md, marginTop: spacing.md, padding: spacing.md, borderRadius: 18,
    backgroundColor: colors.heroInk, overflow: 'hidden', gap: spacing.sm,
  },
  paused: { opacity: 0.88 },
  top: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
  title: { color: '#FFFFFF', fontFamily: fonts.title, fontSize: fontSizes.lg },
  livePill: { backgroundColor: colors.cta, borderRadius: radius.full, paddingHorizontal: 9, paddingVertical: 3 },
  livePillText: { color: '#FFFFFF', fontSize: 11, fontWeight: '800', letterSpacing: 0.4, textTransform: 'uppercase' },
  sub: { color: 'rgba(255,255,255,0.8)', fontSize: fontSizes.sm },
  sports: { flexDirection: 'row', flexWrap: 'wrap', gap: 6 },
  sport: { flexDirection: 'row', alignItems: 'center', gap: 4, borderRadius: radius.full, paddingHorizontal: 10, paddingVertical: 6 },
  sportText: { color: '#FFFFFF', fontSize: fontSizes.xs, fontWeight: '600' },
  actions: { flexDirection: 'row', gap: spacing.sm, marginTop: spacing.xs },
  btn: { flex: 1, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 6, borderRadius: radius.full, paddingVertical: spacing.sm + 2 },
  pause: { backgroundColor: 'rgba(255,255,255,0.15)' },
  pauseText: { color: '#FFFFFF', fontSize: fontSizes.sm, fontWeight: '700' },
  resume: { backgroundColor: colors.cta },
  resumeText: { color: '#FFFFFF', fontSize: fontSizes.sm, fontWeight: '700' },
  edit: { backgroundColor: '#FFFFFF' },
  editText: { color: '#1F1A15', fontSize: fontSizes.sm, fontWeight: '700' },
  empty: {
    marginHorizontal: spacing.md, marginTop: spacing.md, padding: spacing.md + 2, borderRadius: 18,
    backgroundColor: colors.cta + '1A', gap: spacing.sm,
  },
  emptyTitle: { color: colors.textPrimary, fontFamily: fonts.title, fontSize: fontSizes.lg },
  emptyBody: { color: colors.textSecondary, fontSize: fontSizes.sm, lineHeight: 20 },
  cta: { alignSelf: 'flex-start', backgroundColor: colors.cta, borderRadius: radius.full, paddingHorizontal: spacing.md + 2, paddingVertical: spacing.sm + 2, marginTop: spacing.xs },
  ctaText: { color: '#FFFFFF', fontSize: fontSizes.sm + 1, fontWeight: '700' },
});
