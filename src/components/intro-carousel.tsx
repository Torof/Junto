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
import dayjs from 'dayjs';
import { Plus, BellRing, Clock, Backpack, ShieldCheck, type LucideIcon } from 'lucide-react-native';
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
// minimal cast is enough to render them live. All heroes are
// pointerEvents:none so they never catch a swipe.
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

const SPORT_EMOJIS = ['🧗', '🥾', '🚵', '⛷️', '🪂', '🛶'];

interface IntroPage {
  title: string;
  welcome?: { tagline: string; body: string };
  body?: ReactNode; // bespoke page content (pins states + types)
  hero?: ReactNode; // big single hero
  caption?: string;
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

  // The activity pin colors itself from time-status: regular (upcoming) →
  // frame, < 2h to start → yellow, in-progress → green. Demo one of each.
  const stateDemos = useMemo(() => {
    const base = { sport_key: 'escalade' };
    return {
      regular: { ...base, status: 'published', starts_at: '2030-06-15T10:00:00.000Z' } as unknown as NearbyActivity,
      soon: { ...base, status: 'published', starts_at: dayjs().add(1, 'hour').toISOString() } as unknown as NearbyActivity,
      inProgress: { ...base, status: 'in_progress', starts_at: '2030-06-15T10:00:00.000Z' } as unknown as NearbyActivity,
    };
  }, []);

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
        body: (
          <View style={styles.pinsBody}>
            <Text style={styles.pinsLead}>{t('intro.pins.ua')}</Text>
            <View style={styles.stateRow}>
              <StatePin activity={stateDemos.regular} label={t('intro.pins.upcoming')} styles={styles} />
              <StatePin activity={stateDemos.soon} label={t('intro.pins.soon')} styles={styles} />
              <StatePin activity={stateDemos.inProgress} label={t('intro.pins.inProgress')} styles={styles} />
            </View>
            <View style={styles.pinTypeRow}>
              <View style={styles.pinTypeVisual}><ProOfferingPin offering={DEMO_RA} /></View>
              <Text style={styles.pinTypeText}>{t('intro.pins.ra')}</Text>
            </View>
            <View style={styles.pinTypeRow}>
              <View style={styles.pinTypeVisual}><ProPin displayName="M" pinImageUrl={null} /></View>
              <Text style={styles.pinTypeText}>{t('intro.pins.pp')}</Text>
            </View>
          </View>
        ),
      },
      {
        title: t('intro.join.title'),
        hero: (
          <View style={styles.joinHero}>
            <ActivityPopup activity={DEMO_POPUP} onPress={() => {}} />
            <View style={styles.rejoindreBtn}>
              <Text style={styles.rejoindreBtnText}>{t('activity.join')}</Text>
            </View>
          </View>
        ),
        caption: `${t('intro.join.tap')}\n\n${t('intro.join.inside')}`,
      },
      {
        title: t('intro.create.title'),
        hero: (
          <View style={styles.createHero}>
            <View style={styles.fabDemo}>
              <Plus size={26} color="#FFFFFF" strokeWidth={2.6} />
            </View>
            <View style={styles.sportsEmojiRow}>
              {SPORT_EMOJIS.map((e, i) => (
                <Text key={i} style={styles.sportsEmoji}>{e}</Text>
              ))}
            </View>
            <Text style={styles.sportsCount}>{t('intro.create.sports')}</Text>
          </View>
        ),
        caption: t('intro.create.body'),
      },
      {
        title: t('intro.alert.title'),
        hero: (
          <View style={styles.alertDemo}>
            <View style={styles.alertBell}>
              <BellRing size={20} color={colors.cta} strokeWidth={2.2} />
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
          <View style={styles.profileHero}>
            <ReliabilityRing score={82} size={118} strokeWidth={11} showLabel>
              <UserAvatar name="M" avatarUrl={null} size={76} />
            </ReliabilityRing>
            <View style={styles.badgeRow}>
              <SampleBadge icon={Clock} label={t('badges.short.punctual', { defaultValue: 'Ponctuel' })} color={colors.success} styles={styles} />
              <SampleBadge icon={Backpack} label={t('badges.short.prepared', { defaultValue: 'Équipé' })} color={colors.cta} styles={styles} />
              <SampleBadge icon={ShieldCheck} label={t('badges.short.prudent', { defaultValue: 'Prudent' })} color="#4B7CB8" styles={styles} />
            </View>
          </View>
        ),
        caption: t('intro.profile.body'),
      },
    ],
    [t, colors, styles, stateDemos],
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
          <Image source={require('../../assets/junto_icon_round.png')} style={styles.welcomeLogo} />
          <Text style={styles.welcomeTagline}>{item.welcome.tagline}</Text>
          <Text style={styles.welcomeBody}>{item.welcome.body}</Text>
        </View>
      );
    }
    if (item.body) {
      return (
        <View style={[styles.page, { width }]}>
          <Text style={styles.pageTitle}>{item.title}</Text>
          <View style={styles.bodyStage} pointerEvents="none">{item.body}</View>
        </View>
      );
    }
    return (
      <View style={[styles.page, { width }]}>
        <Text style={styles.pageTitle}>{item.title}</Text>
        <View style={styles.heroStage} pointerEvents="none">{item.hero}</View>
        {item.caption && <Text style={styles.caption}>{item.caption}</Text>}
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
          <Text style={styles.nextText}>{isLast ? t('intro.start') : t('intro.next')}</Text>
        </Pressable>
      </SafeAreaView>
    </View>
  );
}

