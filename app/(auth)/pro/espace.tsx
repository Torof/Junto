import { useMemo, useState, useCallback } from 'react';
import { View, Pressable, ScrollView, StyleSheet, Alert, Linking, RefreshControl } from 'react-native';
import { AppText } from '@/components/app-text';
import { Stack, useRouter } from 'expo-router';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import * as Burnt from 'burnt';
import dayjs from 'dayjs';
import 'dayjs/locale/fr';
import { CalendarDays, MessagesSquare, Mountain, Eye, Phone, MessageCircle, Plus, ChevronRight, Trash2 } from 'lucide-react-native';
import { Image } from 'expo-image';
import { proOfferingService } from '@/services/pro-offering-service';
import { conversationService } from '@/services/conversation-service';
import { isClientConversation } from '@/utils/client-conversation';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { fontSizes, spacing, radius, shadows, glow } from '@/constants/theme';
import { useAuth } from '@/hooks/use-auth';
import { bookingService, type AgendaItem, type BookingPeriod } from '@/services/booking-service';
import { proService } from '@/services/pro-service';
import { UserAvatar } from '@/components/user-avatar';
import { PressableScale } from '@/components/pressable-scale';
import { getFriendlyError } from '@/utils/friendly-error';
import { sportCategoryColor } from '@/utils/sport-category-color';
import { useDeleteProPage } from '@/hooks/use-delete-pro-page';

