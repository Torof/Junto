import { useState, useMemo, useRef, type ReactNode } from 'react';
import {
  View,
  Text,
  Image,
  Pressable,
  StyleSheet,
  FlatList,
  useWindowDimensions,
  type ListRenderItemInfo,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useTranslation } from 'react-i18next';
import { Plus, BellRing } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { ActivityPin } from './activity-pin';
import { ProOfferingPin } from './pro-offering-pin';
import { ProPin } from './pro-pin';
import { ActivityPopup } from './activity-popup';
import { ReliabilityRing } from './reliability-ring';
import { UserAvatar } from './user-avatar';
import type { NearbyActivity } from '@/services/activity-service';
import type { ProOffering } from '@/services/pro-offering-service';

// First-run intro shown once on the map (gated by users.tutorial_seen_at).
// A pure next-tap carousel — NO element anchoring, NO interaction beyond
// paging — so it can't break or trap a user when the UI changes (unlike
// the coach-mark tutorial it replaces). Visuals are LIVE components (the
// real pins, popup, reliability ring…) so the intro always matches the
// app; explanatory copy lives in i18n, never baked into an image.

// Display-only stubs. The components read only the fields below, so a
// minimal cast is enough to render them live (and they stay in sync with
// the real map/popup automatically). All heroes are pointerEvents:none.
const DEMO_UA = {
  starts_at: '2030-06-15T10:00:00.000Z',
  status: 'published',
  sport_key: 'escalade',
} as unknown as NearbyActivity;
const DEMO_RA = { sport_key: 'yoga' } as unknown as ProOffering;
const DEMO_POPUP = {
  id: 'intro-demo',
  title: 'Couenne au Saix',
  sport_key: 'escalade',
  starts_at: '2030-06-15T09:00:00.000Z',
  status: 'published',
  visibility: 'public',
  max_participants: 6,
  participant_count: 3,
  level: '6a - 6b',
  level_max: null,
  distance_km: null,
  elevation_gain_m: null,
  objective_name: 'Le Saix',
  lng: 0,
  lat: 0,
} as unknown as NearbyActivity;

interface IntroRow {
  visual: ReactNode;
  text: string;
  legend?: { color: string; label: string }[];
}
interface IntroPage {
  title: string;
  welcome?: { tagline: string; body: string }; // opening manifesto page
  hero?: ReactNode; // big single hero
  caption?: string;
  rows?: IntroRow[]; // multi-row explainer (pins page)
}

interface IntroCarouselProps {
  onDone: () => void;
}

