import { memo, useMemo } from 'react';
import { View, Text, StyleSheet, useWindowDimensions } from 'react-native';
import { Image } from 'expo-image';
import { useTranslation } from 'react-i18next';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius, shadows } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import type { ChannelListItem } from '@/services/channel-service';
import { PressableScale } from '@/components/pressable-scale';
import { SportIcon } from '@/components/sport-icon';
import { ContourLines } from '@/components/partners/contour-lines';
import { sportCategoryColor } from '@/utils/sport-category-color';

// Discussion tile (Partenaires refonte 2026-10-23): the channel photo when it
// has one, else its universe colour + contour lines + the sport glyph.
// `width` = carousel tile; omitted = full width (« Tout voir »), which also
// shows the Rejoindre / Membre tag.
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
  const imageH = full ? 120 : 92;
  const cat = item.sport_key ? categoryOf(item.sport_key) : undefined;
  const tint = sportCategoryColor(cat, colors.cta);
  const sportName = item.sport_key ? t(`sports.${item.sport_key}`, { defaultValue: item.sport_key }) : null;
  const memberText = t('channels.memberCount', { count: item.member_count, defaultValue: '{{count}} membres' });
  const meta = [sportName, item.base_label, memberText].filter(Boolean).join(' · ');

  return (
    <PressableScale style={[styles.tile, { width: tileW }]} onPress={onPress} accessibilityRole="button">
      <View style={[styles.visual, { height: imageH, backgroundColor: tint }]}>
        {item.photo_url ? (
          <Image source={{ uri: item.photo_url }} style={StyleSheet.absoluteFill} contentFit="cover" transition={150} />
        ) : (
          <>
            <ContourLines width={tileW} height={imageH} />
            {item.sport_key ? (
              <View style={styles.glyph}><SportIcon sportKey={item.sport_key} size={full ? 46 : 38} color="#FFFFFF" /></View>
            ) : null}
          </>
        )}
        {!full && (badge || item.is_member) ? (
          <View style={styles.memberBadge}><Text style={styles.memberBadgeText}>{badge ?? t('channels.member', { defaultValue: 'Membre' })}</Text></View>
        ) : null}
      </View>
      <View style={[styles.body, full && styles.bodyFull]}>
        <View style={styles.bodyText}>
          <Text style={styles.name} numberOfLines={full ? 2 : 1}>{item.name}</Text>
          <Text style={styles.meta} numberOfLines={1}>{meta}</Text>
        </View>
        {full ? (
          <View style={[styles.tag, item.is_member ? styles.tagMember : styles.tagJoin]}>
            <Text style={item.is_member ? styles.tagMemberText : styles.tagJoinText}>
              {item.is_member ? t('channels.member', { defaultValue: 'Membre' }) : t('channels.join', { defaultValue: 'Rejoindre' })}
            </Text>
          </View>
        ) : null}
      </View>
    </PressableScale>
  );
});

const createStyles = (colors: AppColors) => StyleSheet.create({
  // overflow stays visible on the tile itself (Android needs it for the
  // elevation shadow); the visual clips its own corners.
  tile: { backgroundColor: colors.surface, borderRadius: 18, ...shadows.card },
  visual: { borderTopLeftRadius: 18, borderTopRightRadius: 18, overflow: 'hidden', alignItems: 'center', justifyContent: 'center' },
  glyph: { opacity: 0.95 },
  memberBadge: { position: 'absolute', left: 10, top: 10, backgroundColor: 'rgba(255,255,255,0.92)', borderRadius: radius.full, paddingHorizontal: spacing.sm, paddingVertical: 3 },
  memberBadgeText: { color: colors.textPrimary, fontSize: 11, fontWeight: '700' },
  body: { paddingHorizontal: spacing.sm + 4, paddingTop: spacing.sm + 2, paddingBottom: spacing.sm + 4 },
  bodyFull: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
  bodyText: { flex: 1, minWidth: 0, gap: 3 },
  name: { color: colors.textPrimary, fontSize: fontSizes.sm + 1, fontWeight: '700' },
  meta: { color: colors.textSecondary, fontSize: fontSizes.xs },
  tag: { borderRadius: radius.full, paddingHorizontal: spacing.sm + 4, paddingVertical: 7 },
  tagMember: { backgroundColor: colors.surfaceAlt },
  tagMemberText: { color: colors.textSecondary, fontSize: fontSizes.xs, fontWeight: '700' },
  tagJoin: { backgroundColor: colors.cta + '1A' },
  tagJoinText: { color: colors.cta, fontSize: fontSizes.xs, fontWeight: '700' },
});