export default function ProSpaceScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const router = useRouter();
  const { session } = useAuth();
  const userId = session?.user?.id ?? null;
  const queryClient = useQueryClient();
  const { confirmDelete, deleting } = useDeleteProPage();

  const { data: proProfile } = useQuery({
    queryKey: ['pro-profile', userId],
    queryFn: () => proService.getById(userId as string),
    enabled: !!userId,
  });

  // The agenda RPC asserts an APPROVED pro — a pending one got a silent
  // error and a dashboard pretending « Aucune sortie aujourd'hui ».
  const isApproved = proProfile?.status === 'approved';

  // Fenêtre courte pour le dashboard (aujourd'hui + compteurs 7 j + demandes du mois).
  const from = dayjs().format('YYYY-MM-DD');
  const to = dayjs().add(1, 'month').format('YYYY-MM-DD');
  const { data: agenda, refetch: refetchAgenda } = useQuery({
    queryKey: ['pro-agenda', from, to],
    queryFn: () => bookingService.getAgenda(from, to),
    enabled: isApproved,
  });

  const invalidate = () => queryClient.invalidateQueries({ queryKey: ['pro-agenda'] });

  // Catalogue size for the « Mes sorties » tile (same key as the pro page).
  const { data: offerings } = useQuery({
    queryKey: ['pro-offerings', userId],
    queryFn: () => proOfferingService.getByProId(userId as string),
    enabled: !!userId && isApproved,
  });
  // Client conversations (DMs opened by a confirmed booking, 00451) — the
  // « Messages » tile counts the unread ones and opens the filtered list.
  const { data: conversations } = useQuery({
    queryKey: ['conversations'],
    queryFn: () => conversationService.getAll(),
    enabled: isApproved,
  });
  const unreadClients = (conversations ?? []).filter((c) => isClientConversation(c) && c.is_unread).length;

  // Pull-to-refresh — there is no realtime on bookings, so this is how a
  // pro sees a request that arrived while the screen was open.
  const [refreshing, setRefreshing] = useState(false);
  const onRefresh = useCallback(async () => {
    setRefreshing(true);
    try {
      await Promise.all([
        refetchAgenda(),
        queryClient.invalidateQueries({ queryKey: ['pro-profile', userId] }),
      ]);
    } finally {
      setRefreshing(false);
    }
  }, [refetchAgenda, queryClient, userId]);

  const todayIso = dayjs().format('YYYY-MM-DD');
  const todayBookings = (agenda ?? [])
    .filter((a) => a.kind === 'booking' && a.status === 'accepted' && a.day === todayIso)
    .sort((a, b) => a.period.localeCompare(b.period));
  const pendings = (agenda ?? []).filter((a) => a.kind === 'booking' && a.status === 'pending');
  const week = dayjs().add(7, 'day').format('YYYY-MM-DD');
  const weekBookings = (agenda ?? []).filter(
    (a) => a.kind === 'booking' && a.status === 'accepted' && a.day <= week,
  );
  const weekPeople = weekBookings.reduce((s, b) => s + (b.party_size ?? 0), 0);
  const firstPending = pendings[0];

  const periodTag = (p: BookingPeriod) =>
    p === 'am' ? t('booking.amShort', { defaultValue: 'MATIN' }) : t('booking.pmShort', { defaultValue: 'A-MIDI' });

  const handleAccept = async (b: AgendaItem) => {
    try {
      await bookingService.accept(b.id);
      Burnt.toast({ title: t('booking.acceptedToast', { defaultValue: 'Réservation confirmée' }), preset: 'done' });
      await invalidate();
    } catch (e) { Burnt.toast({ title: getFriendlyError(e, 'generic') }); }
  };
  const handleDecline = (b: AgendaItem) => {
    Alert.alert(
      t('booking.declineConfirmTitle', { defaultValue: 'Refuser cette demande ?' }),
      t('booking.declineConfirmBody', { defaultValue: 'Le client sera prévenu.' }),
      [
        { text: t('activity.no', { defaultValue: 'Non' }), style: 'cancel' },
        {
          text: t('activity.yes', { defaultValue: 'Oui' }),
          style: 'destructive',
          onPress: async () => {
            try {
              await bookingService.decline(b.id);
              await invalidate();
            } catch (e) { Burnt.toast({ title: getFriendlyError(e, 'generic') }); }
          },
        },
      ],
    );
  };

  // Not approved yet (or refused): no dashboard — the RPCs behind the tiles
  // all refuse. One honest state, with the way to the application.
  if (proProfile && !isApproved) {
    const rejected = proProfile.status === 'rejected';
    return (
      <ScrollView style={styles.container} contentContainerStyle={styles.scroll}>
        <Stack.Screen options={{ title: t('booking.proSpace', { defaultValue: 'Espace pro' }) }} />
        <View style={styles.card}>
          <AppText style={styles.headName}>
            {rejected
              ? t('pro.statusRejectedTitle', { defaultValue: 'Demande refusée' })
              : t('pro.statusPendingTitle', { defaultValue: 'Demande en cours de validation' })}
          </AppText>
          <AppText style={[styles.emptyLine, { marginTop: spacing.xs }]}>
            {rejected
              ? (proProfile.rejection_reason || t('pro.bannerRejected', { defaultValue: 'Demande refusée. Corrige tes informations puis renvoie-la.' }))
              : t('pro.pendingBody', { defaultValue: 'Notre équipe vérifie ta demande. Tu reçois une notification dès qu’elle est validée, et ton espace s’ouvre ici.' })}
          </AppText>
          <Pressable
            style={({ pressed }) => [styles.btnPrimary, { marginTop: spacing.md }, pressed && styles.pressed]}
            onPress={() => router.push('/(auth)/pro/edit')}
          >
            <AppText style={styles.btnPrimaryText}>
              {rejected
                ? t('pro.fixApplication', { defaultValue: 'Corriger ma demande' })
                : t('pro.editApplication', { defaultValue: 'Modifier ma demande' })}
            </AppText>
          </Pressable>
        </View>
      </ScrollView>
    );
  }

  return (
    <ScrollView
      style={styles.container}
      contentContainerStyle={styles.scroll}
      refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={colors.cta} colors={[colors.cta]} />}
    >
      <Stack.Screen options={{ title: t('booking.proSpace', { defaultValue: 'Espace pro' }) }} />

      <View style={styles.head}>
        {/* The pin's logo, not an initial (lot 2 pro). */}
        {proProfile?.pin_image_url ? (
          <Image source={{ uri: proProfile.pin_image_url }} style={styles.logo} contentFit="cover" cachePolicy="memory-disk" />
        ) : (
          <UserAvatar name={proProfile?.display_name ?? proProfile?.company_name ?? '?'} avatarUrl={null} size={48} />
        )}
        <View style={{ flex: 1, minWidth: 0 }}>
          <AppText style={styles.headName} numberOfLines={1}>{proProfile?.display_name ?? proProfile?.company_name ?? '…'}</AppText>
          <AppText style={styles.headSub} numberOfLines={1}>
            {t('booking.pagePublic', { defaultValue: 'Page publique active' })}
          </AppText>
        </View>
      </View>

      {/* The hub's one primary action: publishing a new outing used to need
          Mes offres → Catalogue → Nouvelle activité (3 taps, audit 2026-10-08). */}
      <PressableScale style={[styles.newOutingBtn, glow(colors.brand)]} onPress={() => router.push('/(auth)/pro/offering/edit')}>
        <Plus size={18} color={colors.onCta} strokeWidth={2.6} />
        <AppText style={styles.newOutingText}>{t('booking.newOuting', { defaultValue: 'Nouvelle sortie' })}</AppText>
      </PressableScale>

      {/* 00554: the profession feeds the map filter — ask once, discreetly. */}
      {proProfile && !proProfile.profession && (
        <PressableScale style={styles.nudge} onPress={() => router.push('/(auth)/pro/edit')} accessibilityRole="button">
          <AppText style={styles.nudgeText}>{t('pro.professionNudge', { defaultValue: 'Ajoute ton métier : les clients pourront te trouver par filtre.' })}</AppText>
          <ChevronRight size={16} color={colors.cta} strokeWidth={2.6} />
        </PressableScale>
      )}

      <AppText style={styles.eyebrow}>
        {t('booking.today', { defaultValue: 'Aujourd’hui' })} · {dayjs().format('ddd D MMM')}
      </AppText>
      <View style={styles.card}>
        {todayBookings.length === 0 ? (
          <AppText style={styles.emptyLine}>{t('booking.todayNone', { defaultValue: 'Aucune sortie aujourd’hui.' })}</AppText>
        ) : todayBookings.map((b, i) => {
          const sc = sportCategoryColor(b.sport_category, colors.cta);
          return (
            <View key={b.id} style={[styles.todayLine, i > 0 && styles.todaySep]}>
              <View style={[styles.slotChip, { backgroundColor: sc + '1F' }]}>
                <AppText style={[styles.slotChipText, { color: sc }]}>{periodTag(b.period)}</AppText>
              </View>
              <View style={{ flex: 1, minWidth: 0 }}>
                <AppText style={styles.todayName} numberOfLines={1}>{b.client_name ?? '—'} · {b.party_size} pers.</AppText>
                <AppText style={styles.todaySub} numberOfLines={1}>
                  {b.offering_title} · {b.is_manual
                    ? t('booking.manualTag', { defaultValue: 'manuel' })
                    : t('booking.viaJunto', { defaultValue: 'via l’app' })}
                </AppText>
              </View>
              {b.is_manual && b.manual_phone ? (
                <PressableScale style={styles.roundBtn} onPress={() => Linking.openURL(`tel:${b.manual_phone}`)} accessibilityLabel={t('booking.call', { defaultValue: 'Appeler' })}>
                  <Phone size={15} color={colors.textSecondary} strokeWidth={2.2} />
                </PressableScale>
              ) : !b.is_manual && b.client_id ? (
                <PressableScale style={styles.roundBtn} onPress={() => router.push(`/(auth)/profile/${b.client_id}`)} accessibilityLabel={t('booking.clientProfile', { defaultValue: 'Profil client' })}>
                  <MessageCircle size={15} color={colors.textSecondary} strokeWidth={2.2} />
                </PressableScale>
              ) : null}
            </View>
          );
        })}
      </View>

      {pendings.length > 0 && firstPending && (
        <>
          <AppText style={styles.eyebrow}>
            {t('booking.requests', { defaultValue: 'Demandes' })} · {pendings.length}{' '}
            {pendings.length > 1
              ? t('booking.requestsWaitingPlural', { defaultValue: 'en attente' })
              : t('booking.requestsWaiting', { defaultValue: 'en attente' })}
          </AppText>
          <View style={styles.card}>
            <PressableScale
              style={styles.reqHead}
              onPress={() => firstPending.client_id && router.push(`/(auth)/profile/${firstPending.client_id}`)}
              disabled={!firstPending.client_id}
            >
              <UserAvatar name={firstPending.client_name ?? '?'} avatarUrl={null} size={36} />
              <View style={{ flex: 1, minWidth: 0 }}>
                <AppText style={styles.reqName} numberOfLines={1}>
                  {firstPending.client_name ?? '—'} · {firstPending.party_size} pers.
                </AppText>
                <AppText style={[styles.reqMeta, { color: sportCategoryColor(firstPending.sport_category, colors.textSecondary) }]} numberOfLines={1}>
                  {firstPending.offering_title} — {dayjs(firstPending.day).format('ddd D MMM')}, {firstPending.period === 'am' ? t('booking.am', { defaultValue: 'matin' }) : t('booking.pm', { defaultValue: 'après-midi' })}
                </AppText>
              </View>
            </PressableScale>
            {firstPending.message ? <AppText style={styles.reqMsg} numberOfLines={2}>« {firstPending.message} »</AppText> : null}
            <View style={styles.reqActs}>
              <Pressable style={({ pressed }) => [styles.btnGhost, pressed && styles.pressed]} onPress={() => handleDecline(firstPending)}>
                <AppText style={styles.btnGhostText}>{t('booking.decline', { defaultValue: 'Refuser' })}</AppText>
              </Pressable>
              <Pressable style={({ pressed }) => [styles.btnPrimary, pressed && styles.pressed]} onPress={() => handleAccept(firstPending)}>
                <AppText style={styles.btnPrimaryText}>{t('booking.accept', { defaultValue: 'Accepter' })}</AppText>
              </Pressable>
            </View>
          </View>
          {pendings.length > 1 && (
            <PressableScale onPress={() => router.push('/(auth)/pro/agenda')}>
              <AppText style={styles.seeAll}>
                {t('booking.seeAllRequests', { defaultValue: 'Voir les {{count}} demandes ›', count: pendings.length })}
              </AppText>
            </PressableScale>
          )}
        </>
      )}

      <AppText style={styles.eyebrow}>{t('booking.manage', { defaultValue: 'Gérer' })}</AppText>
      <View style={styles.tiles}>
        <Tile
          styles={styles}
          icon={<CalendarDays size={18} color={colors.cta} strokeWidth={2.2} />}
          title={t('booking.agendaTitle', { defaultValue: 'Agenda' })}
          sub={t('booking.hubAgendaSub7', {
            defaultValue: '7 j : {{count}} résas · {{people}} pers.',
            count: weekBookings.length, people: weekPeople,
          })}
          badge={pendings.length || undefined}
          onPress={() => router.push('/(auth)/pro/agenda')}
        />
        <Tile
          styles={styles}
          icon={<Mountain size={18} color={colors.cta} strokeWidth={2.2} />}
          title={t('booking.hubOutings', { defaultValue: 'Mes sorties' })}
          sub={t('booking.hubOutingsCount', { defaultValue: '{{count}} au catalogue', count: offerings?.length ?? 0 })}
          onPress={() => router.push(`/(auth)/pro/${userId}?tab=catalog`)}
        />
        <Tile
          styles={styles}
          icon={<MessagesSquare size={18} color={colors.cta} strokeWidth={2.2} />}
          title={t('booking.hubMessages', { defaultValue: 'Messages' })}
          sub={unreadClients > 0
            ? t('booking.hubMessagesUnread', { defaultValue: '{{count}} non lu', count: unreadClients })
            : t('booking.hubMessagesSub', { defaultValue: 'Conversations clients' })}
          badge={unreadClients || undefined}
          onPress={() => router.push('/(auth)/pro/messages')}
        />
        {/* « Ma page pro » — two explicit actions instead of one tap (Scott 2026-10-31). */}
        <View style={styles.tile}>
          <View style={styles.tileTop}>
            <View style={styles.ico}><Eye size={18} color={colors.cta} strokeWidth={2.2} /></View>
          </View>
          <AppText style={styles.tileTitle}>{t('booking.hubPageShort', { defaultValue: 'Ma page pro' })}</AppText>
          <View style={styles.pageBtns}>
            <PressableScale style={styles.pageBtn} onPress={() => router.push(`/(auth)/pro/${userId}`)} accessibilityRole="button">
              <AppText style={styles.pageBtnText}>{t('booking.hubPageView', { defaultValue: 'Voir' })}</AppText>
            </PressableScale>
            <PressableScale style={styles.pageBtn} onPress={() => router.push('/(auth)/pro/edit')} accessibilityRole="button">
              <AppText style={styles.pageBtnText}>{t('booking.hubPageEdit', { defaultValue: 'Modifier' })}</AppText>
            </PressableScale>
          </View>
        </View>
      </View>

      <Pressable style={styles.deleteBtn} onPress={confirmDelete} disabled={deleting} accessibilityRole="button">
        <Trash2 size={16} color={colors.error} strokeWidth={2.4} />
        <AppText style={styles.deleteBtnText}>
          {deleting
            ? t('pro.deleting', { defaultValue: 'Suppression…' })
            : t('pro.deleteAction', { defaultValue: 'Supprimer ma page pro' })}
        </AppText>
      </Pressable>
    </ScrollView>
  );
}

