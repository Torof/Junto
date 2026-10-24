import { useState, useMemo, useRef, type ReactNode } from 'react';
import {
  View,
  Image,
  ImageBackground,
  Pressable,
  StyleSheet,
  FlatList,
  ScrollView,
  useWindowDimensions,
  type ListRenderItemInfo,
} from 'react-native';
import Svg, { Path } from 'react-native-svg';
import { AppText } from '@/components/app-text';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useTranslation } from 'react-i18next';
import dayjs from 'dayjs';
import {
  Plus, Calendar, BarChart2, Users, Car, Route, Map, UserSearch, MessageCircle, Menu, CalendarDays, Radar,
  CalendarCheck, Bookmark, Settings, QrCode, MapPinCheck, Clock, Package, type LucideIcon,
} from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { fontSizes, spacing, radius, shadows } from '@/constants/theme';
import { SPORT_CATEGORY_COLORS } from '@/utils/sport-category-color';
import { RELIABILITY_EXCELLENT_COLOR } from '@/utils/reliability-color';
import { ActivityPin } from './activity-pin';
import { SportIcon } from './sport-icon';
import type { NearbyActivity } from '@/services/activity-service';

// The tour of the app (Scott 2026-10-24, board « Tutoriel askandgo »): no
// longer forced on arrival — opened from the « Découvrir askandgo » button on
// the map or the menu entry, and from Settings. A pure next-tap carousel, no
// anchoring, so it can't trap anyone when the UI changes. Each page is one
// picture made of the app's own pieces (real pins, the outing sheet's
// grammar, the menu, the reliability ring), a title and a sentence or two.
// Picture props are pointerEvents none: they never catch a swipe.

const MOUNTAIN = SPORT_CATEGORY_COLORS.mountain ?? '#4A7C59';

function demoPin(sport_key: string, sport_category: string, when: 'upcoming' | 'soon' | 'live'): NearbyActivity {
  return {
    sport_key,
    sport_category,
    visibility: 'public',
    status: when === 'live' ? 'in_progress' : 'published',
    starts_at: when === 'soon' ? dayjs().add(1, 'hour').toISOString() : dayjs().add(3, 'day').toISOString(),
  } as unknown as NearbyActivity;
}

interface IntroPage {
  key: string;
  picture: ReactNode;
  title: string;
  body: string;
}

interface IntroCarouselProps {
  onDone: () => void;
}