export function IntroCarousel({ onDone }: IntroCarouselProps) {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { width } = useWindowDimensions();
  const listRef = useRef<FlatList<IntroPage>>(null);
  const [index, setIndex] = useState(0);

  const pages = useMemo<IntroPage[]>(
    () => [
      {
        title: '',
        welcome: {
          tagline: t('intro.welcome.tagline'),
          body: t('intro.welcome.body'),
        },
      },
      {
        title: t('intro.pins.title'),
        rows: [
          {
            visual: <ActivityPin activity={DEMO_UA} />,
            text: t('intro.pins.ua'),
            legend: [
              { color: '#FBBF24', label: t('intro.pins.soon') },
              { color: colors.success, label: t('intro.pins.inProgress') },
            ],
          },
          { visual: <ProOfferingPin offering={DEMO_RA} />, text: t('intro.pins.ra') },
          { visual: <ProPin displayName="M" pinImageUrl={null} />, text: t('intro.pins.pp') },
        ],
      },
      {
        title: t('intro.join.title'),
        hero: <ActivityPopup activity={DEMO_POPUP} onPress={() => {}} />,
        caption: `${t('intro.join.tap')}\n\n${t('intro.join.inside')}`,
      },
      {
        title: t('intro.create.title'),
        hero: (
          <View style={styles.fabDemo}>
            <Plus size={38} color="#FFFFFF" strokeWidth={2.6} />
          </View>
        ),
        caption: t('intro.create.body'),
      },
      {
        title: t('intro.alert.title'),
        hero: (
          <View style={styles.alertDemo}>
            <View style={styles.alertBell}>
              <BellRing size={26} color={colors.cta} strokeWidth={2.2} />
            </View>
            <View style={styles.alertChip}>
              <Text style={styles.alertChipText}>Escalade · 30 km</Text>
            </View>
          </View>
        ),
        caption: t('intro.alert.body'),
      },
      {
        title: t('intro.profile.title'),
        hero: (
          <ReliabilityRing score={82} size={134} strokeWidth={12} showLabel>
            <UserAvatar name="M" avatarUrl={null} size={86} />
          </ReliabilityRing>
        ),
        caption: t('intro.profile.body'),
      },
    ],
    [t, colors, styles],
  );

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

  const renderPage = ({ item }: ListRenderItemInfo<IntroPage>) => {
    if (item.welcome) {
      return (
        <View style={[styles.page, styles.welcomePage, { width }]}>
          <Image
            source={require('../../assets/junto_icon_round.png')}
            style={styles.welcomeLogo}
          />
          <Text style={styles.welcomeTagline}>{item.welcome.tagline}</Text>
          <Text style={styles.welcomeBody}>{item.welcome.body}</Text>
        </View>
      );
    }
    return (
    <View style={[styles.page, { width }]}>
      <Text style={styles.pageTitle}>{item.title}</Text>

      {item.hero ? (
        <>
          <View style={styles.heroStage} pointerEvents="none">
            {item.hero}
          </View>
          {item.caption && <Text style={styles.caption}>{item.caption}</Text>}
        </>
      ) : (
        <View style={styles.rowsStage} pointerEvents="none">
          {item.rows?.map((row, i) => (
            <View key={i} style={styles.rowBlock}>
              <View style={styles.rowVisual}>{row.visual}</View>
              <View style={styles.rowBody}>
                <Text style={styles.rowText}>{row.text}</Text>
                {row.legend && (
                  <View style={styles.legendRow}>
                    {row.legend.map((l, j) => (
                      <View key={j} style={styles.legendItem}>
                        <View style={[styles.legendDot, { backgroundColor: l.color }]} />
                        <Text style={styles.legendLabel}>{l.label}</Text>
                      </View>
                    ))}
                  </View>
                )}
              </View>
            </View>
          ))}
        </View>
      )}
    </View>
    );
  };

  return (
    <View style={styles.overlay}>
      <SafeAreaView style={styles.safe} edges={['top', 'bottom']}>
        <View style={styles.topBar}>
          <Pressable onPress={onDone} hitSlop={8} style={styles.skipBtn}>
            <Text style={styles.skipText}>{t('intro.skip')}</Text>
          </Pressable>
        </View>

        <FlatList
          ref={listRef}
          data={pages}
          keyExtractor={(_, i) => `intro-${i}`}
          renderItem={renderPage}
          horizontal
          pagingEnabled
          showsHorizontalScrollIndicator={false}
          getItemLayout={(_, i) => ({ length: width, offset: width * i, index: i })}
          onMomentumScrollEnd={(e) =>
            setIndex(Math.round(e.nativeEvent.contentOffset.x / width))
          }
        />

        <View style={styles.dots}>
          {pages.map((_, i) => (
            <View key={i} style={[styles.dot, i === index && styles.dotActive]} />
          ))}
        </View>

        <Pressable style={styles.nextBtn} onPress={goNext}>
          <Text style={styles.nextText}>
            {isLast ? t('intro.start') : t('intro.next')}
          </Text>
        </Pressable>
      </SafeAreaView>
    </View>
  );
}