// Module-level so the tiles keep their identity across renders (defined
// inside the screen, every render remounted the four PressableScale).
function Tile({ icon, title, sub, badge, onPress, styles }: {
  icon: React.ReactNode; title: string; sub: string; badge?: number; onPress: () => void;
  styles: ReturnType<typeof createStyles>;
}) {
  return (
    <PressableScale style={styles.tile} onPress={onPress} accessibilityLabel={title}>
      <View style={styles.tileTop}>
        <View style={styles.ico}>{icon}</View>
        {badge ? <View style={styles.badge}><AppText style={styles.badgeText}>{badge}</AppText></View> : null}
      </View>
      <AppText style={styles.tileTitle}>{title}</AppText>
      <AppText style={styles.tileSub} numberOfLines={1}>{sub}</AppText>
    </PressableScale>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  scroll: { padding: spacing.md, paddingBottom: spacing.xl },
  deleteBtn: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 8,
    paddingVertical: spacing.sm + 2, marginTop: spacing.xl,
  },
  deleteBtnText: { color: colors.error, fontSize: fontSizes.sm, fontWeight: '700' },
  head: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm + 4, marginBottom: spacing.sm + 4 },
  logo: { width: 48, height: 48, borderRadius: radius.card - 2, backgroundColor: colors.surfaceAlt },
  newOutingBtn: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: spacing.sm,
    backgroundColor: colors.brand, borderRadius: radius.full, paddingVertical: spacing.sm + 6,
  },
  newOutingText: { color: colors.onCta, fontSize: fontSizes.md, fontWeight: '700' },
  headName: { color: colors.textPrimary, fontSize: fontSizes.md + 1, fontWeight: '800' },
  headSub: { color: colors.cta, fontSize: fontSizes.xs + 1, marginTop: 1, fontWeight: '600' },
  nudge: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.sm,
    backgroundColor: colors.cta + '14', borderRadius: radius.card, paddingHorizontal: spacing.md, paddingVertical: spacing.sm + 4,
    marginTop: spacing.md,
  },
  nudgeText: { flex: 1, color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '600', lineHeight: 19 },
  eyebrow: {
    color: colors.textMuted, fontSize: fontSizes.xs, fontWeight: '800',
    textTransform: 'uppercase', letterSpacing: 0.8, marginTop: spacing.md + 2, marginBottom: spacing.sm,
  },
  card: { backgroundColor: colors.surface, borderRadius: radius.card, padding: spacing.md, borderWidth: 1, borderColor: colors.lineStrong, ...shadows.card },
  emptyLine: { color: colors.textSecondary, fontSize: fontSizes.sm },
  todayLine: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm + 2, paddingVertical: 4 },
  todaySep: { borderTopWidth: 1, borderTopColor: colors.textMuted + '1A', marginTop: spacing.sm, paddingTop: spacing.sm + 4 },
  slotChip: { minWidth: 52, alignItems: 'center', borderRadius: 9, paddingHorizontal: 7, paddingVertical: 5 },
  slotChipText: { fontSize: fontSizes.xs - 1, fontWeight: '800' },
  todayName: { color: colors.textPrimary, fontSize: fontSizes.sm + 1, fontWeight: '700' },
  todaySub: { color: colors.textSecondary, fontSize: fontSizes.xs + 1, marginTop: 1 },
  roundBtn: {
    width: 32, height: 32, borderRadius: 16, backgroundColor: colors.surfaceAlt,
    borderWidth: 1, borderColor: colors.lineStrong,
    alignItems: 'center', justifyContent: 'center',
  },
  reqHead: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm + 2 },
  reqName: { color: colors.textPrimary, fontSize: fontSizes.sm + 1, fontWeight: '700' },
  reqMeta: { fontSize: fontSizes.sm - 1, marginTop: 1, fontWeight: '600' },
  reqMsg: { color: colors.textSecondary, fontSize: fontSizes.xs + 1, fontStyle: 'italic', marginTop: spacing.sm },
  reqActs: { flexDirection: 'row', gap: spacing.sm, marginTop: spacing.sm + 2, alignItems: 'center' },
  btnGhost: { paddingVertical: spacing.sm + 1, paddingHorizontal: spacing.md, borderRadius: radius.full },
  btnGhostText: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: '600' },
  btnPrimary: {
    flex: 1, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 6,
    backgroundColor: colors.cta, borderRadius: radius.full, paddingVertical: spacing.sm + 2, paddingHorizontal: spacing.md,
  },
  btnPrimaryText: { color: colors.onCta, fontSize: fontSizes.sm, fontWeight: '700' },
  seeAll: { color: colors.cta, fontSize: fontSizes.sm, fontWeight: '700', textAlign: 'center', paddingVertical: spacing.sm },
  pressed: { opacity: 0.85, transform: [{ scale: 0.98 }] },
  tiles: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm + 2 },
  tile: {
    width: '48%', flexGrow: 1, backgroundColor: colors.surface,
    borderRadius: radius.card, padding: spacing.sm + 5,
    borderWidth: 1, borderColor: colors.lineStrong, ...shadows.card,
  },
  tileTop: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginBottom: spacing.sm },
  ico: {
    width: 32, height: 32, borderRadius: radius.lg + 2, backgroundColor: colors.cta + '18',
    alignItems: 'center', justifyContent: 'center',
  },
  tileTitle: { color: colors.textPrimary, fontSize: fontSizes.sm + 1, fontWeight: '800' },
  tileSub: { color: colors.textSecondary, fontSize: fontSizes.xs + 1, marginTop: 2 },
  pageBtns: { flexDirection: 'row', gap: spacing.xs + 2, marginTop: spacing.sm },
  pageBtn: {
    flex: 1, alignItems: 'center', paddingVertical: spacing.xs + 3, borderRadius: radius.full,
    backgroundColor: colors.cta + '18',
  },
  pageBtnText: { color: colors.cta, fontSize: fontSizes.sm - 1, fontWeight: '700' },
  badge: {
    minWidth: 20, height: 20, borderRadius: 10, backgroundColor: colors.error,
    alignItems: 'center', justifyContent: 'center', paddingHorizontal: 6,
  },
  badgeText: { color: '#FFFFFF', fontSize: fontSizes.xs - 1, fontWeight: '800' },
  foot: { textAlign: 'center', color: colors.textMuted, fontSize: fontSizes.xs, marginTop: spacing.md },
});
