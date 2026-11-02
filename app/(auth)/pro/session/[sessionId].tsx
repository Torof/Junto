import { useMemo, useState, useEffect } from 'react';
import { View, StyleSheet } from 'react-native';
import { AppText, AppTextInput } from '@/components/app-text';
import { KeyboardAwareScrollView } from '@/components/keyboard-aware-scroll-view';
import { KeyboardDoneBar } from '@/components/keyboard-done-bar';
import { Stack, useLocalSearchParams, useRouter } from 'expo-router';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import * as Burnt from 'burnt';
import dayjs from 'dayjs';
import { Minus, Plus, Check, Backpack, MapPin } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { fontSizes, spacing, radius, glow, shadows } from '@/constants/theme';
import { bookingService, type ParticipantEntry } from '@/services/booking-service';
import { proOfferingService } from '@/services/pro-offering-service';
import { sessionService } from '@/services/session-service';
import { PressableScale } from '@/components/pressable-scale';
import { LogoSpinner } from '@/components/logo-spinner';
import { getFriendlyError } from '@/utils/friendly-error';
import { sportCategoryColor } from '@/utils/sport-category-color';
import { sessionBlockSub, sessionRange } from '@/utils/session-time';
import { STD_LABELS } from '@/utils/participant-fields';

// Sign-up to a fixed date (00575, maquette validée 2026-11-02): no request,
// the place is taken at once. The group form sits on the same screen and is
// optional — finished later from Mes réservations, with reminders (00574).
export default function JoinSessionScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const router = useRouter();
  const queryClient = useQueryClient();
  const { sessionId, offering: offeringId } = useLocalSearchParams<{ sessionId: string; offering: string }>();

  const { data: offering, isLoading: offeringLoading } = useQuery({
    queryKey: ['pro-offering', offeringId],
    queryFn: () => proOfferingService.getById(offeringId ?? ''),
    enabled: !!offeringId,
  });
  const { data: sessions, isLoading: sessionsLoading } = useQuery({
    queryKey: ['offering-sessions', offeringId],
    queryFn: () => sessionService.getForOffering(offeringId ?? ''),
    enabled: !!offeringId,
  });
  const session = (sessions ?? []).find((s) => s.id === sessionId) ?? null;
  const left = session ? Math.max(0, session.max_participants - session.taken) : 0;

  const [partySize, setPartySize] = useState(1);
  const [message, setMessage] = useState('');
  const [entries, setEntries] = useState<ParticipantEntry[]>([{}]);
  const [sending, setSending] = useState(false);

  useEffect(() => {
    if (left > 0 && partySize > left) setPartySize(left);
  }, [left, partySize]);
  useEffect(() => {
    setEntries((prev) => Array.from({ length: partySize }, (_, i) => prev[i] ?? {}));
  }, [partySize]);

  const stdFields = offering?.participant_fields?.std ?? [];
  const customQs = offering?.participant_fields?.custom ?? [];
  const asksForm = stdFields.length + customQs.length > 0;

  const setField = (idx: number, key: string, value: string) =>
    setEntries((prev) => prev.map((e, i) => (i === idx ? { ...e, [key]: value } : e)));
  const setCustom = (idx: number, q: string, value: string) =>
    setEntries((prev) => prev.map((e, i) =>
      i === idx ? ({ ...e, custom: { ...(e.custom ?? {}), [q]: value } } as ParticipantEntry) : e,
    ));

  // Only what was typed; a participant left blank is not sent (the form stays
  // « à compléter » for them).
  const filledEntries = (): ParticipantEntry[] => entries
    .map((e) => {
      const out: ParticipantEntry = {};
      for (const f of stdFields) {
        const v = (e[f] ?? '').trim();
        if (v) out[f] = v;
      }
      const cust: Record<string, string> = {};
      for (const q of customQs) {
        const v = (e.custom?.[q] ?? '').trim();
        if (v) cust[q] = v;
      }
      if (Object.keys(cust).length > 0) out.custom = cust;
      return out;
    })
    .filter((e) => Object.keys(e).length > 0);

  const submit = async () => {
    if (!session || sending) return;
    setSending(true);
    try {
      const bookingId = await sessionService.join(session.id, partySize, message.trim() || undefined);
      const filled = asksForm ? filledEntries() : [];
      if (filled.length > 0) {
        // The sign-up stands even if the form fails: it can be finished later.
        try { await bookingService.setParticipantInfo(bookingId, filled); } catch { /* finished from Mes réservations */ }
      }
      await queryClient.invalidateQueries({ queryKey: ['my-bookings'] });
      await queryClient.invalidateQueries({ queryKey: ['offering-sessions', offeringId] });
      Burnt.toast({ title: t('session.joinedToast', { defaultValue: 'Inscription confirmée' }), preset: 'done' });
      router.replace('/(auth)/my-bookings');
    } catch (e) {
      Burnt.toast({ title: getFriendlyError(e, 'generic') });
    } finally {
      setSending(false);
    }
  };

  if (offeringLoading || sessionsLoading || !offering || !session) {
    return (
      <View style={styles.center}>
        <Stack.Screen options={{ title: t('session.joinTitle', { defaultValue: 'Inscription' }) }} />
        {offeringLoading || sessionsLoading
          ? <LogoSpinner size={36} />
          : <AppText style={styles.emptyText}>{t('session.gone', { defaultValue: 'Cette date n’est plus disponible.' })}</AppText>}
      </View>
    );
  }

  const c = sportCategoryColor(offering.sport_category, colors.cta);
  const price = offering.price_eur != null
    ? offering.price_unit === 'group' ? offering.price_eur : offering.price_eur * partySize
    : null;
  const required = offering.equipment_required ?? [];
  const provided = offering.equipment_provided ?? [];

  return (
    <View style={styles.container}>
      <Stack.Screen options={{ title: t('session.joinTitle', { defaultValue: 'Inscription' }) }} />
      <KeyboardAwareScrollView contentContainerStyle={styles.scroll} showsVerticalScrollIndicator={false}>
        <View style={styles.head}>
          <View style={[styles.dateBlock, { backgroundColor: c + '1F' }]}>
            <AppText style={[styles.dateDow, { color: c }]}>{dayjs(session.start_day).format('ddd').toUpperCase()}</AppText>
            <AppText style={[styles.dateNum, { color: c }]}>{dayjs(session.start_day).date()}</AppText>
            <AppText style={[styles.dateSub, { color: c }]}>{sessionBlockSub(session)}</AppText>
          </View>
          <View style={{ flex: 1, minWidth: 0, gap: 2 }}>
            <AppText style={styles.headTitle} numberOfLines={2}>{offering.title}</AppText>
            <AppText style={[styles.headWhen, { color: c }]}>{sessionRange(session)}</AppText>
            {session.meeting_point ? (
              <View style={styles.meetRow}>
                <MapPin size={12} color={colors.textSecondary} strokeWidth={2.2} />
                <AppText style={styles.headSub} numberOfLines={2}>{session.meeting_point}</AppText>
              </View>
            ) : null}
          </View>
        </View>

        <View style={styles.box}>
          <View style={{ flex: 1 }}>
            <AppText style={styles.boxTitle}>{t('booking.partySize', { defaultValue: 'Personnes' })}</AppText>
            <AppText style={styles.boxSub}>{t('session.placesLeft', { defaultValue: '{{count}} places restantes', count: left })}</AppText>
          </View>
          <PressableScale style={styles.stepBtn} onPress={() => setPartySize((s) => Math.max(1, s - 1))} accessibilityLabel="−">
            <Minus size={18} color={colors.textPrimary} strokeWidth={2.4} />
          </PressableScale>
          <AppText style={styles.stepVal}>{partySize}</AppText>
          <PressableScale style={styles.stepBtn} onPress={() => setPartySize((s) => Math.min(Math.max(1, left), s + 1))} accessibilityLabel="+">
            <Plus size={18} color={colors.textPrimary} strokeWidth={2.4} />
          </PressableScale>
        </View>

        <AppText style={styles.fieldLabel}>
          {t('session.messageLabel', { defaultValue: 'Un mot pour {{name}} (facultatif)', name: offering.pro_name })}
        </AppText>
        <AppTextInput
          style={styles.input}
          placeholder={t('booking.messagePlaceholder', { defaultValue: 'Niveau, questions, détails utiles…' })}
          placeholderTextColor={colors.textMuted}
          value={message}
          onChangeText={setMessage}
          multiline
          maxLength={500}
        />

        {required.length + provided.length > 0 ? (
          <View style={styles.gearBox}>
            {required.length > 0 ? (
              <>
                <View style={styles.gearHead}>
                  <Backpack size={14} color={colors.textSecondary} strokeWidth={2.2} />
                  <AppText style={styles.sectionLabelInline}>{t('proOffering.equipRequiredLabel', { defaultValue: 'À apporter' })}</AppText>
                </View>
                <AppText style={styles.gearText}>{required.join(' · ')}</AppText>
              </>
            ) : null}
            {provided.length > 0 ? (
              <AppText style={styles.boxSub}>
                {t('session.providedLine', { defaultValue: 'Fourni : {{list}}', list: provided.join(', ') })}
              </AppText>
            ) : null}
          </View>
        ) : null}

        {asksForm ? (
          <>
            <View style={styles.formHead}>
              <AppText style={styles.sectionLabel}>{t('booking.formTitle', { defaultValue: 'Fiche du groupe' })}</AppText>
              <AppText style={styles.boxSub}>{t('session.formOptional', { defaultValue: 'facultatif maintenant' })}</AppText>
            </View>
            <AppText style={styles.formIntro}>
              {t('session.formIntro', { defaultValue: '{{name}} en a besoin pour préparer le matériel de ton groupe.', name: offering.pro_name })}
            </AppText>
            {entries.map((entry, idx) => (
              <View key={idx} style={styles.pCard}>
                <AppText style={styles.pTitle}>
                  {idx === 0
                    ? t('booking.participantYou', { defaultValue: 'Participant 1 · toi' })
                    : t('booking.participantN', { defaultValue: 'Participant {{n}}', n: idx + 1 })}
                </AppText>
                <View style={styles.fieldsRow}>
                  {stdFields.map((f) => {
                    const meta = STD_LABELS[f];
                    if (!meta) return null;
                    return (
                      <View key={f} style={styles.fieldBox}>
                        <AppText style={styles.pLabel}>{t(meta.key, { defaultValue: meta.fallback })}</AppText>
                        <AppTextInput
                          style={styles.pInput}
                          value={entry[f] ?? ''}
                          onChangeText={(v) => setField(idx, f, v)}
                          keyboardType={meta.keyboard}
                          maxLength={30}
                          placeholder="—"
                          placeholderTextColor={colors.textMuted}
                        />
                      </View>
                    );
                  })}
                </View>
                {customQs.map((q) => (
                  <View key={q} style={{ marginTop: spacing.sm }}>
                    <AppText style={styles.pLabel}>{q}</AppText>
                    <AppTextInput
                      style={styles.pInput}
                      value={entry.custom?.[q] ?? ''}
                      onChangeText={(v) => setCustom(idx, q, v)}
                      maxLength={120}
                      placeholder={t('booking.answerPlaceholder', { defaultValue: 'Ta réponse…' })}
                      placeholderTextColor={colors.textMuted}
                    />
                  </View>
                ))}
              </View>
            ))}
          </>
        ) : null}

        <View style={styles.okNote}>
          <Check size={16} color={colors.cta} strokeWidth={2.6} style={{ marginTop: 1 }} />
          <AppText style={styles.okNoteText}>
            {asksForm
              ? t('session.instantNoteForm', { defaultValue: 'Ta place est réservée tout de suite. Fiche incomplète ? Tu la finis plus tard depuis Mes réservations, on te le rappellera.' })
              : t('session.instantNote', { defaultValue: 'Ta place est réservée tout de suite. Le professionnel peut t’écrire avant le départ.' })}
          </AppText>
        </View>

        {price != null ? (
          <View style={styles.totalRow}>
            <AppText style={styles.boxSub}>{t('session.totalOnSite', { defaultValue: 'Total · paiement sur place' })}</AppText>
            <AppText style={styles.total}>{price} €</AppText>
          </View>
        ) : null}

        <PressableScale
          style={[styles.submit, glow(colors.brand), (sending || left === 0) && styles.disabled]}
          onPress={submit}
          disabled={sending || left === 0}
        >
          <AppText style={styles.submitText}>
            {sending
              ? '…'
              : left === 0
                ? t('booking.full', { defaultValue: 'Complet' })
                : t('session.joinCta', { defaultValue: 'M’inscrire · {{count}} personnes', count: partySize })}
          </AppText>
        </PressableScale>
      </KeyboardAwareScrollView>
      <KeyboardDoneBar />
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  scroll: { padding: spacing.md, paddingBottom: spacing.xl + 24, gap: spacing.md },
  center: { flex: 1, backgroundColor: colors.background, alignItems: 'center', justifyContent: 'center', padding: spacing.lg },
  emptyText: { color: colors.textSecondary, fontSize: fontSizes.sm + 1, lineHeight: 21, textAlign: 'center' },
  head: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.sm + 4,
    backgroundColor: colors.surface, borderRadius: radius.card, padding: spacing.md,
    borderWidth: 1, borderColor: colors.lineStrong, ...shadows.card,
  },
  dateBlock: { width: 58, borderRadius: radius.lg, alignItems: 'center', paddingVertical: 6 },
  dateDow: { fontSize: fontSizes.xs - 2, fontWeight: '800' },
  dateNum: { fontSize: fontSizes.lg + 2, lineHeight: 24, fontWeight: '800' },
  dateSub: { fontSize: fontSizes.xs - 2, fontWeight: '700' },
  headTitle: { color: colors.textPrimary, fontSize: fontSizes.md + 1, fontWeight: '800', letterSpacing: -0.2 },
  headWhen: { fontSize: fontSizes.sm, fontWeight: '700' },
  headSub: { color: colors.textSecondary, fontSize: fontSizes.xs + 1, flexShrink: 1 },
  meetRow: { flexDirection: 'row', alignItems: 'center', gap: 4 },
  box: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.sm,
    borderWidth: 1, borderColor: colors.lineStrong, borderRadius: radius.card, padding: spacing.md,
  },
  boxTitle: { color: colors.textPrimary, fontSize: fontSizes.sm + 1, fontWeight: '700' },
  boxSub: { color: colors.textSecondary, fontSize: fontSizes.xs + 1 },
  stepBtn: {
    borderWidth: 1, borderColor: colors.lineStrong,
    width: 40, height: 40, borderRadius: radius.full, backgroundColor: colors.surfaceAlt,
    alignItems: 'center', justifyContent: 'center',
  },
  stepVal: { color: colors.textPrimary, fontSize: fontSizes.md + 1, fontWeight: '800', minWidth: 26, textAlign: 'center' },
  fieldLabel: {
    color: colors.textMuted, fontSize: fontSizes.xs, fontWeight: '800',
    textTransform: 'uppercase', letterSpacing: 0.5, marginBottom: -spacing.sm,
  },
  input: {
    borderWidth: 1, borderColor: colors.lineStrong,
    backgroundColor: colors.surfaceAlt, borderRadius: radius.card - 4,
    paddingHorizontal: spacing.md, paddingVertical: spacing.sm + 3,
    color: colors.textPrimary, fontSize: fontSizes.sm + 1,
    minHeight: 72, textAlignVertical: 'top',
  },
  gearBox: { borderWidth: 1, borderColor: colors.lineStrong, borderRadius: radius.card, padding: spacing.md, gap: 6 },
  gearHead: { flexDirection: 'row', alignItems: 'center', gap: 6 },
  gearText: { color: colors.textPrimary, fontSize: fontSizes.sm, lineHeight: 20 },
  sectionLabel: {
    color: colors.textMuted, fontSize: fontSizes.xs, fontWeight: '800',
    textTransform: 'uppercase', letterSpacing: 0.8,
  },
  sectionLabelInline: {
    color: colors.textSecondary, fontSize: fontSizes.xs, fontWeight: '800',
    textTransform: 'uppercase', letterSpacing: 0.8,
  },
  formHead: { flexDirection: 'row', alignItems: 'baseline', justifyContent: 'space-between', marginBottom: -spacing.sm },
  formIntro: { color: colors.textPrimary, fontSize: fontSizes.sm, lineHeight: 20 },
  pCard: { borderWidth: 1, borderColor: colors.lineStrong, borderRadius: radius.card, padding: spacing.md },
  pTitle: { color: colors.textPrimary, fontSize: fontSizes.sm + 1, fontWeight: '800', marginBottom: spacing.sm },
  fieldsRow: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm },
  fieldBox: { flexGrow: 1, flexBasis: 90 },
  pLabel: { color: colors.textSecondary, fontSize: fontSizes.xs, fontWeight: '700', marginBottom: 4 },
  pInput: {
    borderWidth: 1, borderColor: colors.lineStrong, backgroundColor: colors.surfaceAlt,
    borderRadius: radius.md, paddingHorizontal: spacing.sm + 2, paddingVertical: spacing.sm,
    color: colors.textPrimary, fontSize: fontSizes.sm + 1, fontWeight: '700',
  },
  okNote: { flexDirection: 'row', gap: spacing.sm, backgroundColor: colors.cta + '1A', borderRadius: radius.card, padding: spacing.md },
  okNoteText: { flex: 1, color: colors.textPrimary, fontSize: fontSizes.sm - 1, lineHeight: 19 },
  totalRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 2 },
  total: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: '800' },
  submit: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 7,
    backgroundColor: colors.brand, borderRadius: radius.full, paddingVertical: spacing.sm + 6,
  },
  submitText: { color: colors.onCta, fontSize: fontSizes.md, fontWeight: '800' },
  disabled: { opacity: 0.45 },
});