const createStyles = (colors: AppColors) =>
  StyleSheet.create({
    overlay: {
      ...StyleSheet.absoluteFillObject,
      backgroundColor: colors.background,
      zIndex: 100,
    },
    safe: { flex: 1 },
    topBar: {
      flexDirection: 'row',
      justifyContent: 'flex-end',
      paddingHorizontal: spacing.md,
      paddingTop: spacing.sm,
    },
    skipBtn: { paddingHorizontal: spacing.sm, paddingVertical: spacing.xs },
    skipText: {
      color: colors.textSecondary,
      fontSize: fontSizes.sm,
      fontWeight: '600',
    },
    page: {
      flex: 1,
      paddingHorizontal: spacing.lg,
      justifyContent: 'center',
    },
    // Opening manifesto page — logo + tagline + mission, centered.
    welcomePage: {
      alignItems: 'center',
    },
    welcomeLogo: {
      width: 104,
      height: 104,
      borderRadius: 26,
      marginBottom: spacing.xl,
    },
    welcomeTagline: {
      color: colors.textPrimary,
      fontSize: fontSizes.xxl,
      fontWeight: '800',
      letterSpacing: 0.2,
      lineHeight: 38,
      textAlign: 'center',
      marginBottom: spacing.lg,
    },
    welcomeBody: {
      color: colors.textSecondary,
      fontSize: fontSizes.md,
      lineHeight: 24,
      textAlign: 'center',
    },
    pageTitle: {
      color: colors.textPrimary,
      fontSize: fontSizes.xl,
      fontWeight: '800',
      letterSpacing: 0.3,
      marginBottom: spacing.xl,
      textAlign: 'center',
    },
    // Big hero stage — a brutalist outlined "stage" the live component
    // sits on. Tall enough to give the popup / ring room to breathe.
    heroStage: {
      alignSelf: 'stretch',
      minHeight: 240,
      borderRadius: radius.lg,
      borderWidth: 1,
      borderColor: colors.borderMuted,
      backgroundColor: colors.surfaceAlt,
      paddingVertical: spacing.xl,
      paddingHorizontal: spacing.lg,
      alignItems: 'center',
      justifyContent: 'center',
      marginBottom: spacing.xl,
    },
    caption: {
      color: colors.textPrimary,
      fontSize: fontSizes.md,
      lineHeight: 22,
      textAlign: 'center',
      paddingHorizontal: spacing.sm,
    },
    // Page 1 — the pin legend, on its own stage.
    rowsStage: {
      borderRadius: radius.lg,
      borderWidth: 1,
      borderColor: colors.borderMuted,
      backgroundColor: colors.surfaceAlt,
      padding: spacing.lg,
      gap: spacing.lg,
    },
    rowBlock: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: spacing.md,
    },
    rowVisual: {
      width: 64,
      alignItems: 'center',
      justifyContent: 'center',
    },
    rowBody: { flex: 1, gap: 6 },
    rowText: {
      color: colors.textPrimary,
      fontSize: fontSizes.md,
      lineHeight: 22,
    },
    legendRow: {
      flexDirection: 'row',
      gap: spacing.md,
      marginTop: 2,
    },
    legendItem: { flexDirection: 'row', alignItems: 'center', gap: 5 },
    legendDot: { width: 12, height: 12, borderRadius: 6 },
    legendLabel: {
      color: colors.textSecondary,
      fontSize: fontSizes.sm,
      fontWeight: '600',
    },
    // Create page — a non-interactive replica of the + FAB.
    fabDemo: {
      width: 76,
      height: 76,
      borderRadius: 38,
      backgroundColor: colors.cta,
      alignItems: 'center',
      justifyContent: 'center',
      shadowColor: '#0A0F1A',
      shadowOffset: { width: 0, height: 6 },
      shadowOpacity: 0.25,
      shadowRadius: 12,
      elevation: 8,
    },
    // Alert page — a small mock: bell + a sample criteria chip.
    alertDemo: { alignItems: 'center', gap: spacing.md },
    alertBell: {
      width: 64,
      height: 64,
      borderRadius: 32,
      backgroundColor: colors.cta + '1F',
      borderWidth: 1,
      borderColor: colors.cta,
      alignItems: 'center',
      justifyContent: 'center',
    },
    alertChip: {
      backgroundColor: colors.surface,
      borderRadius: radius.full,
      borderWidth: 1,
      borderColor: colors.borderMuted,
      paddingHorizontal: spacing.md,
      paddingVertical: 6,
    },
    alertChipText: {
      color: colors.textPrimary,
      fontSize: fontSizes.sm,
      fontWeight: '700',
    },
    dots: {
      flexDirection: 'row',
      justifyContent: 'center',
      gap: 6,
      paddingVertical: spacing.md,
    },
    dot: {
      width: 7,
      height: 7,
      borderRadius: 4,
      backgroundColor: colors.borderMuted,
    },
    dotActive: { backgroundColor: colors.cta, width: 20 },
    nextBtn: {
      backgroundColor: colors.cta,
      borderRadius: radius.sm,
      paddingVertical: spacing.sm + 4,
      alignItems: 'center',
      marginHorizontal: spacing.lg,
      marginBottom: spacing.sm,
    },
    nextText: {
      color: '#FFFFFF',
      fontSize: fontSizes.md,
      fontWeight: '700',
    },
  });
