import { useCallback, useMemo, useRef, useState } from 'react';
import { View, FlatList, ScrollView, StyleSheet, useWindowDimensions, type NativeScrollEvent, type NativeSyntheticEvent } from 'react-native';
import { AppText } from '@/components/app-text';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTranslation } from 'react-i18next';
import { useQuery } from '@tanstack/react-query';
import { X, User, Send, MessageCircle } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, fonts, spacing, radius, glow } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { discoveryService, type DiscoveryCard } from '@/services/discovery-service';
import { useSports } from '@/hooks/use-sports';
import { useDiscoveryActions } from '@/hooks/use-discovery-actions';
import { PressableScale } from '@/components/pressable-scale';
import { LogoSpinner } from '@/components/logo-spinner';
import { UserAvatar } from '@/components/user-avatar';
import { ReliabilityRing } from '@/components/reliability-ring';
import { SportIcon } from '@/components/sport-icon';
import { ContourLines } from '@/components/partners/contour-lines';
import { formatPeriod } from '@/components/partners/dispo-card-compact';
import { sportCategoryColor } from '@/utils/sport-category-color';
import { reliabilityColorForTier } from '@/utils/reliability-color';
import { OPEN_LEVEL } from '@/constants/sport-levels';
import { INTENT_LABEL } from '@/constants/discovery-vibes';
import { usePartnersPagerStore } from '@/store/partners-pager-store';

// Full Découverte card (refonte 2026-10-23): a whole page rising from the
// bottom; swipe left / right to the next person of the list it was opened
// from (order kept by the pager store). Everything to decide, and the actions
// at the bottom — the same logic as before (useDiscoveryActions).
const DOTS_MAX = 10;
const HERO_H = 230;

export default function PartnersDispoScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { userId } = useLocalSearchParams<{ userId?: string }>();
  const pagerIds = usePartnersPagerStore((s) => s.userIds);
  const { data: cards } = useQuery({ queryKey: ['discovery-cards'], queryFn: () => discoveryService.getCards() });

  const pages = useMemo(() => {
    const all = cards ?? [];
    if (pagerIds.length === 0) return all;
    const byId = new Map(all.map((c) => [c.user_id, c]));
    return pagerIds.map((id) => byId.get(id)).filter((c): c is DiscoveryCard => !!c);
  }, [cards, pagerIds]);
  const startIndex = Math.max(0, pages.findIndex((c) => c.user_id === userId));
  // The pager mounts once the list is there, so it starts on the right person.
  if (!cards) {
    return <View style={[styles.container, styles.loading]}><LogoSpinner size={40} /></View>;
  }
  return <Pager pages={pages} startIndex={startIndex} />;
}

