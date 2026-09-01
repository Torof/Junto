import { useMemo, useState, type ReactNode } from 'react';
import { View, Text, Pressable, FlatList, ScrollView, StyleSheet, Modal, LayoutAnimation, Platform, UIManager } from 'react-native';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import * as Burnt from 'burnt';
import dayjs from 'dayjs';
import 'dayjs/locale/fr';
import { Car, Bike, Footprints, Bus, Zap, User, UserPlus, Send, Handshake, Telescope, MapPin, Calendar, LocateFixed } from 'lucide-react-native';
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
import { reliabilityColorForTier } from '@/utils/reliability-color';
import { getSportIcon } from '@/constants/sport-icons';
import { OPEN_LEVEL } from '@/constants/sport-levels';
import { useSports } from '@/hooks/use-sports';
import { getFriendlyError } from '@/utils/friendly-error';

const TRANSPORT_ICON: Record<TransportMode, typeof Car> = {
  car: Car, motorbike: Zap, bike: Bike, on_foot: Footprints, public_transport: Bus,
};
const INTENT_LABEL: Record<DispoIntent, string> = {
  discovery: '🧭 Découverte', progression: '📈 Progression', performance: '🔥 Performance',
  detente: '🍃 Détente', conviviality: '🤝 Convivialité',
  dog: '🐕 Chien', child: '👶 Enfant', group: '👥 En groupe', solo: '🧍 Solo',
  active: '⚡ Actif', calm: '😌 Calme', early: '🌅 Matinal',
  nature: '🌲 Nature', challenge: '🎯 Défi', photo: '📷 Photo',
  mixed: '⚥ Groupe mixte', same_level: '🎚️ Même niveau', beginners: '🌱 Débutants bienvenus',
  long_outing: '🥾 Sortie longue', after_work: '🌆 Après le boulot', regular: '🔁 Partenaire régulier',
  adapted: '♿ Handi / adapté', training: '💪 Entraînement', experienced: '🎖️ Expérimenté',
  competition: '🏁 Prépa compét',
};
const formatPeriod = (start: string, end: string) =>
  `${dayjs(start).locale('fr').format('D MMM')} – ${dayjs(end).locale('fr').format('D MMM')}`;

if (Platform.OS === 'android' && UIManager.setLayoutAnimationEnabledExperimental) {
  UIManager.setLayoutAnimationEnabledExperimental(true);
}