export function IntroCarousel({ onDone }: IntroCarouselProps) {
  const { t, i18n } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { width } = useWindowDimensions();
  const listRef = useRef<FlatList<IntroPage>>(null);
  const [index, setIndex] = useState(0);

  const pages = useMemo<IntroPage[]>(() => {
    const demoDate = dayjs().add(3, 'day').hour(9).minute(0).locale(i18n.language);
    return [
      {
        key: 'welcome',
        title: t('intro.welcome.title'),
        body: t('intro.welcome.body'),
        picture: (
          <View style={[styles.stage, styles.welcomeStage]}>
            <Svg width="100%" height={130} viewBox="0 0 328 130" preserveAspectRatio="none" style={styles.mountains}>
              <Path d="M0 130 L70 60 L110 86 L180 20 L240 78 L280 50 L328 90 L328 130 Z" fill="#2C3B30" />
              <Path d="M0 130 L90 90 L150 108 L220 64 L290 102 L328 86 L328 130 Z" fill="#33463A" />
            </Svg>
            <Image source={require('../../assets/askandgo_icon_square.png')} style={styles.welcomeLogo} />
            <AppText style={styles.welcomeName}>askandgo</AppText>
            <AppText style={styles.welcomeTagline}>{t('intro.welcome.tagline')}</AppText>
          </View>
        ),
      },
      {
        key: 'map',
        title: t('intro.map.title'),
        body: t('intro.map.body'),
        picture: (
          <ImageBackground source={require('../../assets/intro-map.jpg')} style={styles.stage} imageStyle={styles.stageImage}>
            <View style={styles.chipsRow}>
              <MapChip color={MOUNTAIN} label={t('intro.map.chipSport')} styles={styles} />
              <MapChip color="#F97316" label={t('intro.map.chipSoon')} styles={styles} />
              <MapChip color={colors.success} label={t('intro.map.chipLive')} styles={styles} />
            </View>
            <View style={[styles.pinAt, { left: '12%', top: '30%' }]}><ActivityPin activity={demoPin('climbing-sport', 'mountain', 'upcoming')} /></View>
            <View style={[styles.pinAt, { left: '50%', top: '22%' }]}><ActivityPin activity={demoPin('canyoning', 'water', 'upcoming')} /></View>
            <View style={[styles.pinAt, { left: '72%', top: '40%' }]}><ActivityPin activity={demoPin('hiking', 'on-foot', 'soon')} /></View>
            <View style={[styles.pinAt, { left: '30%', top: '50%' }]}><ActivityPin activity={demoPin('trail-running', 'on-foot', 'live')} /></View>
            <View style={[styles.pinAt, { left: '62%', top: '62%' }]}><ActivityPin activity={demoPin('paragliding', 'air', 'upcoming')} /></View>
            <MiniTabBar active="carte" styles={styles} colors={colors} t={t} />
          </ImageBackground>
        ),
      },
      {
        key: 'outing',
        title: t('intro.outing.title'),
        body: t('intro.outing.body'),
        picture: (
          <ImageBackground source={require('../../assets/intro-map.jpg')} style={styles.stage} imageStyle={styles.stageImage}>
            <View style={[styles.pinAt, { left: '42%', top: '6%' }]}><ActivityPin activity={demoPin('climbing-sport', 'mountain', 'upcoming')} /></View>
            <View style={styles.fab}><Plus size={22} color={colors.onCta} strokeWidth={3} /></View>
            <View style={styles.sheet}>
              <View style={styles.grabber} />
              <View style={[styles.sportChip, { borderColor: MOUNTAIN, backgroundColor: MOUNTAIN + '18' }]}>
                <SportIcon sportKey="climbing-sport" size={13} color={MOUNTAIN} />
                <AppText style={[styles.sportChipText, { color: MOUNTAIN }]}>{t('sports.climbing-sport', { defaultValue: 'Escalade' })}</AppText>
              </View>
              <AppText style={[styles.kindLine, { color: MOUNTAIN }]}>{t('map.peerOuting')}</AppText>
              <AppText style={styles.sheetTitle}>Couenne au Saix</AppText>
              <InfoRow icon={Calendar} text={demoDate.format(t('format.dateTimeAt', { defaultValue: 'ddd D MMM [à] H[h]mm' }))} styles={styles} />
              <InfoRow icon={BarChart2} text="6a – 7a" styles={styles} extra={(
                <View style={[styles.gpxPill, { borderColor: MOUNTAIN, backgroundColor: MOUNTAIN + '18' }]}>
                  <Route size={10} color={MOUNTAIN} strokeWidth={2.6} />
                  <AppText style={[styles.gpxPillText, { color: MOUNTAIN }]}>GPX</AppText>
                </View>
              )} />
              <InfoRow icon={Users} text={t('map.spotsLeft', { n: 3, count: 3 })} styles={styles} />
              <InfoRow icon={Car} text={`${t('map.carpoolSeats', { n: 2, count: 2 })} · ${t('map.carpoolFrom')} Briançon`} styles={styles} />
              <View style={[styles.sheetCta, { backgroundColor: MOUNTAIN }]}>
                <AppText style={styles.sheetCtaText}>{t('map.seeActivity')} →</AppText>
              </View>
            </View>
          </ImageBackground>
        ),
      },
      {
        key: 'partners',
        title: t('intro.partners.title'),
        body: t('intro.partners.body'),
        picture: (
          <View style={[styles.stage, styles.plainStage]}>
            <View style={styles.partnersInner}>
              <AppText style={styles.screenTitle}>{t('tabs.partenaires')}</AppText>
              <View style={styles.dispoStrip}>
                <AppText style={styles.dispoStripTitle}>{t('intro.partners.myDispo')}</AppText>
                <AppText style={styles.dispoStripSub}>Grande voie, Trail</AppText>
              </View>
              <AppText style={styles.sectionLine}>{t('intro.partners.matching')} <AppText style={{ color: colors.cta }}>8</AppText></AppText>
              <View style={styles.dispoCard}>
                <View style={styles.dispoHead}>
                  <View style={[styles.dispoAvatar, { borderColor: RELIABILITY_EXCELLENT_COLOR }]}><AppText style={styles.dispoInitials}>ML</AppText></View>
                  <View>
                    <AppText style={styles.dispoName}>Marie L.</AppText>
                    <AppText style={[styles.dispoTier, { color: RELIABILITY_EXCELLENT_COLOR }]}>{t('reliability.tier.excellent')}</AppText>
                  </View>
                </View>
                <View style={styles.pills}>
                  <SportPill sportKey="climbing-multipitch" color={MOUNTAIN} label={t('sports.climbing-multipitch', { defaultValue: 'Grande voie' })} styles={styles} />
                  <SportPill sportKey="trail-running" color={SPORT_CATEGORY_COLORS['on-foot'] ?? '#E11D48'} label={t('sports.trail-running', { defaultValue: 'Trail' })} styles={styles} />
                </View>
              </View>
            </View>
            <MiniTabBar active="partenaires" styles={styles} colors={colors} t={t} />
          </View>
        ),
      },
      {
        key: 'menu',
        title: t('intro.menu.title'),
        body: t('intro.menu.body'),
        picture: (
          <ImageBackground source={require('../../assets/intro-map.jpg')} style={styles.stage} imageStyle={styles.stageImage}>
            <View style={styles.dim} />
            <View style={styles.menuSheet}>
              <View style={styles.grabber} />
              <MenuRow icon={CalendarDays} label={t('menu.mesActivites')} accent styles={styles} colors={colors} />
              <MenuRow icon={Radar} label={t('menu.alerts')} sub={t('intro.menu.alertsSub')} highlight styles={styles} colors={colors} />
              <MenuRow icon={Route} label={t('menu.gpxTraces')} styles={styles} colors={colors} />
              <MenuRow icon={CalendarCheck} label={t('menu.myBookings')} styles={styles} colors={colors} />
              <MenuRow icon={Bookmark} label={t('menu.favorites')} styles={styles} colors={colors} />
              <MenuRow icon={Settings} label={t('menu.settings')} styles={styles} colors={colors} />
            </View>
            <MiniTabBar active="menu" styles={styles} colors={colors} t={t} />
          </ImageBackground>
        ),
      },
      {
        key: 'reliability',
        title: t('intro.reliability.title'),
        body: t('intro.reliability.body'),
        picture: (
          <View style={[styles.stage, styles.relStage]}>
            <View style={styles.relCard}>
              <View style={styles.relRing}>
                <Svg width={76} height={76} viewBox="0 0 80 80">
                  <Path d="M40 2 a38 38 0 1 1 0 76 a38 38 0 1 1 0 -76" fill="none" stroke={colors.surfaceAlt} strokeWidth={4} />
                  <Path d="M40 2 a38 38 0 1 1 -22.3 6.2" fill="none" stroke={RELIABILITY_EXCELLENT_COLOR} strokeWidth={3.5} strokeLinecap="round" />
                </Svg>
                <View style={styles.relDisc}><AppText style={styles.relDiscText}>96%</AppText></View>
              </View>
              <View style={{ flex: 1 }}>
                <AppText style={styles.relLabel}>{t('reliability.label').toUpperCase()}</AppText>
                <AppText style={[styles.relTier, { color: RELIABILITY_EXCELLENT_COLOR }]}>{t('reliability.tier.excellent')}</AppText>
                <AppText style={styles.relSub}>{t('intro.reliability.presences')}</AppText>
              </View>
            </View>
            <View style={styles.relTiles}>
              <View style={styles.relTile}>
                <QrCode size={30} color={colors.textPrimary} strokeWidth={2} />
                <AppText style={styles.relTileText}>{t('intro.reliability.qr')}</AppText>
              </View>
              <View style={styles.relTile}>
                <MapPinCheck size={30} color={colors.cta} strokeWidth={2} />
                <AppText style={styles.relTileText}>{t('intro.reliability.auto')}</AppText>
              </View>
            </View>
            <View style={styles.traits}>
              <View style={styles.trait}><Clock size={13} color="#9DA9B5" strokeWidth={2.2} /><AppText style={styles.traitText}>{t('badges.punctual', { defaultValue: 'Ponctuel' })}</AppText><AppText style={[styles.traitCount, { color: '#9DA9B5' }]}>12</AppText></View>
              <View style={styles.trait}><Package size={13} color="#B87333" strokeWidth={2.2} /><AppText style={styles.traitText}>{t('badges.prepared', { defaultValue: 'Préparé' })}</AppText><AppText style={[styles.traitCount, { color: '#B87333' }]}>7</AppText></View>
            </View>
          </View>
        ),
      },
    ];
  }, [t, i18n.language, colors, styles]);

  const isLast = index === pages.length - 1;

  const goNext = () => {
    if (isLast) {
      onDone();
      return;
    }
    const next = index + 1;
    listRef.current?.scrollToIndex({ index: next, animated: true });
    setIndex(next);
  };

  // Each page scrolls vertically when it does not fit (small screens).
  const renderPage = ({ item }: ListRenderItemInfo<IntroPage>) => (
    <ScrollView style={{ width }} contentContainerStyle={styles.pageScroll} showsVerticalScrollIndicator={false}>
      <View pointerEvents="none">{item.picture}</View>
      <AppText style={styles.pageTitle}>{item.title}</AppText>
      <AppText style={styles.pageBody}>{item.body}</AppText>
    </ScrollView>
  );

  return (
    <View style={styles.overlay}>
      <SafeAreaView style={styles.safe} edges={['top', 'bottom']}>
        <View style={styles.topBar}>
          <Pressable onPress={onDone} hitSlop={8} style={styles.skipBtn}>
            <AppText style={styles.skipText}>{t('intro.skip')}</AppText>
          </Pressable>
        </View>

        <FlatList
          ref={listRef}
          data={pages}
          keyExtractor={(p) => p.key}
          renderItem={renderPage}
          horizontal
          pagingEnabled
          showsHorizontalScrollIndicator={false}
          getItemLayout={(_, i) => ({ length: width, offset: width * i, index: i })}
          onMomentumScrollEnd={(e) => setIndex(Math.round(e.nativeEvent.contentOffset.x / width))}
        />

        <View style={styles.dots}>
          {pages.map((p, i) => (
            <View key={p.key} style={[styles.dot, i === index && styles.dotActive]} />
          ))}
        </View>

        <Pressable style={styles.nextBtn} onPress={goNext}>
          <AppText style={styles.nextText}>{isLast ? t('intro.start') : t('intro.next')}</AppText>
        </Pressable>
      </SafeAreaView>
    </View>
  );
}