function StatePin({
  activity,
  label,
  styles,
}: {
  activity: NearbyActivity;
  label: string;
  styles: ReturnType<typeof createStyles>;
}) {
  return (
    <View style={styles.statePinCol}>
      <ActivityPin activity={activity} />
      <Text style={styles.statePinLabel}>{label}</Text>
    </View>
  );
}

function SampleBadge({
  icon: Icon,
  label,
  color,
  styles,
}: {
  icon: LucideIcon;
  label: string;
  color: string;
  styles: ReturnType<typeof createStyles>;
}) {
  return (
    <View style={styles.badgeChip}>
      <View style={[styles.badgeMedal, { backgroundColor: color + '22', borderColor: color }]}>
        <Icon size={16} color={color} strokeWidth={2.2} />
      </View>
      <Text style={styles.badgeLabel} numberOfLines={1}>{label}</Text>
    </View>
  );
}

const createStyles = (colors: AppColors) =>
  StyleSheet.create({
    overlay: { ...StyleSheet.absoluteFillObject, backgroundColor: colors.background, zIndex: 100 },
    safe: { flex: 1 },
    topBar: { flexDirection: 'row', justifyContent: 'flex-end', paddingHorizontal: spacing.md, paddingTop: spacing.sm },
    skipBtn: { paddingHorizontal: spacing.sm, paddingVertical: spacing.xs },
    skipText: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: '600' },
    page: { flex: 1, paddingHorizontal: spacing.lg, justifyContent: 'center' },

    // Opening manifesto page.
    welcomePage: { alignItems: 'center' },
    welcomeLogo: { width: 104, height: 104, borderRadius: 26, marginBottom: spacing.xl },
    welcomeTagline: {
      color: colors.textPrimary, fontSize: fontSizes.xxl, fontWeight: '800',
      letterSpacing: 0.2, lineHeight: 38, textAlign: 'center', marginBottom: spacing.lg,
    },
    welcomeBody: { color: colors.textSecondary, fontSize: fontSizes.md, lineHeight: 24, textAlign: 'center' },

    pageTitle: {
      color: colors.textPrimary, fontSize: fontSizes.xl, fontWeight: '800',
      letterSpacing: 0.3, marginBottom: spacing.xl, textAlign: 'center',
    },

    // Big hero stage — the live component sits on this outlined stage.
    heroStage: {
      alignSelf: 'stretch', minHeight: 220, borderRadius: radius.lg,
      borderWidth: 1, borderColor: colors.borderMuted, backgroundColor: colors.surfaceAlt,
      paddingVertical: spacing.xl, paddingHorizontal: spacing.lg,
      alignItems: 'center', justifyContent: 'center', marginBottom: spacing.xl,
    },
    caption: {
      color: colors.textPrimary, fontSize: fontSizes.md, lineHeight: 22,
      textAlign: 'center', paddingHorizontal: spacing.sm,
    },

    // Pins page — states + types on a stage.
    bodyStage: {
      borderRadius: radius.lg, borderWidth: 1, borderColor: colors.borderMuted,
      backgroundColor: colors.surfaceAlt, padding: spacing.lg, gap: spacing.lg,
    },
    pinsLead: { color: colors.textPrimary, fontSize: fontSizes.md, lineHeight: 22 },
    pinsBody: { gap: spacing.lg },
    stateRow: { flexDirection: 'row', justifyContent: 'space-around', alignItems: 'flex-start' },
    statePinCol: { alignItems: 'center', gap: 6, width: 92 },
    statePinLabel: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: '700', textAlign: 'center' },
    pinTypeRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.md },
    pinTypeVisual: { width: 64, alignItems: 'center', justifyContent: 'center' },
    pinTypeText: { flex: 1, color: colors.textPrimary, fontSize: fontSizes.md, lineHeight: 22 },

    // Join page — popup + the real Rejoindre CTA.
    joinHero: { alignItems: 'center', gap: spacing.md },
    rejoindreBtn: {
      backgroundColor: colors.cta, borderRadius: radius.sm,
      paddingVertical: spacing.sm + 2, paddingHorizontal: spacing.xl + spacing.lg, alignItems: 'center',
    },
    rejoindreBtnText: { color: '#FFFFFF', fontSize: fontSizes.md, fontWeight: '700' },

    // Create page — small + FAB, a teaser of sports, the count.
    createHero: { alignItems: 'center', gap: spacing.md },
    fabDemo: {
      width: 52, height: 52, borderRadius: 26, backgroundColor: colors.cta,
      alignItems: 'center', justifyContent: 'center',
      shadowColor: '#0A0F1A', shadowOffset: { width: 0, height: 5 }, shadowOpacity: 0.25, shadowRadius: 10, elevation: 6,
    },
    sportsEmojiRow: { flexDirection: 'row', gap: spacing.sm, marginTop: spacing.xs },
    sportsEmoji: { fontSize: 24 },
    sportsCount: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: '700' },

    // Alert page — small bell + a sample criteria chip.
    alertDemo: { alignItems: 'center', gap: spacing.sm },
    alertBell: {
      width: 44, height: 44, borderRadius: 22, backgroundColor: colors.cta + '1F',
      borderWidth: 1, borderColor: colors.cta, alignItems: 'center', justifyContent: 'center',
    },
    alertChip: {
      backgroundColor: colors.surface, borderRadius: radius.full, borderWidth: 1, borderColor: colors.borderMuted,
      paddingHorizontal: spacing.md, paddingVertical: 6,
    },
    alertChipText: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '700' },

    // Profile page — reliability ring + sample badges.
    profileHero: { alignItems: 'center', gap: spacing.lg },
    badgeRow: { flexDirection: 'row', gap: spacing.md, justifyContent: 'center' },
    badgeChip: { alignItems: 'center', gap: 5, width: 64 },
    badgeMedal: {
      width: 40, height: 40, borderRadius: 20, borderWidth: 1.5,
      alignItems: 'center', justifyContent: 'center',
    },
    badgeLabel: { color: colors.textSecondary, fontSize: fontSizes.xs, fontWeight: '700', textAlign: 'center' },

    dots: { flexDirection: 'row', justifyContent: 'center', gap: 6, paddingVertical: spacing.md },
    dot: { width: 7, height: 7, borderRadius: 4, backgroundColor: colors.borderMuted },
    dotActive: { backgroundColor: colors.cta, width: 20 },
    nextBtn: {
      backgroundColor: colors.cta, borderRadius: radius.sm, paddingVertical: spacing.sm + 4,
      alignItems: 'center', marginHorizontal: spacing.lg, marginBottom: spacing.sm,
    },
    nextText: { color: '#FFFFFF', fontSize: fontSizes.md, fontWeight: '700' },
  });
