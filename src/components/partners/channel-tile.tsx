import { memo, useMemo } from 'react';
import { View, StyleSheet, useWindowDimensions } from 'react-native';
import { AppText } from '@/components/app-text';
import { Image } from 'expo-image';
import { MapPin, Users } from 'lucide-react-native';
import { useTranslation } from 'react-i18next';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius, shadows } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import type { ChannelListItem } from '@/services/channel-service';
import { PressableScale } from '@/components/pressable-scale';
import { SportIcon } from '@/components/sport-icon';
import { ContourLines } from '@/components/partners/contour-lines';
import { sportCategoryColor } from '@/utils/sport-category-color';

// Discussion tile (Scott 2026-10-24, board « Non-lus · tuiles de discussion »):
// the language of the join card — the channel photo fills the tile (else its
// universe colour + contour lines + the sport glyph), a solid veil, everything
// in white on top: sport chip with its icon, name, place and member count with
// icons. `width` = carousel tile (with its « why » badge); omitted = full width
// (« Tout voir »), which carries the Rejoindre / Membre tag.
export const ChannelTile = memo(function ChannelTile({ item, categoryOf, width, badge, onPress }: {
  item: ChannelListItem;
  categoryOf: (sportKey: string) => string | undefined;
  width?: number;
  // Why the tile is in a carousel (« Membre », « Près de toi », « Ailleurs »).
  badge?: string;
  onPress: () => void;
}) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const { width: screenW } = useWindowDimensions();
  const full = !width;
  const tileW = width ?? screenW - spacing.md * 2;
  const tileH = 150;
  const cat = item.sport_key ? categoryOf(item.sport_key) : undefined;
  const tint = sportCategoryColor(cat, colors.cta);
  const sportName = item.sport_key ? t(`sports.${item.sport_key}`, { defaultValue: item.sport_key }) : null;
  const carouselBadge = !full ? (badge ?? (item.is_member ? t('channels.member', { defaultValue: 'Membre' }) : null)) : null;

  return (
    <PressableScale style={[styles.tile, { width: tileW, height: tileH, backgroundColor: tint }]} onPress={onPress} accessibilityRole="button">
      <View style={styles.clip}>
        {item.photo_url ? (
          <>
            <Image source={{ uri: item.photo_url }} style={StyleSheet.absoluteFill} contentFit="cover" transition={150} />
            <View style={[StyleSheet.absoluteFill, styles.veil]} />
          </>
        ) : (
          <>
            <ContourLines width={tileW} height={tileH} />
            {item.sport_key ? (
              <View style={styles.glyph}><SportIcon sportKey={item.sport_key} size={full ? 64 : 48} color="#FFFFFF" /></View>
            ) : null}
          </>
        )}
      </View>

      <View style={styles.top}>
        {carouselBadge ? (
          <View style={styles.badge}><AppText style={styles.badgeText} numberOfLines={1}>{carouselBadge}</AppText></View>
        ) : null}
        {sportName && item.sport_key ? (
          <View style={styles.sport}>
            <SportIcon sportKey={item.sport_key} size={13} color={WHITE} />
            <AppText style={styles.sportText} numberOfLines={1}>{sportName}</AppText>
          </View>
        ) : null}
      </View>

      <View style={styles.bottom}>
        <AppText style={[styles.name, !full && styles.nameSmall]} numberOfLines={2}>{item.name}</AppText>
        <View style={styles.metaRow}>
          <View style={styles.metaItem}>
            <MapPin size={12} color={WHITE} strokeWidth={2.4} />
            <AppText style={styles.meta} numberOfLines={1}>{item.base_label}</AppText>
          </View>
          <View style={styles.metaItemFixed}>
            <Users size={12} color={WHITE} strokeWidth={2.4} />
            <AppText style={styles.meta}>{item.member_count}</AppText>
          </View>
          {full ? (
            <View style={[styles.tag, item.is_member ? styles.tagMember : { backgroundColor: colors.cta }]}>
              <AppText style={styles.tagText}>
                {item.is_member ? t('channels.member', { defaultValue: 'Membre' }) : t('channels.join', { defaultValue: 'Rejoindre' })}
              </AppText>
            </View>
          ) : null}
        </View>
      </View>
    </PressableScale>
  );
});

const WHITE = '#FFFFFF';

const createStyles = (colors: AppColors) => StyleSheet.create({
  // overflow stays visible on the tile itself (Android needs it for the
  // elevation shadow); the clip layer rounds the photo.
  tile: { borderRadius: 18, padding: spacing.sm + 4, justifyContent: 'space-between', ...shadows.card },
  clip: { ...StyleSheet.absoluteFillObject, borderRadius: 18, overflow: 'hidden', alignItems: 'center', justifyContent: 'center' },
  veil: { backgroundColor: 'rgba(15,12,9,0.42)' },
  glyph: { opacity: 0.35 },
  top: { flexDirection: 'row', alignItems: 'flex-start', gap: spacing.xs },
  badge: { flexShrink: 1, backgroundColor: 'rgba(255,255,255,0.92)', borderRadius: radius.full, paddingHorizontal: spacing.sm, paddingVertical: 3 },
  badgeText: { color: colors.textPrimary, fontSize: 11, fontWeight: '700' },
  sport: {
    marginLeft: 'auto', flexShrink: 1, flexDirection: 'row', alignItems: 'center', gap: 5,
    backgroundColor: 'rgba(255,255,255,0.22)', borderRadius: radius.full, paddingHorizontal: 8, paddingVertical: 4,
  },
  sportText: { color: WHITE, fontSize: 11, fontWeight: '700' },
  bottom: { gap: 6 },
  name: { color: WHITE, fontSize: fontSizes.lg, fontWeight: '800', lineHeight: 22 },
  nameSmall: { fontSize: fontSizes.sm, lineHeight: 18 },
  metaRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm + 4 },
  metaItem: { flexShrink: 1, flexDirection: 'row', alignItems: 'center', gap: 4 },
  metaItemFixed: { flexDirection: 'row', alignItems: 'center', gap: 4 },
  meta: { color: WHITE, fontSize: fontSizes.xs, fontWeight: '600' },
  tag: { marginLeft: 'auto', borderRadius: radius.full, paddingHorizontal: spacing.sm + 4, paddingVertical: 6 },
  tagMember: { backgroundColor: 'rgba(255,255,255,0.25)' },
  tagText: { color: WHITE, fontSize: fontSizes.xs, fontWeight: '800' },
});
