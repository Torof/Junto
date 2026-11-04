import { useMemo, useState } from 'react';
import { View, Pressable, ScrollView, StyleSheet, Switch, Share, Alert, Platform, KeyboardAvoidingView } from 'react-native';
import { AppText, AppTextInput } from '@/components/app-text';
import { Stack } from 'expo-router';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import * as Burnt from 'burnt';
import dayjs from 'dayjs';
import relativeTime from 'dayjs/plugin/relativeTime';
import { CalendarArrowUp, CalendarArrowDown, Share2, RotateCcw, CheckCircle2, AlertCircle } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { fontSizes, spacing, radius, shadows } from '@/constants/theme';
import { calendarLinkService, calendarFeedUrl } from '@/services/calendar-link-service';
import { LogoSpinner } from '@/components/logo-spinner';
import { getFriendlyError } from '@/utils/friendly-error';

dayjs.extend(relativeTime);

// Calendar links (00568, option A validated 2026-11-01):
//  - export: a private iCal link the pro subscribes to once in Google / Apple /
//    Outlook (Google refreshes it on its own schedule, up to ~24 h);
//  - import: the secret iCal address of the pro's calendar — busy half-days
//    become unbookable (read every 15 min, only busy / free is kept).
export default function CalendarSyncScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t, i18n } = useTranslation();
  const queryClient = useQueryClient();

  const { data: links, isLoading, isError, refetch } = useQuery({
    queryKey: ['calendar-links'],
    queryFn: () => calendarLinkService.get(),
  });
  const refresh = () => queryClient.invalidateQueries({ queryKey: ['calendar-links'] });

  const [importUrl, setImportUrl] = useState('');
  const [busy, setBusy] = useState(false);

  const run = async (fn: () => Promise<unknown>, done?: string) => {
    if (busy) return;
    setBusy(true);
    try {
      await fn();
      if (done) Burnt.toast({ title: done, preset: 'done' });
      await refresh();
    } catch (e) { Burnt.toast({ title: getFriendlyError(e, 'generic') }); }
    finally { setBusy(false); }
  };

  const shareFeed = () => {
    if (!links) return;
    Share.share({ message: calendarFeedUrl(links.export_token) }).catch(() => {});
  };

  const regenerate = () => {
    Alert.alert(
      t('calendarSync.regenTitle', { defaultValue: 'Créer un nouveau lien ?' }),
      t('calendarSync.regenBody', { defaultValue: 'L’ancien lien cessera de fonctionner : il faudra ajouter le nouveau dans ton agenda.' }),
      [
        { text: t('activity.no', { defaultValue: 'Non' }), style: 'cancel' },
        { text: t('calendarSync.regenConfirm', { defaultValue: 'Nouveau lien' }), style: 'destructive',
          onPress: () => void run(() => calendarLinkService.regenerateExport(), t('calendarSync.regenDone', { defaultValue: 'Nouveau lien créé' })) },
      ],
    );
  };

  const connect = () => {
    const url = importUrl.trim();
    if (!url) return;
    void run(async () => {
      await calendarLinkService.setImportUrl(url);
      setImportUrl('');
    }, t('calendarSync.importConnected', { defaultValue: 'Agenda branché — première lecture dans 15 min au plus' }));
  };

  const disconnect = () => {
    Alert.alert(
      t('calendarSync.disconnectTitle', { defaultValue: 'Débrancher ton agenda ?' }),
      t('calendarSync.disconnectBody', { defaultValue: 'Les créneaux marqués occupés par ton agenda redeviennent réservables.' }),
      [
        { text: t('activity.no', { defaultValue: 'Non' }), style: 'cancel' },
        { text: t('calendarSync.disconnect', { defaultValue: 'Débrancher' }), style: 'destructive',
          onPress: () => void run(async () => {
            await calendarLinkService.setImportUrl(null);
            await queryClient.invalidateQueries({ queryKey: ['pro-agenda'] });
          }) },
      ],
    );
  };

  const importStatus = () => {
    if (!links?.import_connected) return null;
    if (links.import_error) {
      const reason = t(`calendarSync.error.${links.import_error}`, {
        defaultValue: t('calendarSync.error.unreachable', { defaultValue: 'Ton agenda n’a pas pu être lu. On réessaie toutes les 15 min.' }),
      });
      return { ok: false, text: reason };
    }
    if (!links.import_synced_at) return { ok: true, text: t('calendarSync.importPending', { defaultValue: 'Branché — première lecture dans 15 min au plus.' }) };
    return {
      ok: true,
      text: t('calendarSync.importSynced', {
        defaultValue: 'Branché · lu {{ago}}',
        ago: dayjs(links.import_synced_at).locale(i18n.language).fromNow(),
      }),
    };
  };
  const status = importStatus();

  return (
    <KeyboardAvoidingView style={styles.container} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <Stack.Screen options={{ title: t('calendarSync.title', { defaultValue: 'Synchroniser mon agenda' }) }} />
      {/* An error used to leave the spinner forever (audit 2026-11-04). */}
      {isError && !links ? (
        <View style={[styles.center, { gap: spacing.md, padding: spacing.lg }]}>
          <AppText style={[styles.intro, { textAlign: 'center' }]}>
            {t('calendarSync.loadError', { defaultValue: 'Impossible de charger tes liens d’agenda.' })}
          </AppText>
          <Pressable style={({ pressed }) => [styles.retryBtn, pressed && { opacity: 0.85 }]} onPress={() => void refetch()} accessibilityRole="button">
            <AppText style={styles.retryText}>{t('calendarSync.retry', { defaultValue: 'Réessayer' })}</AppText>
          </Pressable>
        </View>
      ) : isLoading || !links ? (
        <View style={styles.center}><LogoSpinner size={32} /></View>
      ) : (
        <ScrollView contentContainerStyle={styles.scroll} keyboardShouldPersistTaps="handled">
          <AppText style={styles.intro}>
            {t('calendarSync.intro', { defaultValue: 'askandgo reste ton agenda de réservation, et tu continues d’utiliser ton agenda habituel : les deux se parlent.' })}
          </AppText>

          {/* Export */}
          <View style={styles.card}>
            <View style={styles.cardHead}>
              <View style={styles.cardIcon}><CalendarArrowUp size={18} color={colors.cta} strokeWidth={2.2} /></View>
              <View style={{ flex: 1 }}>
                <AppText style={styles.cardTitle}>{t('calendarSync.exportTitle', { defaultValue: 'Mes réservations dans mon agenda' })}</AppText>
                <AppText style={styles.cardSub}>{t('calendarSync.exportSub', { defaultValue: 'Google Agenda, Apple Calendrier, Outlook' })}</AppText>
              </View>
            </View>

            <AppText style={styles.step}>{t('calendarSync.exportStep1', { defaultValue: '1. Envoie-toi ce lien privé (ou copie-le).' })}</AppText>
            <Pressable style={({ pressed }) => [styles.primaryBtn, pressed && styles.pressed]} onPress={shareFeed} accessibilityRole="button">
              <Share2 size={16} color={colors.onCta} strokeWidth={2.2} />
              <AppText style={styles.primaryBtnText}>{t('calendarSync.shareLink', { defaultValue: 'Copier / envoyer le lien' })}</AppText>
            </Pressable>
            <AppText style={styles.step}>
              {t('calendarSync.exportStep2', { defaultValue: '2. Google Agenda sur ordinateur › « Autres agendas » › + › « À partir de l’URL » › colle le lien. Sur iPhone : Réglages › Calendrier › Comptes › Ajouter un calendrier avec abonnement.' })}
            </AppText>
            <AppText style={styles.note}>
              {t('calendarSync.exportDelay', { defaultValue: 'Google met à jour les agendas abonnés à son rythme : une nouvelle réservation peut mettre jusqu’à 24 h à apparaître. askandgo, lui, est toujours à jour.' })}
            </AppText>

            <View style={styles.switchRow}>
              <View style={{ flex: 1 }}>
                <AppText style={styles.switchLabel}>{t('calendarSync.hideNames', { defaultValue: 'Masquer les noms des clients' })}</AppText>
                <AppText style={styles.note}>{t('calendarSync.hideNamesHint', { defaultValue: 'Affiche « Réservation · 3 pers. » si ton agenda est partagé.' })}</AppText>
              </View>
              <Switch
                value={links.hide_names}
                onValueChange={(v) => void run(() => calendarLinkService.setHideNames(v))}
                trackColor={{ false: colors.borderMuted, true: colors.cta }}
                thumbColor={colors.onCta}
              />
            </View>

            <Pressable style={({ pressed }) => [styles.linkBtn, pressed && styles.pressed]} onPress={regenerate} accessibilityRole="button">
              <RotateCcw size={14} color={colors.textSecondary} strokeWidth={2.2} />
              <AppText style={styles.linkBtnText}>{t('calendarSync.regen', { defaultValue: 'Lien partagé par erreur ? Créer un nouveau lien' })}</AppText>
            </Pressable>
          </View>

          {/* Import */}
          <View style={styles.card}>
            <View style={styles.cardHead}>
              <View style={styles.cardIcon}><CalendarArrowDown size={18} color={colors.cta} strokeWidth={2.2} /></View>
              <View style={{ flex: 1 }}>
                <AppText style={styles.cardTitle}>{t('calendarSync.importTitle', { defaultValue: 'Mes indisponibilités dans askandgo' })}</AppText>
                <AppText style={styles.cardSub}>{t('calendarSync.importSub', { defaultValue: 'Un rendez-vous dans ton agenda bloque la demi-journée.' })}</AppText>
              </View>
            </View>

            {status ? (
              <>
                <View style={[styles.status, { backgroundColor: (status.ok ? colors.cta : colors.warning) + '1A' }]}>
                  {status.ok
                    ? <CheckCircle2 size={16} color={colors.cta} strokeWidth={2.4} />
                    : <AlertCircle size={16} color={colors.warning} strokeWidth={2.4} />}
                  <AppText style={[styles.statusText, { color: status.ok ? colors.cta : colors.warning }]}>{status.text}</AppText>
                </View>
                <AppText style={styles.note}>
                  {t('calendarSync.importRule', { defaultValue: 'Matin = 8 h – 13 h, après-midi = 13 h – 19 h. Les événements « disponible » ne bloquent rien. Seul « occupé / libre » est gardé, jamais le contenu de tes rendez-vous.' })}
                </AppText>
                <Pressable style={({ pressed }) => [styles.outlineBtn, pressed && styles.pressed]} onPress={disconnect} accessibilityRole="button">
                  <AppText style={[styles.outlineBtnText, { color: colors.error }]}>{t('calendarSync.disconnect', { defaultValue: 'Débrancher' })}</AppText>
                </Pressable>
              </>
            ) : (
              <>
                <AppText style={styles.step}>
                  {t('calendarSync.importStep1', { defaultValue: '1. Google Agenda sur ordinateur › Paramètres › ton agenda › « Adresse secrète au format iCal » › copie-la.' })}
                </AppText>
                <AppText style={styles.step}>{t('calendarSync.importStep2', { defaultValue: '2. Colle-la ici :' })}</AppText>
                <AppTextInput
                  style={styles.input}
                  value={importUrl}
                  onChangeText={setImportUrl}
                  placeholder="https://calendar.google.com/calendar/ical/…/basic.ics"
                  placeholderTextColor={colors.textMuted}
                  autoCapitalize="none"
                  autoCorrect={false}
                  keyboardType="url"
                  maxLength={500}
                />
                <Pressable
                  style={({ pressed }) => [styles.primaryBtn, (!importUrl.trim() || busy) && { opacity: 0.5 }, pressed && styles.pressed]}
                  onPress={connect}
                  disabled={!importUrl.trim() || busy}
                  accessibilityRole="button"
                >
                  <AppText style={styles.primaryBtnText}>{t('calendarSync.connect', { defaultValue: 'Brancher mon agenda' })}</AppText>
                </Pressable>
                <AppText style={styles.note}>
                  {t('calendarSync.importPrivacy', { defaultValue: 'L’adresse reste sur nos serveurs, on ne garde que « occupé / libre » par demi-journée.' })}
                </AppText>
              </>
            )}
          </View>
        </ScrollView>
      )}
    </KeyboardAvoidingView>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  retryBtn: { backgroundColor: colors.cta, borderRadius: radius.full, paddingVertical: spacing.sm + 2, paddingHorizontal: spacing.lg },
  retryText: { color: colors.onCta, fontSize: fontSizes.sm, fontWeight: '700' },
  scroll: { padding: spacing.md, gap: spacing.md, paddingBottom: spacing.xl },
  intro: { color: colors.textSecondary, fontSize: fontSizes.sm, lineHeight: 20 },
  card: {
    backgroundColor: colors.surface, borderRadius: radius.card, padding: spacing.md,
    borderWidth: 1, borderColor: colors.lineStrong, gap: spacing.sm + 2, ...shadows.card,
  },
  cardHead: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm + 2 },
  cardIcon: { width: 36, height: 36, borderRadius: 11, backgroundColor: colors.cta + '1F', alignItems: 'center', justifyContent: 'center' },
  cardTitle: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '800' },
  cardSub: { color: colors.textSecondary, fontSize: fontSizes.xs + 1, marginTop: 1 },
  step: { color: colors.textPrimary, fontSize: fontSizes.sm, lineHeight: 20 },
  note: { color: colors.textMuted, fontSize: fontSizes.xs + 1, lineHeight: 17 },
  primaryBtn: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 6,
    backgroundColor: colors.cta, borderRadius: radius.full, paddingVertical: spacing.sm + 4,
  },
  primaryBtnText: { color: colors.onCta, fontSize: fontSizes.sm, fontWeight: '700' },
  outlineBtn: {
    alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: colors.lineStrong,
    borderRadius: radius.full, paddingVertical: spacing.sm + 2,
  },
  outlineBtnText: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '700' },
  linkBtn: { flexDirection: 'row', alignItems: 'center', gap: 6, alignSelf: 'flex-start', paddingVertical: 4 },
  linkBtnText: { color: colors.textSecondary, fontSize: fontSizes.xs + 1, fontWeight: '600' },
  switchRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, borderTopWidth: 1, borderTopColor: colors.line, paddingTop: spacing.sm + 2 },
  switchLabel: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '700' },
  status: { flexDirection: 'row', alignItems: 'center', gap: 6, borderRadius: radius.lg, paddingHorizontal: spacing.sm + 2, paddingVertical: spacing.sm },
  statusText: { flex: 1, fontSize: fontSizes.sm - 1, fontWeight: '600' },
  input: {
    borderWidth: 1, borderColor: colors.lineStrong, backgroundColor: colors.surfaceAlt, borderRadius: radius.card - 4,
    paddingHorizontal: spacing.md, paddingVertical: spacing.sm + 3, color: colors.textPrimary, fontSize: fontSizes.sm,
  },
  pressed: { opacity: 0.85, transform: [{ scale: 0.98 }] },
});
