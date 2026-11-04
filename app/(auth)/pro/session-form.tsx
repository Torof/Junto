import { useEffect, useMemo, useRef, useState } from 'react';
import { View, Pressable, StyleSheet, Platform, Alert } from 'react-native';
import { AppText, AppTextInput } from '@/components/app-text';
import { KeyboardAwareScrollView } from '@/components/keyboard-aware-scroll-view';
import { KeyboardDoneBar } from '@/components/keyboard-done-bar';
import { Stack, useLocalSearchParams, useRouter } from 'expo-router';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import * as Burnt from 'burnt';
import dayjs from 'dayjs';
import DateTimePicker from '@react-native-community/datetimepicker';
import { CalendarDays, Info, Minus, Plus } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { fontSizes, spacing, radius, glow, shadows } from '@/constants/theme';
import { useAuth } from '@/hooks/use-auth';
import { proOfferingService } from '@/services/pro-offering-service';
import { sessionService, type SessionInput } from '@/services/session-service';
import type { BookingPeriod } from '@/services/booking-service';
import { PressableScale } from '@/components/pressable-scale';
import { SportIcon } from '@/components/sport-icon';
import { getFriendlyError } from '@/utils/friendly-error';
import { sportCategoryColor } from '@/utils/sport-category-color';
import { sessionDays, sessionLength, type SessionLength } from '@/utils/session-time';
import { STD_LABELS } from '@/utils/participant-fields';

const MAX_DAYS = 14; // DB: pro_sessions_span