type Styles = ReturnType<typeof createStyles>;
type T = (k: string, o?: Record<string, unknown>) => string;

function MapChip({ color, label, styles }: { color: string; label: string; styles: Styles }) {
  return (
    <View style={styles.mapChip}>
      <View style={[styles.mapChipDot, { backgroundColor: color }]} />
      <AppText style={[styles.mapChipText, { color }]}>{label}</AppText>
    </View>
  );
}

function InfoRow({ icon: Icon, text, extra, styles }: { icon: LucideIcon; text: string; extra?: ReactNode; styles: Styles }) {
  return (
    <View style={styles.infoRow}>
      <Icon size={14} color={MOUNTAIN} strokeWidth={2.2} />
      <AppText style={styles.infoText} numberOfLines={1}>{text}</AppText>
      {extra}
    </View>
  );
}

function SportPill({ sportKey, color, label, styles }: { sportKey: string; color: string; label: string; styles: Styles }) {
  return (
    <View style={[styles.sportPill, { backgroundColor: color + '1A' }]}>
      <SportIcon sportKey={sportKey} size={12} color={color} />
      <AppText style={[styles.sportPillText, { color }]}>{label}</AppText>
    </View>
  );
}

function MenuRow({
  icon: Icon, label, sub, accent, highlight, styles, colors,
}: { icon: LucideIcon; label: string; sub?: string; accent?: boolean; highlight?: boolean; styles: Styles; colors: AppColors }) {
  return (
    <View style={[styles.menuRow, highlight && styles.menuRowHighlight]}>
      <View style={[styles.menuIcon, accent && { backgroundColor: colors.cta }]}>
        <Icon size={17} color={accent ? colors.onCta : colors.textPrimary} strokeWidth={2.2} />
      </View>
      <View style={{ flex: 1 }}>
        <AppText style={styles.menuLabel}>{label}</AppText>
        {sub ? <AppText style={styles.menuSub}>{sub}</AppText> : null}
      </View>
    </View>
  );
}