function Pager({ pages, startIndex }: { pages: DiscoveryCard[]; startIndex: number }) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const { width } = useWindowDimensions();
  const actions = useDiscoveryActions();
  const { data: sports } = useSports();
  const categoryOf = useCallback((key: string) => (sports ?? []).find((s) => s.key === key)?.category, [sports]);
  const [index, setIndex] = useState(startIndex);
  const listRef = useRef<FlatList<DiscoveryCard>>(null);

  const onMomentumEnd = (e: NativeSyntheticEvent<NativeScrollEvent>) => {
    setIndex(Math.round(e.nativeEvent.contentOffset.x / width));
  };

  const current = pages[index];

  const renderPage = ({ item }: { item: DiscoveryCard }) => {
    const relColor = reliabilityColorForTier(item.reliability_tier, colors);
    return (
      <ScrollView style={{ width }} contentContainerStyle={{ paddingBottom: 130 + insets.bottom }} showsVerticalScrollIndicator={false}>
        <View style={[styles.hero, { paddingTop: insets.top + 64 }]}>
          <ContourLines width={width} height={HERO_H + insets.top} opacity={0.08} />
          <View style={styles.heroRow}>
            <ReliabilityRing tier={item.reliability_tier} size={92} strokeWidth={4} showLabel={false}>
              <UserAvatar name={item.display_name} avatarUrl={item.avatar_url} size={92} />
            </ReliabilityRing>
            <View style={styles.heroText}>
              <AppText style={styles.name} numberOfLines={2}>{item.display_name}</AppText>
              {item.reliability_tier ? (
                <View style={[styles.tierPill, { backgroundColor: relColor }]}>
                  <AppText style={styles.tierPillText}>{t(`reliability.tier.${item.reliability_tier}`)}</AppText>
                </View>
              ) : null}
              <AppText style={styles.heroSub}>
                {t('partenaires.fromYourZone', { defaultValue: 'à {{km}} km de ta zone', km: Math.round(item.distance_km) })}
                {' · '}
                {item.sorties_count > 0
                  ? t('discovery.sortiesCount', { defaultValue: '{{count}} sorties', count: item.sorties_count })
                  : t('discovery.newcomer', { defaultValue: 'nouveau' })}
              </AppText>
            </View>
          </View>
        </View>

        <View style={styles.body}>
          <View style={styles.blocks}>
            <View style={styles.block}>
              <AppText style={styles.blockLabel}>{t('partenaires.when', { defaultValue: 'Quand' })}</AppText>
              <AppText style={styles.blockValue}>{formatPeriod(item.window_start, item.window_end)}</AppText>
            </View>
            <View style={styles.block}>
              <AppText style={styles.blockLabel}>{t('partenaires.moves', { defaultValue: 'Se déplace' })}</AppText>
              <AppText style={styles.blockValue} numberOfLines={2}>
                {item.transport_modes.map((m) => t(`transport.type.${m}`, { defaultValue: m })).join(', ')}
              </AppText>
            </View>
            <View style={[styles.block, styles.blockWide]}>
              <View style={{ flex: 1, gap: 3 }}>
                <AppText style={styles.blockLabel}>{t('partenaires.theirZone', { defaultValue: 'Sa zone' })}</AppText>
                <AppText style={styles.blockValue}>
                  {item.radius_km
                    ? t('partenaires.radiusValue', { defaultValue: 'Rayon de {{km}} km', km: item.radius_km })
                    : t('discovery.radiusAny', { defaultValue: 'Peu importe' })}
                </AppText>
              </View>
              <PressableScale style={styles.zoneBtn} onPress={() => router.push({ pathname: '/(auth)/discovery-zone', params: { userId: item.user_id, name: item.display_name } })}>
                <AppText style={styles.zoneBtnText}>{t('discovery.seeZone', { defaultValue: 'Voir la zone' })}</AppText>
              </PressableScale>
            </View>
          </View>

          <View style={styles.section}>
            <AppText style={styles.sectionLabel}>{t('partenaires.theirSports', { defaultValue: 'Ses sports' })}</AppText>
            <View style={styles.chips}>
              {item.sport_keys.map((k) => {
                const level = item.levels?.[k];
                return (
                  <View key={k} style={[styles.sportChip, { backgroundColor: sportCategoryColor(categoryOf(k), colors.cta) }]}>
                    <SportIcon sportKey={k} size={14} color="#FFFFFF" />
                    <AppText style={styles.sportChipText}>
                      {t(`sports.${k}`, { defaultValue: k })}{level && level !== OPEN_LEVEL ? ` · ${level}` : ''}
                    </AppText>
                  </View>
                );
              })}
            </View>
          </View>

          {item.intent && item.intent.length > 0 ? (
            <View style={styles.section}>
              <AppText style={styles.sectionLabel}>{t('partenaires.vibes', { defaultValue: 'Vibes' })}</AppText>
              <View style={styles.chips}>
                {item.intent.map((it) => (
                  <View key={it} style={styles.vibe}>
                    <AppText style={styles.vibeText}>{t(`discovery.intent.${it}`, { defaultValue: INTENT_LABEL[it] })}</AppText>
                  </View>
                ))}
              </View>
            </View>
          ) : null}

          {item.about ? (
            <View style={styles.section}>
              <AppText style={styles.sectionLabel}>{t('partenaires.about', { defaultValue: 'En quelques mots' })}</AppText>
              <AppText style={styles.about}>{item.about}</AppText>
            </View>
          ) : null}

          <PressableScale style={styles.profileLink} onPress={() => router.push(`/(auth)/profile/${item.user_id}`)} accessibilityRole="button">
            <User size={16} color={colors.textSecondary} strokeWidth={2.2} />
            <AppText style={styles.profileLinkText}>{t('partenaires.viewProfile', { defaultValue: 'Voir son profil' })}</AppText>
          </PressableScale>
        </View>
      </ScrollView>
    );
  };

  return (
    <View style={styles.container}>
      <FlatList
        ref={listRef}
        data={pages}
        keyExtractor={(c) => c.user_id}
        renderItem={renderPage}
        horizontal
        pagingEnabled
        showsHorizontalScrollIndicator={false}
        initialScrollIndex={startIndex}
        getItemLayout={(_, i) => ({ length: width, offset: width * i, index: i })}
        onMomentumScrollEnd={onMomentumEnd}
      />

      {/* Top bar over the pages */}
      <View style={[styles.topBar, { top: insets.top + spacing.sm }]} pointerEvents="box-none">
        <PressableScale style={styles.close} onPress={() => router.back()} accessibilityRole="button" accessibilityLabel={t('partenaires.close', { defaultValue: 'Fermer' })}>
          <X size={18} color="#FFFFFF" strokeWidth={2.8} />
        </PressableScale>
        {pages.length > 1 ? (
          pages.length <= DOTS_MAX ? (
            <View style={styles.dots} accessibilityLabel={`${index + 1} / ${pages.length}`}>
              {pages.map((p, i) => <View key={p.user_id} style={[styles.dot, i === index && styles.dotOn]} />)}
            </View>
          ) : (
            <AppText style={styles.counter}>{`${index + 1} / ${pages.length}`}</AppText>
          )
        ) : <View />}
        <View style={{ width: 36 }} />
      </View>

      {/* Actions — same states as before: demo, connected, sent, received, none. */}
      {current ? (
        <View style={[styles.actions, { paddingBottom: insets.bottom + spacing.md }]}>
          {current.is_demo ? (
            <View style={[styles.btn, styles.btnMuted]}>
              <AppText style={styles.btnMutedText}>{t('discovery.demoProfile', { defaultValue: 'Profil de démonstration' })}</AppText>
            </View>
          ) : current.contact_state === 'connected' && current.conversation_id ? (
            <PressableScale style={[styles.btn, styles.btnPrimary]} onPress={() => router.push(`/(auth)/conversation/${current.conversation_id}`)}>
              <Send size={16} color="#FFFFFF" strokeWidth={2.4} />
              <AppText style={styles.btnPrimaryText}>{t('discovery.chat', { defaultValue: 'Discuter' })}</AppText>
            </PressableScale>
          ) : current.contact_state === 'pending' ? (
            <View style={[styles.btn, styles.btnMuted]}>
              <AppText style={styles.btnMutedText}>{t('partenaires.requestSent', { defaultValue: 'Demande envoyée' })}</AppText>
            </View>
          ) : current.contact_state === 'pending_received' ? (
            <PressableScale style={[styles.btn, styles.btnPrimary]} onPress={() => router.push('/(auth)/(tabs)/messagerie?tab=requests')}>
              <MessageCircle size={16} color="#FFFFFF" strokeWidth={2.4} />
              <AppText style={styles.btnPrimaryText}>{t('discovery.respond', { defaultValue: 'Répondre' })}</AppText>
            </PressableScale>
          ) : (
            <>
              <PressableScale style={[styles.btn, styles.btnSecondary]} onPress={() => actions.openInvite(current.user_id)} disabled={!!actions.sendingTo}>
                <AppText style={styles.btnSecondaryText}>{t('discovery.inviteTitle', { defaultValue: 'Inviter à une sortie' })}</AppText>
              </PressableScale>
              <PressableScale
                style={[styles.btn, styles.btnPrimary, actions.sendingTo === current.user_id && styles.faded]}
                onPress={() => actions.contact(current.user_id)}
                disabled={actions.sendingTo === current.user_id}
              >
                <Send size={16} color="#FFFFFF" strokeWidth={2.4} />
                <AppText style={styles.btnPrimaryText}>{t('discovery.contact', { defaultValue: 'Contacter' })}</AppText>
              </PressableScale>
            </>
          )}
        </View>
      ) : null}

      {actions.inviteSheet}
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  loading: { alignItems: 'center', justifyContent: 'center' },
  hero: { backgroundColor: colors.heroInk, paddingHorizontal: spacing.lg, paddingBottom: spacing.lg, overflow: 'hidden' },
  heroRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.md },
  heroText: { flex: 1, minWidth: 0, gap: 6 },
  name: { color: '#FFFFFF', fontFamily: fonts.title, fontSize: 26 },
  tierPill: { alignSelf: 'flex-start', borderRadius: radius.full, paddingHorizontal: 10, paddingVertical: 4 },
  tierPillText: { color: '#FFFFFF', fontSize: fontSizes.xs, fontWeight: '700' },
  heroSub: { color: 'rgba(255,255,255,0.8)', fontSize: fontSizes.sm },
  body: { padding: spacing.md + 2, gap: spacing.md + 2 },
  blocks: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm + 2 },
  block: { flexGrow: 1, flexBasis: '45%', backgroundColor: colors.surfaceAlt, borderRadius: 14, padding: spacing.sm + 4, gap: 3 },
  blockWide: { flexBasis: '100%', flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
  blockLabel: { color: colors.textSecondary, fontSize: fontSizes.xs, fontWeight: '700', letterSpacing: 0.5, textTransform: 'uppercase' },
  blockValue: { color: colors.textPrimary, fontSize: fontSizes.md - 1, fontWeight: '700' },
  zoneBtn: { backgroundColor: colors.cta + '1A', borderRadius: radius.full, paddingHorizontal: spacing.sm + 4, paddingVertical: spacing.sm },
  zoneBtnText: { color: colors.cta, fontSize: fontSizes.sm, fontWeight: '700' },
  section: { gap: spacing.sm },
  sectionLabel: { color: colors.textSecondary, fontSize: fontSizes.xs + 1, fontWeight: '700', letterSpacing: 0.5, textTransform: 'uppercase' },
  chips: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm },
  sportChip: { flexDirection: 'row', alignItems: 'center', gap: 5, borderRadius: radius.full, paddingHorizontal: 12, paddingVertical: 7 },
  sportChipText: { color: '#FFFFFF', fontSize: fontSizes.sm - 1, fontWeight: '600' },
  vibe: { backgroundColor: colors.surfaceAlt, borderRadius: radius.full, paddingHorizontal: 12, paddingVertical: 7 },
  vibeText: { color: colors.textPrimary, fontSize: fontSizes.sm - 1, fontWeight: '600' },
  about: { color: colors.textPrimary, fontSize: fontSizes.md - 1, lineHeight: 23 },
  profileLink: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, alignSelf: 'flex-start', paddingVertical: spacing.xs },
  profileLinkText: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: '600' },
  topBar: { position: 'absolute', left: spacing.md, right: spacing.md, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  close: { width: 36, height: 36, borderRadius: 18, backgroundColor: 'rgba(255,255,255,0.14)', alignItems: 'center', justifyContent: 'center' },
  dots: { flexDirection: 'row', gap: 5, alignItems: 'center' },
  dot: { width: 6, height: 6, borderRadius: 3, backgroundColor: 'rgba(255,255,255,0.35)' },
  dotOn: { width: 18, backgroundColor: '#FFFFFF' },
  counter: { color: '#FFFFFF', fontSize: fontSizes.sm, fontWeight: '700' },
  actions: {
    position: 'absolute', left: 0, right: 0, bottom: 0, flexDirection: 'row', gap: spacing.sm + 2,
    paddingHorizontal: spacing.md + 2, paddingTop: spacing.sm + 6, backgroundColor: colors.background,
    borderTopWidth: 1, borderTopColor: colors.line,
  },
  btn: { flex: 1, height: 52, borderRadius: radius.full, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: spacing.sm },
  btnPrimary: { backgroundColor: colors.cta, ...glow(colors.cta) },
  btnPrimaryText: { color: '#FFFFFF', fontSize: fontSizes.md - 1, fontWeight: '700' },
  btnSecondary: { backgroundColor: colors.surfaceAlt },
  btnSecondaryText: { color: colors.textPrimary, fontSize: fontSizes.md - 1, fontWeight: '700' },
  btnMuted: { backgroundColor: colors.surfaceAlt },
  btnMutedText: { color: colors.textSecondary, fontSize: fontSizes.md - 1, fontWeight: '700' },
  faded: { opacity: 0.5 },
});
