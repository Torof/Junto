import { useState, useMemo, useRef, type ReactNode } from 'react';
import {
  View,
  Text,
  Pressable,
  StyleSheet,
  FlatList,
  useWindowDimensions,
  type ListRenderItemInfo,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useTranslation } from 'react-i18next';
import { Plus, BellRing, Layers, UserRound } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { ActivityPin } from './activity-pin';
import { ProOfferingPin } from './pro-offering-pin';
import { ProPin } from './pro-pin';
import type { NearbyActivity } from '@/services/activity-service';
import type { ProOffering } from '@/services/pro-offering-service';

// First-run intro shown once on the map (gated by users.tutorial_seen_at).
// A pure next-tap carousel — NO element anchoring, NO interaction beyond
// paging — so it can't break or trap a user when the UI changes (unlike
// the coach-mark tutorial it replaces). Element visuals are live
// components where possible (pins, etc.) and small screenshot crops
// elsewhere; explanatory copy lives in i18n, never baked into an image.

// Display-only stubs — the pin components read only sport_key / status /
// starts_at, so a minimal cast is enough to render them live (and they
// stay in sync with the real map pins automatically).
const DEMO_UA = {
  starts_at: '2030-06-15T10:00:00.000Z',
  status: 'published',
  sport_key: 'escalade',
} as unknown as NearbyActivity;
const DEMO_RA = { sport_key: 'yoga' } as unknown as ProOffering;

interface IntroBlock {
  visual: ReactNode;
  text: string;
}
interface IntroPage {
  title: string;
  blocks: IntroBlock[];
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
        title: t('intro.pins.title'),
        blocks: [
          { visual: <ActivityPin activity={DEMO_UA} />, text: t('intro.pins.ua') },
          { visual: <ProOfferingPin offering={DEMO_RA} />, text: t('intro.pins.ra') },
          { visual: <ProPin displayName="M" pinImageUrl={null} />, text: t('intro.pins.pp') },
        ],
      },
      {
        title: t('intro.join.title'),
        blocks: [
          { visual: <CropSlot label="popup + Voir plus" icon={<Layers size={22} color={colors.textMuted} strokeWidth={2} />} styles={styles} />, text: t('intro.join.tap') },
          { visual: <CropSlot label="onglets" icon={<Layers size={22} color={colors.textMuted} strokeWidth={2} />} styles={styles} />, text: t('intro.join.inside') },
        ],
      },
      {
        title: t('intro.create.title'),
        blocks: [
          { visual: <CropSlot label="bouton +" icon={<Plus size={22} color={colors.cta} strokeWidth={2.6} />} styles={styles} />, text: t('intro.create.body') },
        ],
      },
      {
        title: t('intro.alert.title'),
        blocks: [
          { visual: <CropSlot label="alerte" icon={<BellRing size={22} color={colors.cta} strokeWidth={2.2} />} styles={styles} />, text: t('intro.alert.body') },
        ],
      },
      {
        title: t('intro.profile.title'),
        blocks: [
          { visual: <CropSlot label="profil · fiabilité" icon={<UserRound size={22} color={colors.textMuted} strokeWidth={2} />} styles={styles} />, text: t('intro.profile.body') },
        ],
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

  const renderPage = ({ item }: ListRenderItemInfo<IntroPage>) => (
    <View style={[styles.page, { width }]}>
      <Text style={styles.pageTitle}>{item.title}</Text>
      <View style={styles.blocks}>
        {item.blocks.map((block, i) => (
          <View key={i} style={styles.block}>
            <View style={styles.blockVisual}>{block.visual}</View>
            <Text style={styles.blockText}>{block.text}</Text>
          </View>
        ))}
      </View>
    </View>
  );

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

// Placeholder for a screenshot crop to be slotted in. Renders a dashed
// card with a hint icon + label so the flow reads end-to-end before the
// real crops land.
function CropSlot({
  label,
  icon,
  styles,
}: {
  label: string;
  icon: ReactNode;
  styles: ReturnType<typeof createStyles>;
}) {
  return (
    <View style={styles.cropSlot}>
      {icon}
      <Text style={styles.cropLabel}>{label}</Text>
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
    pageTitle: {
      color: colors.textPrimary,
      fontSize: fontSizes.xl,
      fontWeight: '800',
      letterSpacing: 0.3,
      marginBottom: spacing.xl,
      textAlign: 'center',
    },
    blocks: { gap: spacing.lg },
    block: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: spacing.md,
    },
    blockVisual: {
      width: 64,
      alignItems: 'center',
      justifyContent: 'center',
    },
    blockText: {
      flex: 1,
      color: colors.textPrimary,
      fontSize: fontSizes.md,
      lineHeight: 22,
    },
    cropSlot: {
      width: 56,
      height: 56,
      borderRadius: radius.sm,
      borderWidth: 1.5,
      borderColor: colors.borderMuted,
      borderStyle: 'dashed',
      alignItems: 'center',
      justifyContent: 'center',
      gap: 2,
    },
    cropLabel: {
      color: colors.textMuted,
      fontSize: 7,
      textAlign: 'center',
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
