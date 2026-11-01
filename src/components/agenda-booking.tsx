import { useMemo } from 'react';
import { View, Pressable, StyleSheet } from 'react-native';
import { useTranslation } from 'react-i18next';
import dayjs from 'dayjs';
import { MessageCircle, Phone, AlertCircle, Check } from 'lucide-react-native';
import { AppText } from '@/components/app-text';
import { UserAvatar } from '@/components/user-avatar';
import { SportIcon } from '@/components/sport-icon';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { fontSizes, spacing, radius, shadows } from '@/constants/theme';
import { sportCategoryColor } from '@/utils/sport-category-color';
import type { AgendaItem, BookingPeriod } from '@/services/booking-service';

// Pro agenda building blocks (maquette validée 2026-11-01): a booking reads as
// « what, when, who » with real buttons, and dates say « Matin » / « Après-midi »
// instead of AM/PM.

type TFn = ReturnType<typeof useTranslation>['t'];

const capitalize = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);

export const periodWord = (p: BookingPeriod, t: TFn) =>
  p === 'am' ? t('booking.am', { defaultValue: 'matin' }) : t('booking.pm', { defaultValue: 'après-midi' });

// « Jeu. 5 nov. · Après-midi »
export const bookingWhen = (day: string, period: BookingPeriod, t: TFn) =>
  `${capitalize(dayjs(day).format('ddd D MMM'))} · ${capitalize(periodWord(period, t))}`;

// Filled participant forms vs party size — null when the outing asks for none.
export const formsState = (b: AgendaItem): { done: number; total: number } | null => {
  const asked = (b.participant_fields?.std?.length ?? 0) + (b.participant_fields?.custom?.length ?? 0);
  if (asked === 0 || b.status !== 'accepted') return null;
  return { done: Math.min(b.participant_info?.length ?? 0, b.party_size ?? 0), total: b.party_size ?? 0 };
};

// Square sport tile — solid for a confirmed booking, tinted for a request.
export function SportTile({ b, size = 40 }: { b: AgendaItem; size?: number }) {
  const colors = useColors();
  const c = sportCategoryColor(b.sport_category, colors.cta);
  const solid = b.status === 'accepted';
  return (
    <View style={{
      width: size, height: size, borderRadius: size * 0.28, alignItems: 'center', justifyContent: 'center',
      backgroundColor: solid ? c : c + '1F',
    }}>
      {b.sport_key ? <SportIcon sportKey={b.sport_key} size={size * 0.5} color={solid ? colors.onCta : c} /> : null}
    </View>
  );
}

// « DIM. / 8 / matin » block of the « À venir » rows.
export function DateBlock({ b }: { b: AgendaItem }) {
  const colors = useColors();
  const { t } = useTranslation();
  const c = sportCategoryColor(b.sport_category, colors.cta);
  return (
    <View style={{ width: 56, borderRadius: radius.lg, backgroundColor: c + '1F', alignItems: 'center', paddingVertical: 6 }}>
      <AppText style={{ color: c, fontSize: fontSizes.xs - 2, fontWeight: '800' }}>{dayjs(b.day).format('ddd').toUpperCase()}</AppText>
      <AppText style={{ color: c, fontSize: fontSizes.lg + 2, lineHeight: 24, fontWeight: '800' }}>{dayjs(b.day).date()}</AppText>
      <AppText style={{ color: c, fontSize: fontSizes.xs - 2, fontWeight: '700' }}>
        {b.period === 'am' ? t('booking.halfAm', { defaultValue: 'matin' }) : t('booking.halfPm', { defaultValue: 'a-midi' })}
      </AppText>
    </View>
  );
}