const TABS: { key: string; icon: LucideIcon }[] = [
  { key: 'carte', icon: Map },
  { key: 'partenaires', icon: UserSearch },
  { key: 'messagerie', icon: MessageCircle },
  { key: 'menu', icon: Menu },
];

function MiniTabBar({ active, styles, colors, t }: { active: string; styles: Styles; colors: AppColors; t: T }) {
  return (
    <View style={styles.tabBar}>
      {TABS.map(({ key, icon: Icon }) => {
        const on = key === active;
        return (
          <View key={key} style={styles.tab}>
            <View style={[styles.tabPill, on && { backgroundColor: colors.cta + '24' }]}>
              <Icon size={18} color={on ? colors.cta : colors.textSecondary} strokeWidth={on ? 2.4 : 2} />
            </View>
            <AppText style={[styles.tabLabel, on && { color: colors.textPrimary }]} numberOfLines={1}>{t(`tabs.${key}`)}</AppText>
          </View>
        );
      })}
    </View>
  );
}

const STAGE_H = 340;

const createStyles = (colors: AppColors) =>
  StyleSheet.create({
    overlay: { ...StyleSheet.absoluteFillObject, backgroundColor: colors.background, zIndex: 100 },
    safe: { flex: 1 },
    topBar: { flexDirection: 'row', justifyContent: 'flex-end', paddingHorizontal: spacing.md, paddingTop: spacing.sm },
    skipBtn: { paddingHorizontal: spacing.sm, paddingVertical: spacing.xs },
    skipText: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: '600' },
    pageScroll: { flexGrow: 1, paddingHorizontal: spacing.lg, paddingTop: spacing.sm, paddingBottom: spacing.md },
    pageTitle: { color: colors.textPrimary, fontSize: 25, fontWeight: '800', letterSpacing: -0.6, lineHeight: 29, marginTop: spacing.lg },
    pageBody: { color: colors.textSecondary, fontSize: fontSizes.md - 1, lineHeight: 22, marginTop: spacing.sm },

    stage: { height: STAGE_H, borderRadius: radius.xl, overflow: 'hidden', backgroundColor: '#DCE5D3' },
    stageImage: { borderRadius: radius.xl },
    plainStage: { backgroundColor: colors.surface, borderWidth: 1, borderColor: colors.line },
    pinAt: { position: 'absolute' },

    // 1 — welcome
    welcomeStage: { backgroundColor: colors.heroInk, alignItems: 'center', justifyContent: 'center', gap: spacing.sm },
    mountains: { position: 'absolute', left: 0, right: 0, bottom: 0 },
    welcomeLogo: { width: 92, height: 92, borderRadius: 26, marginBottom: spacing.xs },
    welcomeName: { color: '#FFFFFF', fontSize: 36, fontWeight: '800', letterSpacing: -1.2 },
    welcomeTagline: { color: 'rgba(255,255,255,0.8)', fontSize: fontSizes.sm + 1, fontWeight: '600' },

    // 2 — map
    chipsRow: { flexDirection: 'row', flexWrap: 'wrap', justifyContent: 'center', gap: 6, paddingTop: spacing.sm, paddingHorizontal: spacing.sm },
    mapChip: { flexDirection: 'row', alignItems: 'center', gap: 5, backgroundColor: '#FFFFFF', borderRadius: radius.full, paddingHorizontal: 10, paddingVertical: 5, ...shadows.card },
    mapChipDot: { width: 7, height: 7, borderRadius: 4 },
    mapChipText: { fontSize: 11, fontWeight: '700' },

    // 3 — outing sheet (the app's activity-sheet grammar)
    fab: {
      position: 'absolute', right: 14, top: 18, width: 44, height: 44, borderRadius: 22, backgroundColor: colors.cta,
      alignItems: 'center', justifyContent: 'center', ...shadows.raised,
    },
    sheet: {
      position: 'absolute', left: 0, right: 0, bottom: 0, backgroundColor: colors.surface,
      borderTopLeftRadius: radius.xl, borderTopRightRadius: radius.xl, paddingHorizontal: spacing.md, paddingBottom: spacing.md, gap: 5,
    },
    grabber: { alignSelf: 'center', width: 36, height: 4, borderRadius: 2, backgroundColor: colors.textMuted, marginTop: 8, marginBottom: 4 },
    sportChip: { alignSelf: 'flex-start', flexDirection: 'row', alignItems: 'center', gap: 4, paddingHorizontal: 8, paddingVertical: 2, borderRadius: radius.full, borderWidth: 1 },
    sportChipText: { fontSize: 9.5, fontWeight: '800', letterSpacing: 0.6, textTransform: 'uppercase' },
    kindLine: { fontSize: 11.5, fontWeight: '700' },
    sheetTitle: { color: colors.textPrimary, fontSize: 20, fontWeight: '800', letterSpacing: -0.4 },
    infoRow: { flexDirection: 'row', alignItems: 'center', gap: 6 },
    infoText: { flex: 1, color: colors.textPrimary, fontSize: fontSizes.sm - 1, fontWeight: '600' },
    gpxPill: { flexDirection: 'row', alignItems: 'center', gap: 3, borderWidth: 1, borderRadius: radius.full, paddingHorizontal: 6, paddingVertical: 1 },
    gpxPillText: { fontSize: 10, fontWeight: '800' },
    sheetCta: { marginTop: 4, borderRadius: radius.lg, paddingVertical: 10, alignItems: 'center' },
    sheetCtaText: { color: '#FFFFFF', fontSize: fontSizes.sm + 1, fontWeight: '800' },

    // 4 — partners
    partnersInner: { padding: spacing.md, gap: spacing.sm },
    screenTitle: { color: colors.textPrimary, fontSize: 19, fontWeight: '800' },
    dispoStrip: { backgroundColor: colors.heroInk, borderRadius: 14, paddingHorizontal: 12, paddingVertical: 9, gap: 2 },
    dispoStripTitle: { color: '#FFFFFF', fontSize: 13, fontWeight: '700' },
    dispoStripSub: { color: 'rgba(255,255,255,0.7)', fontSize: 11 },
    sectionLine: { color: colors.textPrimary, fontSize: 14, fontWeight: '800' },
    dispoCard: { backgroundColor: colors.surface, borderRadius: 18, padding: 12, gap: 8, ...shadows.cardFirm },
    dispoHead: { flexDirection: 'row', alignItems: 'center', gap: 9 },
    dispoAvatar: { width: 38, height: 38, borderRadius: 19, borderWidth: 2.5, backgroundColor: '#DCE5D3', alignItems: 'center', justifyContent: 'center' },
    dispoInitials: { color: '#3F7A56', fontSize: 12, fontWeight: '800' },
    dispoName: { color: colors.textPrimary, fontSize: 14, fontWeight: '700' },
    dispoTier: { fontSize: 11, fontWeight: '600' },
    pills: { flexDirection: 'row', flexWrap: 'wrap', gap: 5 },
    sportPill: { flexDirection: 'row', alignItems: 'center', gap: 4, borderRadius: radius.full, paddingHorizontal: 8, paddingVertical: 4 },
    sportPillText: { fontSize: 11, fontWeight: '600' },

    // 5 — menu
    dim: { ...StyleSheet.absoluteFillObject, backgroundColor: 'rgba(15,20,16,0.35)' },
    menuSheet: {
      position: 'absolute', left: 0, right: 0, bottom: 56, backgroundColor: colors.surface,
      borderTopLeftRadius: radius.xl, borderTopRightRadius: radius.xl, paddingHorizontal: spacing.md, paddingBottom: spacing.sm,
    },
    menuRow: { flexDirection: 'row', alignItems: 'center', gap: 12, paddingVertical: 5 },
    menuRowHighlight: { backgroundColor: colors.cta + '14', borderRadius: 14, borderWidth: 2, borderColor: colors.cta, marginHorizontal: -8, paddingHorizontal: 6, marginVertical: 2 },
    menuIcon: { width: 32, height: 32, borderRadius: 10, backgroundColor: colors.surfaceAlt, alignItems: 'center', justifyContent: 'center' },
    menuLabel: { color: colors.textPrimary, fontSize: 14, fontWeight: '600' },
    menuSub: { color: colors.cta, fontSize: 11, fontWeight: '600' },

    // 6 — reliability
    relStage: { backgroundColor: colors.surfaceAlt, padding: spacing.md, gap: spacing.md, justifyContent: 'center' },
    relCard: { flexDirection: 'row', alignItems: 'center', gap: 14, backgroundColor: colors.surface, borderRadius: 18, padding: 14, ...shadows.card },
    relRing: { width: 76, height: 76, alignItems: 'center', justifyContent: 'center' },
    relDisc: { position: 'absolute', width: 62, height: 62, borderRadius: 31, backgroundColor: '#DCE5D3', alignItems: 'center', justifyContent: 'center' },
    relDiscText: { color: '#3F7A56', fontSize: 16, fontWeight: '800' },
    relLabel: { color: colors.textSecondary, fontSize: 10, fontWeight: '600', letterSpacing: 1.2 },
    relTier: { fontSize: 24, fontWeight: '800', letterSpacing: -0.6 },
    relSub: { color: colors.textMuted, fontSize: 11 },
    relTiles: { flexDirection: 'row', gap: spacing.sm },
    relTile: { flex: 1, alignItems: 'center', gap: 6, backgroundColor: colors.surface, borderRadius: 16, padding: 12, ...shadows.card },
    relTileText: { color: colors.textPrimary, fontSize: 12, fontWeight: '700', textAlign: 'center' },
    traits: { flexDirection: 'row', justifyContent: 'center', gap: 6 },
    trait: { flexDirection: 'row', alignItems: 'center', gap: 5, backgroundColor: colors.surface, borderRadius: 8, paddingHorizontal: 9, paddingVertical: 5 },
    traitText: { color: colors.textPrimary, fontSize: 12.5, fontWeight: '600' },
    traitCount: { fontSize: 12.5, fontWeight: '700', marginLeft: 2 },

    // Mini tab bar at the bottom of a picture
    tabBar: { position: 'absolute', left: 0, right: 0, bottom: 0, height: 56, backgroundColor: colors.surface, flexDirection: 'row', alignItems: 'center', paddingHorizontal: 4 },
    tab: { flex: 1, alignItems: 'center', gap: 2 },
    tabPill: { height: 26, width: 50, borderRadius: 13, alignItems: 'center', justifyContent: 'center' },
    tabLabel: { color: colors.textSecondary, fontSize: 9.5, fontWeight: '700' },

    dots: { flexDirection: 'row', justifyContent: 'center', gap: 6, paddingVertical: spacing.md },
    dot: { width: 7, height: 7, borderRadius: 4, backgroundColor: colors.borderMuted },
    dotActive: { backgroundColor: colors.cta, width: 20 },
    nextBtn: {
      backgroundColor: colors.cta, borderRadius: radius.full, paddingVertical: spacing.sm + 6,
      alignItems: 'center', marginHorizontal: spacing.lg, marginBottom: spacing.sm,
    },
    nextText: { color: colors.onCta, fontSize: fontSizes.md, fontWeight: '700' },
  });