// « Poser une date » (00575, maquette validée 2026-11-02): a date for one of
// the pro's outings — half-day, day or several days — with its places, an
// optional minimum and the meeting point. The participant form and the gear
// come from the outing itself. ?id= edits a date, ?dup= copies one a week
// later, ?offering= preselects the outing.
export default function SessionFormScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t, i18n } = useTranslation();
  const router = useRouter();
  const queryClient = useQueryClient();
  const { session: auth } = useAuth();
  const userId = auth?.user?.id ?? null;
  const { id: editId, dup: dupId, offering: presetOffering } = useLocalSearchParams<{ id?: string; dup?: string; offering?: string }>();

  const { data: offerings } = useQuery({
    queryKey: ['pro-offerings', userId],
    queryFn: () => proOfferingService.getByProId(userId as string),
    enabled: !!userId,
  });
  const sourceId = editId ?? dupId ?? null;
  const { data: mine } = useQuery({
    queryKey: ['my-sessions', 'form'],
    // 14 days back: a multi-day date begun earlier can still be duplicated
    // from the agenda (audit 2026-11-04 — the form opened empty).
    queryFn: () => sessionService.getMine(dayjs().subtract(14, 'day').format('YYYY-MM-DD'), dayjs().add(13, 'month').format('YYYY-MM-DD')),
    enabled: !!sourceId,
  });

  const [offeringId, setOfferingId] = useState<string | null>(presetOffering ?? null);
  const [length, setLength] = useState<SessionLength>('day');
  const [start, setStart] = useState(() => dayjs().add(7, 'day').startOf('day').toDate());
  const [end, setEnd] = useState(() => dayjs().add(9, 'day').startOf('day').toDate());
  const [period, setPeriod] = useState<BookingPeriod>('am');
  const [meeting, setMeeting] = useState('');
  const [places, setPlaces] = useState(6);
  const [minimum, setMinimum] = useState(0); // 0 = none
  const [picker, setPicker] = useState<'start' | 'end' | null>(null);
  const [saving, setSaving] = useState(false);
  // Held from the first tap to the end (conflict check included): a double tap
  // could otherwise publish the date twice.
  const busy = useRef(false);

  // Prefill once from the edited / copied date.
  const prefilled = useRef(false);
  useEffect(() => {
    if (prefilled.current || !sourceId || !mine) return;
    const src = mine.find((s) => s.id === sourceId);
    if (!src) return;
    prefilled.current = true;
    const shift = editId ? 0 : 7;
    setOfferingId(src.offering_id);
    setLength(sessionLength(src));
    setStart(dayjs(src.start_day).add(shift, 'day').toDate());
    setEnd(dayjs(src.end_day).add(shift, 'day').toDate());
    setPeriod(src.start_period);
    setMeeting(src.meeting_point ?? '');
    setPlaces(src.max_participants);
    setMinimum(src.min_participants ?? 0);
  }, [mine, sourceId, editId]);

  const offering = (offerings ?? []).find((o) => o.id === offeringId) ?? null;
  // A new date takes the outing's places and minimum.
  const pickOffering = (id: string) => {
    setOfferingId(id);
    if (editId) return;
    const o = (offerings ?? []).find((x) => x.id === id);
    if (o?.max_participants) setPlaces(o.max_participants);
    setMinimum(o?.min_participants ?? 0);
  };

  const startIso = dayjs(start).format('YYYY-MM-DD');
  const endIso = length === 'multi' ? dayjs(end).format('YYYY-MM-DD') : startIso;
  const win = {
    start_day: startIso,
    start_period: length === 'half' ? period : 'am' as BookingPeriod,
    end_day: endIso,
    end_period: length === 'half' ? period : 'pm' as BookingPeriod,
  };
  const days = sessionDays(win);
  const fmt = (iso: string) => dayjs(iso).locale(i18n.language).format('ddd D MMM');

  const whenHint = length === 'multi'
    ? t('session.formMultiHint', { defaultValue: '{{count}} jours · du {{from}} matin au {{to}} après-midi', count: days, from: fmt(startIso), to: fmt(endIso) })
    : length === 'day'
      ? t('session.formDayHint', { defaultValue: 'Journée entière · matin et après-midi' })
      : t('session.formHalfHint', { defaultValue: 'Une demi-journée' });
  const blockHint = length === 'multi'
    ? t('session.blockMulti', { defaultValue: 'Ces {{count}} jours se ferment dans ton agenda : on ne pourra plus t’y demander d’autre sortie.', count: days })
    : length === 'day'
      ? t('session.blockDay', { defaultValue: 'Cette journée se ferme dans ton agenda : on ne pourra plus t’y demander d’autre sortie.' })
      : t('session.blockHalf', { defaultValue: 'Cette demi-journée se ferme dans ton agenda : on ne pourra plus t’y demander d’autre sortie.' });

  const stdFields = offering?.participant_fields?.std ?? [];
  const customQs = offering?.participant_fields?.custom ?? [];
  const required = offering?.equipment_required ?? [];
  const provided = offering?.equipment_provided ?? [];

  const save = async () => {
    if (!offeringId || saving || busy.current) {
      if (!offeringId) Burnt.toast({ title: t('session.pickOffering', { defaultValue: 'Choisis une sortie' }) });
      return;
    }
    if (length === 'multi' && (days < 2 || days > MAX_DAYS)) {
      Burnt.toast({ title: t('errors.code.session_dates', { defaultValue: 'Vérifie les dates.' }) });
      return;
    }
    const input: SessionInput = {
      ...win,
      max_participants: places,
      min_participants: minimum > 0 ? Math.min(minimum, places) : null,
      meeting_point: meeting.trim() || null,
    };
    const src = editId ? (mine ?? []).find((s) => s.id === editId) : null;
    const moved = !src || src.start_day !== input.start_day || src.start_period !== input.start_period
      || src.end_day !== input.end_day || src.end_period !== input.end_period;

    const run = async () => {
      busy.current = true;
      setSaving(true);
      try {
        if (editId) await sessionService.update(editId, input);
        else await sessionService.create(offeringId, input);
        await queryClient.invalidateQueries({ queryKey: ['pro-agenda'] });
        await queryClient.invalidateQueries({ queryKey: ['my-sessions'] });
        await queryClient.invalidateQueries({ queryKey: ['offering-sessions', offeringId] });
        Burnt.toast({ title: editId ? t('session.savedToast', { defaultValue: 'Date modifiée' }) : t('session.postedToast', { defaultValue: 'Date publiée' }), preset: 'done' });
        router.back();
      } catch (e) {
        Burnt.toast({ title: getFriendlyError(e, 'generic') });
      } finally {
        busy.current = false;
        setSaving(false);
      }
    };
    const release = () => { busy.current = false; };

    // Pending requests on these half-days will be declined: the pro sees who
    // first (option A, Scott 2026-11-02).
    if (moved) {
      busy.current = true;
      try {
        const conflicts = await sessionService.getConflicts(win);
        if (conflicts.length > 0) {
          const list = conflicts
            .map((c) => `• ${c.client_name ?? '—'} — ${fmt(c.day)} ${c.period === 'am' ? t('booking.am', { defaultValue: 'matin' }) : t('booking.pm', { defaultValue: 'après-midi' })}`)
            .join('\n');
          Alert.alert(
            t('session.conflictTitle', { defaultValue: '{{count}} demandes en attente sur ces jours', count: conflicts.length }),
            `${t('session.conflictBody', { defaultValue: 'Elles seront refusées et les clients prévenus. Tu peux d’abord leur répondre depuis l’agenda.' })}\n\n${list}`,
            [
              { text: t('common.cancel', { defaultValue: 'Annuler' }), style: 'cancel', onPress: release },
              { text: t('session.conflictConfirm', { defaultValue: 'Publier quand même' }), style: 'destructive', onPress: () => void run() },
            ],
            { cancelable: true, onDismiss: release },
          );
          return;
        }
      } catch (e) {
        release();
        Burnt.toast({ title: getFriendlyError(e, 'generic') });
        return;
      }
    }
    void run();
  };

  const lengths: { id: SessionLength; label: string }[] = [
    { id: 'half', label: t('session.lenHalf', { defaultValue: 'Demi-journée' }) },
    { id: 'day', label: t('session.lenDay', { defaultValue: 'Journée' }) },
    { id: 'multi', label: t('session.lenMulti', { defaultValue: 'Plusieurs jours' }) },
  ];

  return (
    <View style={styles.container}>
      <Stack.Screen options={{ title: editId ? t('session.editTitle', { defaultValue: 'Modifier la date' }) : t('session.newTitle', { defaultValue: 'Poser une date' }) }} />
      <KeyboardAwareScrollView contentContainerStyle={styles.scroll} showsVerticalScrollIndicator={false}>
        <AppText style={styles.label}>{t('session.outingLabel', { defaultValue: 'Sortie' })}</AppText>
        <View style={styles.offerGrid}>
          {(offerings ?? []).map((o) => {
            const on = offeringId === o.id;
            const c = sportCategoryColor(o.sport_category, colors.cta);
            const locked = !!editId && !on;
            return (
              <Pressable
                key={o.id}
                style={({ pressed }) => [styles.offerTile, on && { borderColor: c, borderWidth: 2 }, locked && { opacity: 0.4 }, pressed && { opacity: 0.85 }]}
                onPress={() => !editId && pickOffering(o.id)}
                disabled={!!editId}
                accessibilityState={{ selected: on }}
              >
                <View style={[styles.offerIcon, { backgroundColor: on ? c : c + '1F' }]}>
                  <SportIcon sportKey={o.sport_key} size={16} color={on ? colors.onCta : c} />
                </View>
                <AppText style={styles.offerTitle} numberOfLines={2}>{o.title}</AppText>
              </Pressable>
            );
          })}
        </View>

        <AppText style={styles.label}>{t('session.lengthLabel', { defaultValue: 'Longueur' })}</AppText>
        <View style={styles.segmented}>
          {lengths.map((l) => (
            <Pressable key={l.id} style={[styles.segment, length === l.id && styles.segmentOn]} onPress={() => {
              setLength(l.id);
              if (l.id === 'multi' && !dayjs(end).isAfter(dayjs(start), 'day')) setEnd(dayjs(start).add(2, 'day').toDate());
            }}>
              <AppText style={[styles.segmentText, length === l.id && styles.segmentTextOn]} numberOfLines={1}>{l.label}</AppText>
            </Pressable>
          ))}
        </View>

        <AppText style={styles.label}>{t('session.whenLabel', { defaultValue: 'Quand' })}</AppText>
        <View style={styles.row}>
          <Pressable style={({ pressed }) => [styles.dateBtn, pressed && { opacity: 0.85 }]} onPress={() => setPicker('start')} accessibilityRole="button">
            <AppText style={styles.dateBtnLabel}>{length === 'multi' ? t('session.start', { defaultValue: 'Début' }) : t('session.day', { defaultValue: 'Jour' })}</AppText>
            <View style={styles.dateBtnRow}>
              <CalendarDays size={15} color={colors.cta} strokeWidth={2.2} />
              <AppText style={styles.dateBtnText}>{fmt(startIso)}</AppText>
            </View>
          </Pressable>
          {length === 'multi' ? (
            <Pressable style={({ pressed }) => [styles.dateBtn, pressed && { opacity: 0.85 }]} onPress={() => setPicker('end')} accessibilityRole="button">
              <AppText style={styles.dateBtnLabel}>{t('session.end', { defaultValue: 'Fin' })}</AppText>
              <View style={styles.dateBtnRow}>
                <CalendarDays size={15} color={colors.cta} strokeWidth={2.2} />
                <AppText style={styles.dateBtnText}>{fmt(endIso)}</AppText>
              </View>
            </Pressable>
          ) : null}
        </View>
        {length === 'half' ? (
          <View style={[styles.segmented, { marginTop: spacing.sm }]}>
            {(['am', 'pm'] as BookingPeriod[]).map((p) => (
              <Pressable key={p} style={[styles.segment, period === p && styles.segmentOn]} onPress={() => setPeriod(p)}>
                <AppText style={[styles.segmentText, period === p && styles.segmentTextOn]}>
                  {p === 'am' ? t('booking.periodAm', { defaultValue: 'Matin' }) : t('booking.periodPm', { defaultValue: 'Après-midi' })}
                </AppText>
              </Pressable>
            ))}
          </View>
        ) : null}
        <AppText style={styles.hint}>{whenHint}</AppText>
        {picker ? (
          <DateTimePicker
            value={picker === 'start' ? start : end}
            mode="date"
            display={Platform.OS === 'ios' ? 'inline' : 'default'}
            minimumDate={picker === 'start' ? new Date() : dayjs(start).add(1, 'day').toDate()}
            maximumDate={picker === 'start' ? dayjs().add(12, 'month').toDate() : dayjs(start).add(MAX_DAYS - 1, 'day').toDate()}
            onChange={(_, d) => {
              const which = picker;
              setPicker(null);
              if (!d) return;
              if (which === 'start') {
                // Keep the length when the start moves.
                const span = dayjs(end).diff(dayjs(start), 'day');
                setStart(d);
                setEnd(dayjs(d).add(Math.max(1, span), 'day').toDate());
              } else {
                setEnd(d);
              }
            }}
          />
        ) : null}

        <AppText style={styles.label}>{t('session.meetingLabel', { defaultValue: 'Rendez-vous' })}</AppText>
        <AppTextInput
          style={styles.input}
          value={meeting}
          onChangeText={setMeeting}
          maxLength={120}
          placeholder={t('session.meetingPlaceholder', { defaultValue: 'Ex. 8 h 00 au parking de Ceillac' })}
          placeholderTextColor={colors.textMuted}
        />

        <View style={styles.box}>
          <View style={styles.boxRow}>
            <View style={{ flex: 1 }}>
              <AppText style={styles.boxTitle}>{t('session.placesLabel', { defaultValue: 'Places' })}</AppText>
              <AppText style={styles.boxSub}>{t('session.placesSub', { defaultValue: 'Par défaut, celles de la sortie' })}</AppText>
            </View>
            <PressableScale style={styles.stepBtn} onPress={() => setPlaces((n) => Math.max(1, n - 1))} accessibilityLabel="−">
              <Minus size={17} color={colors.textPrimary} strokeWidth={2.4} />
            </PressableScale>
            <AppText style={styles.stepVal}>{places}</AppText>
            <PressableScale style={styles.stepBtn} onPress={() => setPlaces((n) => Math.min(50, n + 1))} accessibilityLabel="+">
              <Plus size={17} color={colors.textPrimary} strokeWidth={2.4} />
            </PressableScale>
          </View>
          <View style={[styles.boxRow, styles.boxSep]}>
            <View style={{ flex: 1 }}>
              <AppText style={styles.boxTitle}>{t('session.minLabel', { defaultValue: 'Minimum pour partir' })}</AppText>
              <AppText style={styles.boxSub}>{t('session.minSub', { defaultValue: 'Facultatif · rappel 2 jours avant s’il n’est pas atteint' })}</AppText>
            </View>
            <PressableScale style={styles.stepBtn} onPress={() => setMinimum((n) => Math.max(0, n - 1))} accessibilityLabel="−">
              <Minus size={17} color={colors.textPrimary} strokeWidth={2.4} />
            </PressableScale>
            <AppText style={styles.stepVal}>{minimum > 0 ? minimum : '—'}</AppText>
            <PressableScale style={styles.stepBtn} onPress={() => setMinimum((n) => Math.min(places, n + 1))} accessibilityLabel="+">
              <Plus size={17} color={colors.textPrimary} strokeWidth={2.4} />
            </PressableScale>
          </View>
        </View>

        {offering ? (
          <>
            <AppText style={styles.label}>{t('session.prepLabel', { defaultValue: 'Préparation · reprise de la sortie' })}</AppText>
            <View style={styles.box}>
              <View style={styles.prepRow}>
                <AppText style={styles.boxTitle}>{t('session.prepForm', { defaultValue: 'Fiche participant' })}</AppText>
                {stdFields.length + customQs.length > 0 ? (
                  <View style={styles.chips}>
                    {stdFields.map((f) => (
                      <View key={f} style={styles.chip}><AppText style={styles.chipText}>{t(STD_LABELS[f]?.key ?? f, { defaultValue: STD_LABELS[f]?.fallback ?? f })}</AppText></View>
                    ))}
                    {customQs.map((q) => (
                      <View key={q} style={styles.chip}><AppText style={styles.chipText} numberOfLines={1}>{q}</AppText></View>
                    ))}
                  </View>
                ) : (
                  <AppText style={styles.boxSub}>{t('session.prepNone', { defaultValue: 'Rien de demandé' })}</AppText>
                )}
              </View>
              <View style={[styles.prepRow, styles.boxSep]}>
                <AppText style={styles.boxTitle}>{t('proOffering.equipRequiredLabel', { defaultValue: 'À apporter' })}</AppText>
                <AppText style={styles.prepText}>{required.length > 0 ? required.join(' · ') : '—'}</AppText>
              </View>
              <View style={[styles.prepRow, styles.boxSep]}>
                <AppText style={styles.boxTitle}>{t('session.prepProvided', { defaultValue: 'Fourni' })}</AppText>
                <AppText style={styles.prepText}>{provided.length > 0 ? provided.join(' · ') : '—'}</AppText>
              </View>
            </View>
            <PressableScale onPress={() => router.push(`/(auth)/pro/offering/edit?id=${offering.id}`)} hitSlop={6}>
              <AppText style={styles.link}>{t('session.prepEdit', { defaultValue: 'Modifier dans la sortie ›' })}</AppText>
            </PressableScale>
          </>
        ) : null}

        <View style={styles.note}>
          <Info size={16} color={colors.textSecondary} strokeWidth={2.2} style={{ marginTop: 1 }} />
          <AppText style={styles.noteText}>{blockHint}</AppText>
        </View>

        <PressableScale style={[styles.submit, glow(colors.brand), (saving || !offeringId) && styles.disabled]} onPress={save} disabled={saving}>
          <AppText style={styles.submitText}>
            {saving ? '…' : editId ? t('common.save', { defaultValue: 'Enregistrer' }) : t('session.publish', { defaultValue: 'Publier la date' })}
          </AppText>
        </PressableScale>
      </KeyboardAwareScrollView>
      <KeyboardDoneBar />
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  scroll: { padding: spacing.md, paddingBottom: spacing.xl + 24 },
  label: {
    color: colors.textMuted, fontSize: fontSizes.xs, fontWeight: '800',
    textTransform: 'uppercase', letterSpacing: 0.8, marginTop: spacing.md + 2, marginBottom: spacing.sm,
  },
  offerGrid: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm },
  offerTile: {
    width: '48.5%', flexDirection: 'row', alignItems: 'center', gap: spacing.sm,
    borderWidth: 1, borderColor: colors.lineStrong, borderRadius: radius.lg, padding: spacing.sm + 2,
    backgroundColor: colors.surface,
  },
  offerIcon: { width: 32, height: 32, borderRadius: 10, alignItems: 'center', justifyContent: 'center' },
  offerTitle: { flex: 1, color: colors.textPrimary, fontSize: fontSizes.sm - 1, fontWeight: '700' },
  segmented: { flexDirection: 'row', backgroundColor: colors.surfaceAlt, borderRadius: radius.full, padding: 4 },
  segment: { flex: 1, borderRadius: radius.full, paddingVertical: spacing.sm + 2, alignItems: 'center' },
  segmentOn: { backgroundColor: colors.surface, ...shadows.card },
  segmentText: { color: colors.textSecondary, fontSize: fontSizes.sm - 1, fontWeight: '700' },
  segmentTextOn: { color: colors.textPrimary },
  row: { flexDirection: 'row', gap: spacing.sm },
  dateBtn: {
    flex: 1, borderWidth: 1, borderColor: colors.lineStrong, borderRadius: radius.lg,
    paddingHorizontal: spacing.sm + 4, paddingVertical: spacing.sm + 2, backgroundColor: colors.surface, gap: 2,
  },
  dateBtnLabel: { color: colors.textSecondary, fontSize: fontSizes.xs },
  dateBtnRow: { flexDirection: 'row', alignItems: 'center', gap: 6 },
  dateBtnText: { color: colors.textPrimary, fontSize: fontSizes.sm + 1, fontWeight: '800', textTransform: 'capitalize' },
  hint: { color: colors.textSecondary, fontSize: fontSizes.xs + 1, marginTop: spacing.sm },
  input: {
    borderWidth: 1, borderColor: colors.lineStrong, backgroundColor: colors.surfaceAlt, borderRadius: radius.card - 4,
    paddingHorizontal: spacing.md, paddingVertical: spacing.sm + 3, color: colors.textPrimary, fontSize: fontSizes.sm + 1,
  },
  box: { borderWidth: 1, borderColor: colors.lineStrong, borderRadius: radius.card, marginTop: spacing.md, overflow: 'hidden' },
  boxRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, padding: spacing.md },
  boxSep: { borderTopWidth: 1, borderTopColor: colors.lineStrong },
  boxTitle: { color: colors.textPrimary, fontSize: fontSizes.sm + 1, fontWeight: '700' },
  boxSub: { color: colors.textSecondary, fontSize: fontSizes.xs, marginTop: 1 },
  stepBtn: {
    width: 36, height: 36, borderRadius: radius.full, borderWidth: 1, borderColor: colors.lineStrong,
    backgroundColor: colors.surface, alignItems: 'center', justifyContent: 'center',
  },
  stepVal: { color: colors.textPrimary, fontSize: fontSizes.md + 1, fontWeight: '800', minWidth: 24, textAlign: 'center' },
  prepRow: { padding: spacing.md, gap: 6 },
  prepText: { color: colors.textPrimary, fontSize: fontSizes.sm - 1, lineHeight: 19 },
  chips: { flexDirection: 'row', flexWrap: 'wrap', gap: 6 },
  chip: { backgroundColor: colors.surfaceAlt, borderRadius: radius.full, paddingHorizontal: 10, paddingVertical: 5, maxWidth: '100%' },
  chipText: { color: colors.textPrimary, fontSize: fontSizes.xs, fontWeight: '700' },
  link: { color: colors.cta, fontSize: fontSizes.sm - 1, fontWeight: '700', marginTop: spacing.sm },
  note: { flexDirection: 'row', gap: spacing.sm, backgroundColor: colors.surfaceAlt, borderRadius: radius.card, padding: spacing.md, marginTop: spacing.lg },
  noteText: { flex: 1, color: colors.textPrimary, fontSize: fontSizes.sm - 1, lineHeight: 19 },
  submit: {
    alignItems: 'center', justifyContent: 'center', backgroundColor: colors.brand,
    borderRadius: radius.full, paddingVertical: spacing.sm + 6, marginTop: spacing.lg,
  },
  submitText: { color: colors.onCta, fontSize: fontSizes.md, fontWeight: '800' },
  disabled: { opacity: 0.45 },
});
