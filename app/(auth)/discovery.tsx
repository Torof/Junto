import { useLayoutEffect, useMemo, useState } from 'react';
import { View, Text, Pressable, FlatList, StyleSheet, Modal } from 'react-native';
import { useRouter, useNavigation } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import * as Burnt from 'burnt';
import dayjs from 'dayjs';
import 'dayjs/locale/fr';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { discoveryService, type DiscoveryCard } from '@/services/discovery-service';
import { conversationService } from '@/services/conversation-service';
import { UserAvatar } from '@/components/user-avatar';
import { ReliabilityRing } from '@/components/reliability-ring';
import { LogoSpinner } from '@/components/logo-spinner';
import { sportCategoryColor } from '@/utils/sport-category-color';
import { getSportIcon } from '@/constants/sport-icons';
import { useSports } from '@/hooks/use-sports';
import { getFriendlyError } from '@/utils/friendly-error';

export default function DiscoveryScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const router = useRouter();
  const navigation = useNavigation();
  const queryClient = useQueryClient();
  const [contacted, setContacted] = useState<Set<string>>(new Set());
  const [inviteTargetId, setInviteTargetId] = useState<string | null>(null);

  const { data: invitable, isLoading: invitableLoading } = useQuery({
    queryKey: ['invitable-activities', inviteTargetId],
    queryFn: () => discoveryService.getInvitableActivities(inviteTargetId as string),
    enabled: !!inviteTargetId,
  });

  useLayoutEffect(() => {
    navigation.setOptions({ title: t('discovery.title', { defaultValue: 'Découverte' }) });
  }, [navigation, t]);

  const { data: sports } = useSports();
  const sportById = useMemo(() => new Map((sports ?? []).map((s) => [s.key, s])), [sports]);

  const { data: mine } = useQuery({ queryKey: ['my-dispo'], queryFn: () => discoveryService.getMyDispo() });
  const active = mine?.is_active === true;
  const { data: cards, isLoading } = useQuery({
    queryKey: ['discovery-cards'],
    queryFn: () => discoveryService.getCards(),
    enabled: active,
  });

  const handleDeactivate = async () => {
    try {
      await discoveryService.deactivate();
      await queryClient.invalidateQueries({ queryKey: ['my-dispo'] });
      await queryClient.invalidateQueries({ queryKey: ['discovery-cards'] });
    } catch (e) { Burnt.toast({ title: getFriendlyError(e, 'generic') }); }
  };

  const handleContact = async (userId: string) => {
    try {
      await conversationService.sendContactRequest(userId, t('discovery.contactMessage', { defaultValue: 'Salut ! On matche sur Découverte — ça te dit une sortie ?' }), 'discovery');
      setContacted((prev) => new Set(prev).add(userId));
      Burnt.toast({ title: t('discovery.contactSent', { defaultValue: 'Demande envoyée' }), preset: 'done' });
    } catch (e) { Burnt.toast({ title: getFriendlyError(e, 'generic') }); }
  };

  const handleInvite = async (activityId: string) => {
    const target = inviteTargetId;
    if (!target) return;
    try {
      await discoveryService.sendDiscoveryInvite(target, activityId);
      setContacted((prev) => new Set(prev).add(target));
      setInviteTargetId(null);
      Burnt.toast({ title: t('discovery.inviteSent', { defaultValue: 'Invitation envoyée' }), preset: 'done' });
    } catch (e) { Burnt.toast({ title: getFriendlyError(e, 'generic') }); }
  };

  const sportPill = (key: string) => {
    const cat = sportById.get(key)?.category;
    return (
      <View key={key} style={[styles.sportPill, { backgroundColor: sportCategoryColor(cat, colors.cta) }]}>
        <Text style={styles.sportPillText}>{getSportIcon(key)} {t(`sports.${key}`, { defaultValue: key })}</Text>
      </View>
    );
  };

  const renderCard = ({ item }: { item: DiscoveryCard }) => (
    <View style={styles.card}>
      <View style={styles.cardTop}>
        <Pressable onPress={() => router.push(`/(auth)/profile/${item.user_id}`)} hitSlop={4}>
          <ReliabilityRing tier={item.reliability_tier} size={44} strokeWidth={3} showLabel={false}>
            <UserAvatar name={item.display_name} avatarUrl={item.avatar_url} size={44} />
          </ReliabilityRing>
        </Pressable>
        <View style={{ flex: 1, minWidth: 0 }}>
          <Text style={styles.cardName} numberOfLines={1}>
            {item.display_name} · {t('discovery.atKm', { defaultValue: 'à {{km}} km', km: Math.round(item.distance_km) })}
          </Text>
          <Text style={styles.cardSub}>
            {item.sorties_count > 0
              ? t('discovery.sortiesCount', { defaultValue: '{{count}} sorties', count: item.sorties_count })
              : t('discovery.newcomer', { defaultValue: 'nouveau' })}
          </Text>
        </View>
      </View>

      <View style={styles.pillWrap}>{item.sport_keys.map(sportPill)}</View>

      <View style={styles.actions}>
        <Pressable onPress={() => router.push(`/(auth)/profile/${item.user_id}`)}>
          <Text style={styles.link}>{t('discovery.viewProfile', { defaultValue: 'Voir profil' })}</Text>
        </Pressable>
        <Pressable onPress={() => setInviteTargetId(item.user_id)} disabled={contacted.has(item.user_id)}>
          <Text style={[styles.link, contacted.has(item.user_id) && styles.linkDone]}>
            {t('discovery.invite', { defaultValue: 'Inviter' })}
          </Text>
        </Pressable>
        <Pressable onPress={() => handleContact(item.user_id)} disabled={contacted.has(item.user_id)}>
          <Text style={[styles.link, contacted.has(item.user_id) && styles.linkDone]}>
            {contacted.has(item.user_id) ? t('discovery.contactedShort', { defaultValue: 'Demande envoyée' }) : t('discovery.contact', { defaultValue: 'Contacter' })}
          </Text>
        </Pressable>
      </View>
    </View>
  );

  // No active dispo → invite to compose.
  if (!active) {
    return (
      <View style={styles.empty}>
        <Text style={styles.emptyTitle}>{t('discovery.emptyTitle', { defaultValue: 'Vois qui est dispo pour une sortie' })}</Text>
        <Text style={styles.emptyBody}>{t('discovery.emptyBody', { defaultValue: 'Compose ta dispo (sport, zone, dates) — tu deviens visible et tu vois qui correspond autour de toi.' })}</Text>
        <Pressable style={styles.cta} onPress={() => router.push('/(auth)/discovery-compose')}>
          <Text style={styles.ctaText}>{mine ? t('discovery.editDispo', { defaultValue: 'Reprendre ma dispo' }) : t('discovery.composeDispo', { defaultValue: 'Composer ma dispo' })}</Text>
        </Pressable>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      {/* My active dispo */}
      <View style={styles.myDispo}>
        <View style={styles.pillWrap}>{(mine?.sport_keys ?? []).map(sportPill)}</View>
        <Text style={styles.myDispoMeta}>
          {mine?.base_label}{mine?.radius_km ? ` · ${mine.radius_km} km` : ` · ${t('discovery.radiusAny', { defaultValue: 'peu importe' })}`}
        </Text>
        <View style={styles.actions}>
          <Pressable onPress={() => router.push('/(auth)/discovery-compose')}><Text style={styles.link}>{t('discovery.edit', { defaultValue: 'Modifier' })}</Text></Pressable>
          <Pressable onPress={handleDeactivate}><Text style={[styles.link, styles.linkDanger]}>{t('discovery.deactivate', { defaultValue: 'Désactiver' })}</Text></Pressable>
        </View>
      </View>

      {isLoading ? (
        <View style={styles.center}><LogoSpinner size={40} /></View>
      ) : (
        <FlatList
          data={cards ?? []}
          keyExtractor={(i) => i.user_id}
          renderItem={renderCard}
          contentContainerStyle={styles.list}
          ListHeaderComponent={
            <Text style={styles.matchesLabel}>
              {t('discovery.matchesCount', { defaultValue: '{{count}} correspondances', count: (cards ?? []).length })}
            </Text>
          }
          ListEmptyComponent={
            <Text style={styles.noMatches}>{t('discovery.noMatches', { defaultValue: 'Personne pour l’instant. Reviens plus tard, ou élargis ta zone / tes dates.' })}</Text>
          }
        />
      )}

      {/* Invite picker — pick one of my activities that matches their dispo.
          The request stays a contact request until they accept (gate intact). */}
      <Modal visible={!!inviteTargetId} transparent animationType="slide" onRequestClose={() => setInviteTargetId(null)}>
        <Pressable style={styles.modalBackdrop} onPress={() => setInviteTargetId(null)}>
          <Pressable style={styles.modalSheet} onPress={(e) => e.stopPropagation()}>
            <Text style={styles.modalTitle}>{t('discovery.inviteTitle', { defaultValue: 'Inviter à une sortie' })}</Text>
            {invitableLoading ? (
              <View style={styles.modalCenter}><LogoSpinner size={32} /></View>
            ) : (invitable ?? []).length === 0 ? (
              <Text style={styles.modalEmpty}>
                {t('discovery.inviteEmpty', { defaultValue: 'Aucune de tes sorties ne correspond à sa dispo. Crée une sortie qui matche son sport et ses dates.' })}
              </Text>
            ) : (
              (invitable ?? []).map((a) => (
                <Pressable key={a.id} style={styles.inviteRow} onPress={() => handleInvite(a.id)}>
                  <Text style={styles.inviteRowIcon}>{getSportIcon(a.sport_key)}</Text>
                  <View style={{ flex: 1, minWidth: 0 }}>
                    <Text style={styles.inviteRowTitle} numberOfLines={1}>{a.title}</Text>
                    <Text style={styles.inviteRowMeta}>{dayjs(a.starts_at).locale('fr').format('ddd D MMM · H[h]mm')}</Text>
                  </View>
                </Pressable>
              ))
            )}
            <Pressable style={styles.modalCancel} onPress={() => setInviteTargetId(null)}>
              <Text style={styles.modalCancelText}>{t('common.cancel', { defaultValue: 'Annuler' })}</Text>
            </Pressable>
          </Pressable>
        </Pressable>
      </Modal>
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  empty: { flex: 1, backgroundColor: colors.background, alignItems: 'center', justifyContent: 'center', padding: spacing.xl, gap: spacing.md },
  emptyTitle: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: '800', textAlign: 'center' },
  emptyBody: { color: colors.textSecondary, fontSize: fontSizes.md, textAlign: 'center', lineHeight: 22 },
  cta: { backgroundColor: colors.cta, borderRadius: radius.md, paddingVertical: spacing.sm + 2, paddingHorizontal: spacing.xl, marginTop: spacing.md },
  ctaText: { color: '#FFFFFF', fontSize: fontSizes.md, fontWeight: '800' },
  myDispo: { backgroundColor: colors.cta + '14', borderBottomWidth: 1, borderBottomColor: colors.borderMuted, padding: spacing.md, gap: spacing.sm },
  myDispoMeta: { color: colors.textSecondary, fontSize: fontSizes.sm },
  matchesLabel: { color: colors.textSecondary, fontSize: fontSizes.xs, fontWeight: '700', textTransform: 'uppercase', letterSpacing: 0.5, paddingVertical: spacing.sm },
  noMatches: { color: colors.textSecondary, fontSize: fontSizes.md, textAlign: 'center', paddingVertical: spacing.xl, lineHeight: 22 },
  list: { padding: spacing.md },
  card: { borderWidth: 1, borderColor: colors.borderMuted, borderRadius: radius.md, padding: spacing.md, marginBottom: spacing.sm, gap: spacing.sm },
  cardTop: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
  cardName: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '700' },
  cardSub: { color: colors.textSecondary, fontSize: fontSizes.xs, marginTop: 2 },
  pillWrap: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.xs },
  sportPill: { borderRadius: radius.full, paddingHorizontal: spacing.sm + 2, paddingVertical: 4 },
  sportPillText: { color: '#FFFFFF', fontSize: fontSizes.xs, fontWeight: '700' },
  actions: { flexDirection: 'row', gap: spacing.lg, marginTop: spacing.xs },
  link: { color: colors.cta, fontSize: fontSizes.sm, fontWeight: '700', textDecorationLine: 'underline' },
  linkDone: { color: colors.textSecondary, textDecorationLine: 'none' },
  linkDanger: { color: colors.error },
  modalBackdrop: { flex: 1, backgroundColor: '#00000088', justifyContent: 'flex-end' },
  modalSheet: {
    backgroundColor: colors.background,
    borderTopLeftRadius: radius.xl,
    borderTopRightRadius: radius.xl,
    padding: spacing.lg,
    gap: spacing.sm,
    paddingBottom: spacing.xl,
  },
  modalCenter: { alignItems: 'center', justifyContent: 'center', paddingVertical: spacing.xl },
  modalTitle: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: '800', marginBottom: spacing.xs },
  modalEmpty: { color: colors.textSecondary, fontSize: fontSizes.md, lineHeight: 22, paddingVertical: spacing.md },
  inviteRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
    paddingVertical: spacing.sm + 2,
    borderBottomWidth: 1,
    borderBottomColor: colors.borderMuted,
  },
  inviteRowIcon: { fontSize: 22 },
  inviteRowTitle: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '700' },
  inviteRowMeta: { color: colors.textSecondary, fontSize: fontSizes.sm, marginTop: 2, textTransform: 'capitalize' },
  modalCancel: { alignItems: 'center', paddingVertical: spacing.md, marginTop: spacing.xs },
  modalCancelText: { color: colors.textSecondary, fontSize: fontSizes.md, fontWeight: '700' },
});