export function DiscoveryView() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const router = useRouter();
  const queryClient = useQueryClient();
  const [contacted, setContacted] = useState<Set<string>>(new Set());
  const [inviteTargetId, setInviteTargetId] = useState<string | null>(null);
  const [openAbout, setOpenAbout] = useState<Set<string>>(new Set());
  const toggleAbout = (id: string) => {
    LayoutAnimation.configureNext(LayoutAnimation.create(180, LayoutAnimation.Types.easeInEaseOut, LayoutAnimation.Properties.opacity));
    setOpenAbout((prev) => { const n = new Set(prev); if (n.has(id)) n.delete(id); else n.add(id); return n; });
  };

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
    const c = sportCategoryColor(cat, colors.cta);
    const showLevel = level && level !== OPEN_LEVEL;
    return (
      <View key={key} style={[styles.sportPill, { backgroundColor: c + '22', borderColor: c + '55' }]}>
        <Text style={[styles.sportPillText, { color: c }]}>
          {getSportIcon(key)} {t(`sports.${key}`, { defaultValue: key })}{showLevel ? ` · ${level}` : ''}
        </Text>
      </View>
    );
  };

  // Shared labeled row (fixed-width label column + free value) — used by both
  // "Ta dispo" and the match cards so the two read as the same system.
  const Row = ({ label, children, stack }: { label: string; children: ReactNode; stack?: boolean }) => (
    <View style={stack ? styles.infoRowStack : styles.infoRow}>
      <Text style={styles.infoLabel}>{label}</Text>
      <View style={stack ? styles.infoValueStack : styles.infoValue}>{children}</View>
    </View>
  );
  const transportIcons = (modes: TransportMode[], size = 16) => (
    <View style={styles.transportIcons}>
      {modes.map((m) => {
        const Icon = TRANSPORT_ICON[m];
        return Icon ? <Icon key={m} size={size} color={colors.textSecondary} strokeWidth={2.2} /> : null;
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
  const renderCard = ({ item }: { item: DiscoveryCard }) => {
    const done = contacted.has(item.user_id);
    const relColor = reliabilityColorForTier(item.reliability_tier, colors);
    return (
      <View style={styles.card}>
        <View style={styles.cardTop}>
          <Pressable onPress={() => router.push(`/(auth)/profile/${item.user_id}`)} hitSlop={4}>
            <ReliabilityRing tier={item.reliability_tier} size={56} strokeWidth={3} showLabel={false}>
              <UserAvatar name={item.display_name} avatarUrl={item.avatar_url} size={56} />
            </ReliabilityRing>
          </Pressable>
          <View style={{ flex: 1, minWidth: 0 }}>
            <View style={styles.nameRow}>
              <Text style={styles.cardName} numberOfLines={1}>{item.display_name}</Text>
              {item.reliability_tier ? (
                <View style={[styles.relChip, { backgroundColor: relColor + '22', borderColor: relColor + '55' }]}>
                  <Text style={[styles.relChipText, { color: relColor }]}>{t(`reliability.tier.${item.reliability_tier}`)}</Text>
                </View>
              ) : null}
            </View>
            <View style={styles.subRow}>
              <MapPin size={13} color={colors.textSecondary} strokeWidth={2.4} />
              <Text style={styles.cardSub} numberOfLines={1}>
                {t('discovery.atKm', { defaultValue: 'à {{km}} km', km: Math.round(item.distance_km) })}
                {' · '}
                {item.sorties_count > 0
                  ? t('discovery.sortiesCount', { defaultValue: '{{count}} sorties', count: item.sorties_count })
                  : t('discovery.newcomer', { defaultValue: 'nouveau' })}
              </Text>
            </View>
            <View style={styles.dateRow}>
              <Calendar size={13} color={colors.textSecondary} strokeWidth={2.2} />
              <Text style={styles.metaText} numberOfLines={1}>{formatPeriod(item.window_start, item.window_end)}</Text>
            </View>
          </View>
        </View>

        <View style={styles.headMeta}>
          <LocateFixed size={13} color={colors.textSecondary} strokeWidth={2.2} />
          <Text style={styles.metaText}>{radiusText(item.radius_km)}</Text>
          <Text style={styles.metaDot}>·</Text>
          {transportIcons(item.transport_modes, 15)}
          <Text style={styles.metaDot}>·</Text>
          <Pressable onPress={() => openZone({ userId: item.user_id, name: item.display_name })} hitSlop={6}>
            <Text style={[styles.metaText, styles.metaZone]}>{t('discovery.seeZone', { defaultValue: 'Voir la zone' })}</Text>
          </Pressable>
        </View>

        <View style={styles.pillWrap}>
          {item.sport_keys.map((k) => sportPill(k, item.levels?.[k]))}
          {item.intent && item.intent.length > 0 && <View style={styles.pillBreak} />}
          {item.intent?.map((it) => (
            <View key={it} style={styles.intentChip}>
              <Text style={styles.intentChipText}>{t(`discovery.intent.${it}`, { defaultValue: INTENT_LABEL[it] })}</Text>
            </View>
          ))}
        </View>

        {item.about ? (
          <View style={styles.aboutCard}>
            <Text style={styles.aboutText} numberOfLines={openAbout.has(item.user_id) ? undefined : 2}>
              {item.about}
            </Text>
            {item.about.length > 110 && (
              <Pressable onPress={() => toggleAbout(item.user_id)} hitSlop={6}>
                <Text style={styles.aboutMore}>
                  {openAbout.has(item.user_id)
                    ? t('discovery.seeLess', { defaultValue: 'Voir moins' })
                    : t('discovery.seeMore', { defaultValue: 'Voir plus' })}
                </Text>
              </Pressable>
            )}
          </View>
        ) : null}

        <View style={styles.acts}>
          <Pressable style={({ pressed }) => [styles.btnGhost, pressed && styles.pressed]} onPress={() => router.push(`/(auth)/profile/${item.user_id}`)}>
            <User size={15} color={colors.textPrimary} strokeWidth={2.4} />
            <Text style={styles.btnGhostText}>{t('discovery.viewProfile', { defaultValue: 'Profil' })}</Text>
          </Pressable>
          <Pressable style={({ pressed }) => [styles.btnGhost, pressed && styles.pressed, done && styles.btnFaded]} onPress={() => setInviteTargetId(item.user_id)} disabled={done}>
            <UserPlus size={15} color={colors.textPrimary} strokeWidth={2.4} />
            <Text style={styles.btnGhostText}>{t('discovery.invite', { defaultValue: 'Inviter' })}</Text>
          </Pressable>
          {done ? (
            <View style={styles.btnSent}>
              <Text style={styles.btnSentText}>{t('discovery.contactedShort', { defaultValue: 'Envoyée' })}</Text>
            </View>
          ) : (
            <Pressable style={({ pressed }) => [styles.btnPrimary, pressed && styles.pressedPrimary]} onPress={() => handleContact(item.user_id)}>
              <Send size={15} color="#FFFFFF" strokeWidth={2.4} />
              <Text style={styles.btnPrimaryText}>{t('discovery.contact', { defaultValue: 'Contacter' })}</Text>
            </Pressable>
          )}
        </View>
      </View>
    );
  };

  // No active dispo → warm onboarding.
  if (!active) {
    const steps: { t: string; s: string }[] = [
      { t: t('discovery.onbStep1', { defaultValue: 'Ta dispo' }), s: t('discovery.onbStep1s', { defaultValue: 'Sport, zone, dates, transport' }) },
      { t: t('discovery.onbStep2', { defaultValue: 'Tu deviens visible' }), s: t('discovery.onbStep2s', { defaultValue: 'Et tu vois qui correspond' }) },
      { t: t('discovery.onbStep3', { defaultValue: 'Vous vous contactez' }), s: t('discovery.onbStep3s', { defaultValue: 'Puis une vraie sortie sur la carte' }) },
    ];
    return (
      <View style={styles.onbWrap}>
        <ScrollView contentContainerStyle={styles.onbScroll} showsVerticalScrollIndicator={false}>
        <View style={styles.onb}>
          <View style={styles.halo}><Handshake size={46} color={colors.cta} strokeWidth={2} /></View>
          <Text style={styles.onbTitle}>{t('discovery.onbTitle', { defaultValue: 'Trouve des partenaires autour de toi' })}</Text>
          <Text style={styles.onbBody}>{t('discovery.onbBody', { defaultValue: 'Publie ta dispo — un sport, une zone, des dates — et vois qui cherche la même chose.' })}</Text>
          <View style={styles.steps}>
            {steps.map((st, i) => (
              <View key={i} style={styles.step}>
                <View style={styles.stepN}><Text style={styles.stepNText}>{i + 1}</Text></View>
                <View style={{ flex: 1 }}>
                  <Text style={styles.stepT}>{st.t}</Text>
                  <Text style={styles.stepS}>{st.s}</Text>
                </View>
              </View>
            ))}
          </View>
        </View>
        </ScrollView>
        <Pressable style={({ pressed }) => [styles.ctaBig, pressed && styles.pressedPrimary]} onPress={() => router.push('/(auth)/discovery-compose')}>
          <Text style={styles.ctaBigText}>{mine ? t('discovery.editDispo', { defaultValue: 'Reprendre ma dispo' }) : t('discovery.composeDispo', { defaultValue: 'Composer ma dispo' })}</Text>
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
              bordered={false}
              chevronBoxed
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
                  <Row label={t('discovery.row.intent', { defaultValue: 'Cherche' })} stack>
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
            <View style={styles.emptyMatches}>
              <View style={styles.emptyIc}><Telescope size={32} color={colors.textMuted} strokeWidth={2} /></View>
              <Text style={styles.emptyMatchesTitle}>{t('discovery.noMatchesTitle', { defaultValue: 'Personne pour l’instant' })}</Text>
              <Text style={styles.emptyMatchesBody}>{t('discovery.noMatchesBody', { defaultValue: 'Reviens plus tard, ou élargis ta zone et tes dates pour croiser plus de monde.' })}</Text>
              <Pressable onPress={() => router.push('/(auth)/discovery-compose')} hitSlop={8}>
                <Text style={styles.emptyMatchesEdit}>{t('discovery.editMyDispo', { defaultValue: 'Modifier ma dispo' })}</Text>
              </Pressable>
            </View>
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
  // --- Onboarding (no dispo) ---
  onbWrap: { flex: 1, backgroundColor: colors.background, paddingHorizontal: spacing.lg, paddingTop: spacing.lg, paddingBottom: spacing.lg },
  onbScroll: { flexGrow: 1, justifyContent: 'center', paddingVertical: spacing.lg },
  onb: { alignItems: 'center', justifyContent: 'center', gap: spacing.sm },
  halo: {
    width: 108, height: 108, borderRadius: 54, backgroundColor: colors.cta + '18',
    alignItems: 'center', justifyContent: 'center', marginBottom: spacing.sm,
    ...Platform.select({ ios: { shadowColor: colors.cta, shadowOffset: { width: 0, height: 6 }, shadowOpacity: 0.18, shadowRadius: 16 }, android: { elevation: 2 } }),
  },
  onbTitle: { color: colors.textPrimary, fontSize: fontSizes.xl, fontWeight: '800', textAlign: 'center', letterSpacing: -0.4, lineHeight: 30 },
  onbBody: { color: colors.textSecondary, fontSize: fontSizes.md, textAlign: 'center', lineHeight: 22, maxWidth: 300, marginBottom: spacing.xs },
  steps: { alignSelf: 'stretch', gap: spacing.sm + 2, marginTop: spacing.md },
  step: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.sm + 2, backgroundColor: colors.surface,
    borderRadius: 16, padding: spacing.sm + 4, borderWidth: 1, borderColor: colors.borderMuted,
    ...Platform.select({ ios: { shadowColor: '#16281E', shadowOffset: { width: 0, height: 3 }, shadowOpacity: 0.07, shadowRadius: 10 }, android: { elevation: 1 } }),
  },
  stepN: { width: 27, height: 27, borderRadius: 14, backgroundColor: colors.cta + '1A', alignItems: 'center', justifyContent: 'center' },
  stepNText: { color: colors.cta, fontWeight: '800', fontSize: fontSizes.sm },
  stepT: { color: colors.textPrimary, fontSize: fontSizes.sm + 1, fontWeight: '800' },
  stepS: { color: colors.textSecondary, fontSize: fontSizes.xs + 1, fontWeight: '600', marginTop: 1 },
  ctaBig: {
    backgroundColor: colors.cta, borderRadius: 16, paddingVertical: spacing.md, alignItems: 'center', marginTop: spacing.md,
    ...Platform.select({ ios: { shadowColor: colors.cta, shadowOffset: { width: 0, height: 6 }, shadowOpacity: 0.34, shadowRadius: 14 }, android: { elevation: 4 } }),
  },
  ctaBigText: { color: '#FFFFFF', fontSize: fontSizes.md + 1, fontWeight: '800' },

  // --- Ta dispo panel ---
  myDispoWrap: { paddingHorizontal: spacing.md, backgroundColor: colors.cta + '14', borderBottomWidth: 1, borderBottomColor: colors.cta + '3D' },
  myDispoActions: { flexDirection: 'row', gap: spacing.lg, marginTop: spacing.md, paddingBottom: spacing.xs },
  matchesLabel: { color: colors.textMuted, fontSize: fontSizes.xs, fontWeight: '800', textTransform: 'uppercase', letterSpacing: 0.8, paddingVertical: spacing.sm, paddingHorizontal: 2 },

  // --- Empty matches ---
  emptyMatches: { alignItems: 'center', paddingVertical: spacing.xl + spacing.md, gap: spacing.sm, paddingHorizontal: spacing.lg },
  emptyIc: { width: 76, height: 76, borderRadius: 38, backgroundColor: colors.surfaceAlt, alignItems: 'center', justifyContent: 'center', marginBottom: spacing.xs },
  emptyMatchesTitle: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: '800' },
  emptyMatchesBody: { color: colors.textSecondary, fontSize: fontSizes.sm + 1, textAlign: 'center', lineHeight: 21, maxWidth: 260 },
  emptyMatchesEdit: { color: colors.cta, fontSize: fontSizes.sm + 1, fontWeight: '800', marginTop: spacing.xs },

  // --- Match card ---
  list: { padding: spacing.md, paddingBottom: spacing.lg },
  card: {
    backgroundColor: colors.background, borderRadius: 20, padding: spacing.md, marginBottom: spacing.md, gap: spacing.md,
    borderWidth: 1, borderColor: colors.borderMuted,
    ...Platform.select({ ios: { shadowColor: '#16281E', shadowOffset: { width: 0, height: 6 }, shadowOpacity: 0.10, shadowRadius: 16 }, android: { elevation: 3 } }),
  },
  cardTop: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm + 2 },
  nameRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, minWidth: 0 },
  cardName: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: '800', letterSpacing: -0.3, flexShrink: 1 },
  relChip: { borderRadius: radius.full, paddingHorizontal: spacing.sm, paddingVertical: 2, borderWidth: 1 },
  relChipText: { fontSize: fontSizes.xs - 1, fontWeight: '800' },
  subRow: { flexDirection: 'row', alignItems: 'center', gap: 5, marginTop: 3 },
  cardSub: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: '600', flexShrink: 1 },
  dateRow: { flexDirection: 'row', alignItems: 'center', gap: 5, marginTop: 3 },
  headMeta: { flexDirection: 'row', alignItems: 'center', gap: 6 },
  metaText: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: '700' },
  metaDot: { color: colors.textMuted, fontSize: fontSizes.sm },
  metaZone: { color: colors.cta, fontWeight: '800' },
  pillWrap: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.xs + 2 },
  pillBreak: { width: '100%', height: 0 },
  sportPill: { borderRadius: radius.full, paddingHorizontal: spacing.sm + 3, paddingVertical: 6, borderWidth: 1 },
  sportPillText: { fontSize: fontSizes.xs - 1, fontWeight: '800' },

  aboutCard: { gap: 3 },
  aboutText: { color: colors.textPrimary, fontSize: fontSizes.sm, lineHeight: 20 },
  aboutMore: { color: colors.cta, fontSize: fontSizes.xs + 1, fontWeight: '800' },
  infoRows: { gap: spacing.sm, marginTop: spacing.sm },
  infoRow: { flexDirection: 'row', alignItems: 'flex-start', gap: spacing.sm },
  infoRowStack: { gap: spacing.xs + 2 },
  infoLabel: { width: 62, color: colors.textMuted, fontSize: fontSizes.xs, fontWeight: '800', textTransform: 'uppercase', letterSpacing: 0.3, paddingTop: 2 },
  infoValue: { flex: 1, minWidth: 0 },
  infoValueStack: { width: '100%' },
  infoText: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '700' },
  transportIcons: { flexDirection: 'row', flexWrap: 'wrap', alignItems: 'center', gap: spacing.sm },
  intentWrap: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.xs },
  intentChip: { alignSelf: 'flex-start', backgroundColor: '#FFFFFF', borderWidth: 1, borderColor: colors.borderMuted, borderRadius: radius.full, paddingHorizontal: spacing.sm + 3, paddingVertical: 5 },
  intentChipText: { color: colors.textPrimary, fontSize: fontSizes.xs - 1, fontWeight: '800' },
  radiusValue: { flexDirection: 'row', flexWrap: 'wrap', alignItems: 'center', gap: spacing.sm },
  zoneLink: { color: colors.cta, fontSize: fontSizes.xs, fontWeight: '800' },

  // --- actions ---
  acts: { flexDirection: 'row', gap: spacing.sm },
  btnGhost: {
    flex: 1, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 6, backgroundColor: colors.surfaceAlt, borderRadius: 13, paddingVertical: spacing.sm + 3, borderWidth: 1, borderColor: colors.borderMuted,
    ...Platform.select({ ios: { shadowColor: '#000', shadowOffset: { width: 0, height: 2 }, shadowOpacity: 0.12, shadowRadius: 5 }, android: { elevation: 2 } }),
  },
  btnGhostText: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '800' },
  btnPrimary: {
    flex: 1, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 6, backgroundColor: colors.cta, borderRadius: 13, paddingVertical: spacing.sm + 3,
    borderWidth: 1, borderColor: 'rgba(0,0,0,0.12)',
    ...Platform.select({ ios: { shadowColor: colors.cta, shadowOffset: { width: 0, height: 4 }, shadowOpacity: 0.32, shadowRadius: 10 }, android: { elevation: 3 } }),
  },
  btnPrimaryText: { color: '#FFFFFF', fontSize: fontSizes.sm, fontWeight: '800' },
  btnSent: { flex: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: colors.cta + '22', borderRadius: 13, paddingVertical: spacing.sm + 3, borderWidth: 1, borderColor: colors.cta + '40' },
  btnSentText: { color: colors.cta, fontSize: fontSizes.sm, fontWeight: '800' },
  btnFaded: { opacity: 0.45 },
  pressed: { opacity: 0.7, transform: [{ scale: 0.97 }] },
  pressedPrimary: { transform: [{ scale: 0.97 }] },
  link: { color: colors.cta, fontSize: fontSizes.sm, fontWeight: '800' },
  linkDanger: { color: colors.error, fontSize: fontSizes.sm, fontWeight: '800' },
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