// A booking in the requests list or the day sheet.
//  - request: message + Écrire / Refuser / Accepter
//  - day:     forms state + Écrire (or Appeler) / Détails
export function AgendaBookingCard({ b, variant, onWrite, onCall, onDetails, onAccept, onDecline }: {
  b: AgendaItem;
  variant: 'request' | 'day';
  onWrite?: () => void;
  onCall?: () => void;
  onDetails?: () => void;
  onAccept?: () => void;
  onDecline?: () => void;
}) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const c = sportCategoryColor(b.sport_category, colors.cta);
  const pending = b.status === 'pending';
  const forms = formsState(b);
  const people = t('booking.peopleCount', { defaultValue: '{{count}} personnes', count: b.party_size ?? 0 });
  const source = b.is_manual
    ? t('booking.sourceManual', { defaultValue: 'manuelle' })
    : t('booking.sourceApp', { defaultValue: 'dans l’app' });

  return (
    <View style={[styles.card, pending && { borderStyle: 'dashed', borderWidth: 1.5, borderColor: c + '88' }]}>
      <View style={styles.head}>
        <SportTile b={b} size={variant === 'request' ? 44 : 38} />
        <View style={{ flex: 1, minWidth: 0 }}>
          <AppText style={styles.title} numberOfLines={2}>{b.offering_title ?? '—'}</AppText>
          {variant === 'request' ? (
            <AppText style={[styles.when, { color: c }]}>{bookingWhen(b.day, b.period, t)}</AppText>
          ) : (
            <AppText style={styles.who} numberOfLines={1}>
              <AppText style={styles.whoName}>{b.client_name ?? '—'}</AppText> · {people} · {source}
            </AppText>
          )}
        </View>
        {pending ? (
          <View style={styles.pendingChip}>
            <AppText style={styles.pendingChipText}>{t('booking.status.pending', { defaultValue: 'En attente' })}</AppText>
          </View>
        ) : null}
      </View>

      {variant === 'request' ? (
        <View style={styles.clientRow}>
          <UserAvatar name={b.client_name ?? '?'} avatarUrl={null} size={26} />
          <AppText style={styles.whoName} numberOfLines={1}>{b.client_name ?? '—'}</AppText>
          <AppText style={styles.whoSoft}>· {people}</AppText>
        </View>
      ) : null}

      {variant === 'request' && b.message ? (
        <View style={styles.msgBox}><AppText style={styles.msgText}>« {b.message} »</AppText></View>
      ) : null}

      {variant === 'day' && forms ? (
        forms.done >= forms.total ? (
          <View style={[styles.formsLine, { backgroundColor: colors.cta + '1A' }]}>
            <Check size={14} color={colors.cta} strokeWidth={2.6} />
            <AppText style={[styles.formsText, { color: colors.cta }]}>{t('booking.formsDone', { defaultValue: 'Fiches participants complètes' })}</AppText>
          </View>
        ) : (
          <View style={[styles.formsLine, { backgroundColor: colors.warning + '1A' }]}>
            <AlertCircle size={14} color={colors.warning} strokeWidth={2.4} />
            <AppText style={[styles.formsText, { color: colors.warning }]}>
              {t('booking.formsSummary', { defaultValue: 'Fiches participants : {{done}} sur {{total}}', done: forms.done, total: forms.total })}
            </AppText>
          </View>
        )
      ) : null}

      <View style={styles.actions}>
        {variant === 'request' ? (
          <>
            {onWrite ? (
              <Pressable style={({ pressed }) => [styles.outlineBtn, pressed && styles.pressed]} onPress={onWrite} accessibilityRole="button">
                <MessageCircle size={16} color={colors.textPrimary} strokeWidth={2.2} />
                <AppText style={styles.outlineBtnText}>{t('booking.write', { defaultValue: 'Écrire' })}</AppText>
              </Pressable>
            ) : null}
            <Pressable style={({ pressed }) => [styles.ghostBtn, pressed && styles.pressed]} onPress={onDecline} accessibilityRole="button">
              <AppText style={styles.ghostBtnText}>{t('booking.decline', { defaultValue: 'Refuser' })}</AppText>
            </Pressable>
            <Pressable style={({ pressed }) => [styles.primaryBtn, pressed && styles.pressed]} onPress={onAccept} accessibilityRole="button">
              <AppText style={styles.primaryBtnText}>{t('booking.accept', { defaultValue: 'Accepter' })}</AppText>
            </Pressable>
          </>
        ) : (
          <>
            {onWrite ? (
              <Pressable style={({ pressed }) => [styles.tintBtn, pressed && styles.pressed]} onPress={onWrite} accessibilityRole="button">
                <MessageCircle size={16} color={colors.cta} strokeWidth={2.2} />
                <AppText style={styles.tintBtnText}>{t('booking.write', { defaultValue: 'Écrire' })}</AppText>
              </Pressable>
            ) : onCall ? (
              <Pressable style={({ pressed }) => [styles.tintBtn, pressed && styles.pressed]} onPress={onCall} accessibilityRole="button">
                <Phone size={16} color={colors.cta} strokeWidth={2.2} />
                <AppText style={styles.tintBtnText}>{t('booking.call', { defaultValue: 'Appeler' })}</AppText>
              </Pressable>
            ) : null}
            <Pressable style={({ pressed }) => [styles.outlineBtn, { flex: 1 }, pressed && styles.pressed]} onPress={onDetails} accessibilityRole="button">
              <AppText style={styles.outlineBtnText}>{t('booking.details', { defaultValue: 'Détails' })}</AppText>
            </Pressable>
          </>
        )}
      </View>
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  card: {
    backgroundColor: colors.surface, borderRadius: radius.card, padding: spacing.sm + 4,
    borderWidth: 1, borderColor: colors.lineStrong, gap: spacing.sm + 2, marginBottom: spacing.sm + 2, ...shadows.card,
  },
  head: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm + 2 },
  title: { color: colors.textPrimary, fontSize: fontSizes.sm + 1, fontWeight: '800' },
  when: { fontSize: fontSizes.sm - 1, fontWeight: '600', marginTop: 2 },
  who: { color: colors.textPrimary, fontSize: fontSizes.sm - 1, marginTop: 2 },
  whoName: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '700' },
  whoSoft: { color: colors.textSecondary, fontSize: fontSizes.sm - 1 },
  pendingChip: { backgroundColor: colors.warning + '22', borderRadius: radius.full, paddingHorizontal: 9, paddingVertical: 4 },
  pendingChipText: { color: colors.warning, fontSize: fontSizes.xs - 1, fontWeight: '800' },
  clientRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
  msgBox: { backgroundColor: colors.surfaceAlt, borderRadius: radius.lg, paddingHorizontal: spacing.sm + 4, paddingVertical: spacing.sm + 2 },
  msgText: { color: colors.textPrimary, fontSize: fontSizes.sm - 1, lineHeight: 18 },
  formsLine: { flexDirection: 'row', alignItems: 'center', gap: 6, borderRadius: radius.lg, paddingHorizontal: spacing.sm + 2, paddingVertical: 7 },
  formsText: { fontSize: fontSizes.xs + 1, fontWeight: '600' },
  actions: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
  outlineBtn: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 6,
    borderWidth: 1, borderColor: colors.lineStrong, backgroundColor: colors.surface,
    borderRadius: radius.full, paddingVertical: spacing.sm + 2, paddingHorizontal: spacing.md - 2,
  },
  outlineBtnText: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '700' },
  ghostBtn: { paddingVertical: spacing.sm + 2, paddingHorizontal: spacing.sm + 2 },
  ghostBtnText: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: '600' },
  primaryBtn: {
    flex: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: colors.cta,
    borderRadius: radius.full, paddingVertical: spacing.sm + 3,
  },
  primaryBtnText: { color: colors.onCta, fontSize: fontSizes.sm, fontWeight: '700' },
  tintBtn: {
    flex: 1, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 6,
    backgroundColor: colors.cta + '1F', borderRadius: radius.full, paddingVertical: spacing.sm + 2,
  },
  tintBtnText: { color: colors.cta, fontSize: fontSizes.sm, fontWeight: '700' },
  pressed: { opacity: 0.85, transform: [{ scale: 0.98 }] },
});
