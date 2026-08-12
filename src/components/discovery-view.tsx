import { useMemo, useState, type ReactNode } from 'react';
import { View, Text, Pressable, FlatList, StyleSheet, Modal } from 'react-native';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import * as Burnt from 'burnt';
import dayjs from 'dayjs';
import 'dayjs/locale/fr';
import { Car, Bike, Footprints, Bus, Zap } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { discoveryService, type DiscoveryCard, type DispoIntent, type TransportMode } from '@/services/discovery-service';
import { conversationService } from '@/services/conversation-service';
import { UserAvatar } from '@/components/user-avatar';
import { ReliabilityRing } from '@/components/reliability-ring';
import { LogoSpinner } from '@/components/logo-spinner';
import { CollapsibleSection } from '@/components/collapsible-section';
import { sportCategoryColor } from '@/utils/sport-category-color';
import { getSportIcon } from '@/constants/sport-icons';
import { OPEN_LEVEL } from '@/constants/sport-levels';
import { useSports } from '@/hooks/use-sports';
import { getFriendlyError } from '@/utils/friendly-error';

const TRANSPORT_ICON: Record<TransportMode, typeof Car> = {
  car: Car, motorbike: Zap, bike: Bike, on_foot: Footprints, public_transport: Bus,
};
const INTENT_LABEL: Record<DispoIntent, string> = {
  discovery: 'Découverte', progression: 'Progression', performance: 'Performance',
  detente: 'Détente', conviviality: 'Convivialité',
};
const formatPeriod = (start: string, end: string) =>
  `${dayjs(start).locale('fr').format('D MMM')} – ${dayjs(end).locale('fr').format('D MMM')}`;

