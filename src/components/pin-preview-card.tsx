import { useEffect, useMemo, useRef } from 'react';
import { View, Text, Image, Pressable, StyleSheet, Animated, Easing } from 'react-native';
import { ChevronRight, MapPin } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { fontSizes, fonts, spacing, radius } from '@/constants/theme';
import { type NearbyPro } from '@/services/pro-service';
import { type ProOffering } from '@/services/pro-offering-service';
import { getSportIcon } from '@/constants/sport-icons';
import { sportCategoryColor } from '@/utils/sport-category-color';

interface ProVariant {
  variant: 'pro';
  pro: NearbyPro;
}

interface OfferingVariant {
  variant: 'offering';
  offering: ProOffering;
}

type Props = (ProVariant | OfferingVariant) & {
  onPress: () => void;
};

// Google-Maps-style preview card that slides up from the bottom when
// the user taps a pro storefront or offering pin. First tap shows
// this card; second tap on the same pin (or anywhere on the card)
// opens the full detail page. Tapping the map elsewhere dismisses.
//
// Slides up via translateY animation when mounted; the parent unmounts
// it to dismiss (snap-out, no exit animation — keeps the flow tight).
export function PinPreviewCard(props: Props) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);

  // Slide-up entrance.
  const translateY = useRef(new Animated.Value(120)).current;
  useEffect(() => {
    Animated.timing(translateY, {
      toValue: 0,
      duration: 220,
      easing: Easing.out(Easing.quad),
      useNativeDriver: true,
    }).start();
  }, [translateY]);

  if (props.variant === 'pro') {
    const { pro } = props;
    const thumb = pro.pin_image_url;
    const initial = (pro.display_name?.trim().charAt(0) ?? '?').toUpperCase();
    return (
      <Animated.View style={[styles.wrap, { transform: [{ translateY }] }]}>
        <Pressable style={styles.card} onPress={props.onPress}>
          {thumb ? (
            <Image source={{ uri: thumb }} style={styles.thumb} />
          ) : (
            <View style={[styles.thumb, styles.thumbPlaceholder]}>
              <Text style={styles.thumbInitial}>{initial}</Text>
            </View>
          )}
          <View style={styles.body}>
            <Text style={styles.kicker}>Page pro</Text>
            <Text style={styles.title} numberOfLines={1}>{pro.display_name}</Text>
          </View>
          <ChevronRight size={20} color={colors.textSecondary} />
        </Pressable>
      </Animated.View>
    );
  }

  // offering
  const { offering } = props;
  const accent = sportCategoryColor(offering.sport_category, colors.cta);
  return (
    <Animated.View style={[styles.wrap, { transform: [{ translateY }] }]}>
      <Pressable style={styles.card} onPress={props.onPress}>
        <View style={[styles.thumb, styles.thumbPlaceholder, { backgroundColor: `${accent}22` }]}>
          <Text style={styles.thumbEmoji}>{getSportIcon(offering.sport_key)}</Text>
        </View>
        <View style={styles.body}>
          <Text style={[styles.kicker, { color: accent }]}>Activité récurrente</Text>
          <Text style={styles.title} numberOfLines={1}>{offering.title}</Text>
          <View style={styles.locationRow}>
            <MapPin size={11} color={colors.textSecondary} strokeWidth={2.4} />
            <Text style={styles.locationText} numberOfLines={1}>{offering.location_name}</Text>
          </View>
        </View>
        <ChevronRight size={20} color={colors.textSecondary} />
      </Pressable>
    </Animated.View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  // Floats above the ActivitiesBottomSheet's collapsed handle.
  // Parent controls position via wrapping View — this just animates
  // its own transform.
  wrap: {
    paddingHorizontal: spacing.md,
  },
  card: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    backgroundColor: colors.surface,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.borderMuted,
    padding: spacing.sm,
    shadowColor: '#0A0F1A',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.18,
    shadowRadius: 6,
    elevation: 6,
  },
  thumb: { width: 48, height: 48, borderRadius: radius.sm, backgroundColor: colors.background },
  thumbPlaceholder: { alignItems: 'center', justifyContent: 'center' },
  thumbInitial: { color: '#FFFFFF', fontSize: 20, fontWeight: '800' },
  thumbEmoji: { fontSize: 26 },
  body: { flex: 1, gap: 2 },
  kicker: {
    color: colors.textMuted,
    fontSize: fontSizes.xs - 1,
    fontWeight: '800',
    letterSpacing: 1,
    textTransform: 'uppercase',
  },
  title: { color: colors.textPrimary, fontSize: fontSizes.md, fontFamily: fonts.title, letterSpacing: -0.2 },
  locationRow: { flexDirection: 'row', alignItems: 'center', gap: 4 },
  locationText: { color: colors.textSecondary, fontSize: fontSizes.xs, flexShrink: 1 },
});