export function DiscoveryView() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const router = useRouter();
  const queryClient = useQueryClient();
  const [contacted, setContacted] = useState<Set<string>>(new Set());
  const [inviteTargetId, setInviteTargetId] = useState<string | null>(null);

  const { data: invitable, isLoading: invitableLoading } = useQuery({
    queryKey: ['invitable-activities', inviteTargetId],
    queryFn: () => discoveryService.getInvitableActivities(inviteTargetId as string),
    enabled: !!inviteTargetId,
  });


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

  const sportPill = (key: string, level?: string) => {
    const cat = sportById.get(key)?.category;
    const showLevel = level && level !== OPEN_LEVEL;
    return (
      <View key={key} style={[styles.sportPill, { backgroundColor: sportCategoryColor(cat, colors.cta) }]}>
        <Text style={styles.sportPillText}>
          {getSportIcon(key)} {t(`sports.${key}`, { defaultValue: key })}{showLevel ? ` · ${level}` : ''}
        </Text>
      </View>
    );
  };

  // Shared labeled row (fixed-width label column + free value) — used by both
  // "Ta dispo" and the match cards so the two read as the same system.
  const Row = ({ label, children }: { label: string; children: ReactNode }) => (
    <View style={styles.infoRow}>
      <Text style={styles.infoLabel}>{label}</Text>
      <View style={styles.infoValue}>{children}</View>
    </View>
  );
  const transportIcons = (modes: TransportMode[]) => (
    <View style={styles.transportIcons}>
      {modes.map((m) => {
        const Icon = TRANSPORT_ICON[m];
        return Icon ? <Icon key={m} size={16} color={colors.textSecondary} strokeWidth={2.2} /> : null;
      })}
    </View>
  );
  const intentChips = (intents: DispoIntent[]) => (
    <View style={styles.intentWrap}>
      {intents.map((it) => (
        <View key={it} style={styles.intentChip}>
          <Text style={styles.intentChipText}>{t(`discovery.intent.${it}`, { defaultValue: INTENT_LABEL[it] })}</Text>
        </View>
      ))}
    </View>
  );
  const radiusText = (km: number | null) =>
    km ? `${km} km` : t('discovery.radiusAny', { defaultValue: 'Peu importe' });
  const openZone = (params: Record<string, string>) =>
    router.push({ pathname: '/(auth)/discovery-zone', params });

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

      <View style={styles.pillWrap}>{item.sport_keys.map((k) => sportPill(k, item.levels?.[k]))}</View>

      <View style={styles.cardDivider} />

      <View style={styles.infoRows}>
        <Row label={t('discovery.row.when', { defaultValue: 'Quand' })}>
          <Text style={styles.infoText}>{formatPeriod(item.window_start, item.window_end)}</Text>
        </Row>
        <Row label={t('discovery.row.radius', { defaultValue: 'Rayon' })}>
          <View style={styles.radiusValue}>
            <Text style={styles.infoText}>{radiusText(item.radius_km)}</Text>
            <Pressable onPress={() => openZone({ userId: item.user_id, name: item.display_name })} hitSlop={6}>
              <Text style={styles.zoneLink}>{t('discovery.seeZone', { defaultValue: 'Voir la zone' })}</Text>
            </Pressable>
          </View>
        </Row>
        <Row label={t('discovery.row.transport', { defaultValue: 'Trajet' })}>
          {transportIcons(item.transport_modes)}
        </Row>
        {item.intent && item.intent.length > 0 && (
          <Row label={t('discovery.row.intent', { defaultValue: 'Cherche' })}>
            {intentChips(item.intent)}
          </Row>
        )}
      </View>

      <View style={styles.cardDivider} />

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
      {/* My active dispo — collapsible so it stays reviewable without eating
          the list's space (Scott, 2026-08-09). */}
      {mine && (() => {
        const placeText = `${mine.base_label} · ${radiusText(mine.radius_km)}`;
        return (
          <View style={styles.myDispoWrap}>
            <CollapsibleSection
              title={t('discovery.myDispoTitle', { defaultValue: 'Ta dispo' })}
              summary={`${t('discovery.row.sportsCount', { count: mine.sport_keys.length, defaultValue: '{{count}} sports' })} · ${mine.base_label}`}
            >
              <View style={styles.infoRows}>
                <Row label={t('discovery.row.sports', { defaultValue: 'Sports' })}>
                  <View style={styles.pillWrap}>{mine.sport_keys.map((k) => sportPill(k, mine.levels?.[k]))}</View>
                </Row>
                <Row label={t('discovery.row.place', { defaultValue: 'Lieu' })}>
                  <View style={styles.radiusValue}>
                    <Text style={styles.infoText}>{placeText}</Text>
                    <Pressable onPress={() => openZone({ lng: String(mine.base_lng), lat: String(mine.base_lat), radius: mine.radius_km ? String(mine.radius_km) : '', label: mine.base_label })} hitSlop={6}>
                      <Text style={styles.zoneLink}>{t('discovery.seeMyZone', { defaultValue: 'Voir mon rayon' })}</Text>
                    </Pressable>
                  </View>
                </Row>
                <Row label={t('discovery.row.when', { defaultValue: 'Quand' })}>
                  <Text style={styles.infoText}>{formatPeriod(mine.window_start, mine.window_end)}</Text>
                </Row>
                <Row label={t('discovery.row.transport', { defaultValue: 'Trajet' })}>
                  {transportIcons(mine.transport_modes)}
                </Row>
                {mine.intent && mine.intent.length > 0 && (
                  <Row label={t('discovery.row.intent', { defaultValue: 'Cherche' })}>
                    {intentChips(mine.intent)}
                  </Row>
                )}
              </View>
              <View style={styles.myDispoActions}>
                <Pressable onPress={() => router.push('/(auth)/discovery-compose')}><Text style={styles.link}>{t('discovery.edit', { defaultValue: 'Modifier' })}</Text></Pressable>
                <Pressable onPress={handleDeactivate}><Text style={[styles.link, styles.linkDanger]}>{t('discovery.deactivate', { defaultValue: 'Désactiver' })}</Text></Pressable>
              </View>
            </CollapsibleSection>
          </View>
        );
      })()}

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
  myDispoWrap: { paddingHorizontal: spacing.md, backgroundColor: colors.cta + '0D' },
  myDispoActions: { flexDirection: 'row', gap: spacing.lg, marginTop: spacing.md },
  matchesLabel: { color: colors.textSecondary, fontSize: fontSizes.xs, fontWeight: '700', textTransform: 'uppercase', letterSpacing: 0.5, paddingVertical: spacing.sm },
  noMatches: { color: colors.textSecondary, fontSize: fontSizes.md, textAlign: 'center', paddingVertical: spacing.xl, lineHeight: 22 },
  list: { padding: spacing.md },
  card: { backgroundColor: colors.surface, borderWidth: 1, borderColor: colors.borderMuted, borderRadius: radius.lg, padding: spacing.md, marginBottom: spacing.md, gap: spacing.sm },
  cardTop: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
  cardName: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '800' },
  cardSub: { color: colors.textSecondary, fontSize: fontSizes.xs, marginTop: 2 },
  cardDivider: { height: 1, backgroundColor: colors.line },
  pillWrap: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.xs },
  sportPill: { borderRadius: radius.full, paddingHorizontal: spacing.sm + 2, paddingVertical: 4 },
  sportPillText: { color: '#FFFFFF', fontSize: fontSizes.xs, fontWeight: '700' },
  infoRows: { gap: spacing.sm },
  infoRow: { flexDirection: 'row', alignItems: 'flex-start', gap: spacing.sm },
  infoLabel: { width: 62, color: colors.textSecondary, fontSize: fontSizes.xs, fontWeight: '700', textTransform: 'uppercase', letterSpacing: 0.3, paddingTop: 2 },
  infoValue: { flex: 1, minWidth: 0 },
  infoText: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '600' },
  transportIcons: { flexDirection: 'row', flexWrap: 'wrap', alignItems: 'center', gap: spacing.sm },
  intentWrap: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.xs },
  intentChip: { alignSelf: 'flex-start', backgroundColor: colors.cta + '1A', borderRadius: radius.full, paddingHorizontal: spacing.sm + 2, paddingVertical: 3 },
  intentChipText: { color: colors.cta, fontSize: fontSizes.xs, fontWeight: '800' },
  radiusValue: { flexDirection: 'row', flexWrap: 'wrap', alignItems: 'center', gap: spacing.sm },
  zoneLink: { color: colors.cta, fontSize: fontSizes.xs, fontWeight: '700', textDecorationLine: 'underline' },
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
