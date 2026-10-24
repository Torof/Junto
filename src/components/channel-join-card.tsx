import { useMemo, useState } from 'react';
import { View, Pressable, StyleSheet } from 'react-native';
import { Image } from 'expo-image';
import { useTranslation } from 'react-i18next';
import { MapPin } from 'lucide-react-native';
import { AppText } from '@/components/app-text';
import { UserAvatar } from '@/components/user-avatar';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius, shadows, glow } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { SPORT_UNIVERSE } from '@/constants/sport-universe';
import { sportCategoryColor, mixHex } from '@/utils/sport-category-color';
import type { ChannelDetail } from '@/services/channel-service';

interface Props {
  channel: ChannelDetail;
  // Recent authors from the preview (most recent first) — the roster itself
  // is members-only.
  authors: { id: string; name: string; avatarUrl: string | null }[];
  onJoin: () => Promise<void>;
}

// A channel one has not joined (Scott 2026-10-24): it opens on its real
// messages, sharp, and this card floats over the middle — about two thirds of
// the screen, the channel photo filling it, everything in white on top.
export function ChannelJoinCard({ channel, authors, onJoin }: Props) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const [joining, setJoining] = useState(false);
  const category = channel.sport_key ? SPORT_UNIVERSE[channel.sport_key] : undefined;
  const tint = mixHex(sportCategoryColor(category, colors.cta), '#1F1A15', 0.65);
  const sportName = channel.sport_key ? t(`sports.${channel.sport_key}`, { defaultValue: channel.sport_key }) : null;
  const shown = authors.slice(0, 5);

  const join = async () => {
    setJoining(true);
    try { await onJoin(); } finally { setJoining(false); }
  };

  return (
    <View style={styles.layer} pointerEvents="box-none">
      <View style={[styles.card, { backgroundColor: tint }]}>
        {channel.photo_url ? (
          <Image source={{ uri: channel.photo_url }} style={StyleSheet.absoluteFill} contentFit="cover" cachePolicy="memory-disk" />
        ) : null}
        <View style={[StyleSheet.absoluteFill, styles.veil]} />

        <View style={styles.top}>
          {sportName && (
            <View style={styles.chip}>
              <AppText style={styles.chipText}>{sportName}</AppText>
            </View>
          )}
          <AppText style={styles.name} numberOfLines={3}>{channel.name}</AppText>
          <View style={styles.placeRow}>
            <MapPin size={14} color="#FFFFFF" strokeWidth={2.4} />
            <AppText style={styles.place} numberOfLines={1}>
              {channel.base_label} · {channel.radius_km} km
            </AppText>
          </View>
        </View>

        <View style={styles.bottom}>
          {channel.description ? (
            <AppText style={styles.desc} numberOfLines={5}>{channel.description}</AppText>
          ) : null}
          <View style={styles.membersRow}>
            {shown.length > 0 && (
              <View style={styles.avatars}>
                {shown.map((a, i) => (
                  <View key={a.id} style={[styles.avatarRing, i > 0 && styles.avatarOverlap]}>
                    <UserAvatar name={a.name} avatarUrl={a.avatarUrl} size={28} />
                  </View>
                ))}
              </View>
            )}
            <AppText style={styles.members}>
              {t('group.memberCount', { defaultValue: '{{count}} membres', count: channel.member_count })}
            </AppText>
          </View>
          <Pressable style={[styles.joinBtn, joining && styles.joinBusy]} onPress={join} disabled={joining}>
            <AppText style={styles.joinText}>{t('channels.joinCta', { defaultValue: 'Rejoindre le canal' })}</AppText>
          </Pressable>
          <AppText style={styles.hint}>
            {t('channels.joinHint', { defaultValue: "Tu pourras lire toute la discussion et écrire dès que tu l'auras rejoint." })}
          </AppText>
        </View>
      </View>
    </View>
  );
}

const WHITE = '#FFFFFF';

const createStyles = (colors: AppColors) => StyleSheet.create({
  layer: { ...StyleSheet.absoluteFillObject, alignItems: 'center', justifyContent: 'center', paddingHorizontal: spacing.lg },
  card: {
    width: '100%', minHeight: '62%', maxHeight: '80%',
    borderRadius: radius.xl, overflow: 'hidden',
    justifyContent: 'space-between',
    padding: spacing.lg, gap: spacing.lg,
    ...shadows.sheet,
  },
  veil: { backgroundColor: 'rgba(15,12,9,0.48)' },
  top: { gap: spacing.sm },
  chip: {
    alignSelf: 'flex-start', backgroundColor: 'rgba(255,255,255,0.22)',
    borderRadius: radius.full, paddingHorizontal: spacing.sm + 2, paddingVertical: 3,
  },
  chipText: { color: WHITE, fontSize: fontSizes.xs, fontWeight: '700' },
  name: { color: WHITE, fontSize: fontSizes.xl, fontWeight: '800', lineHeight: 30 },
  placeRow: { flexDirection: 'row', alignItems: 'center', gap: 5 },
  place: { color: WHITE, fontSize: fontSizes.sm, fontWeight: '600', opacity: 0.92 },
  bottom: { gap: spacing.md },
  desc: { color: WHITE, fontSize: fontSizes.md, lineHeight: 22 },
  membersRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
  avatars: { flexDirection: 'row' },
  avatarRing: { borderWidth: 2, borderColor: WHITE, borderRadius: 16 },
  avatarOverlap: { marginLeft: -9 },
  members: { color: WHITE, fontSize: fontSizes.sm, fontWeight: '700' },
  joinBtn: {
    backgroundColor: colors.cta, borderRadius: radius.full,
    paddingVertical: spacing.md - 2, alignItems: 'center',
    ...glow(colors.cta),
  },
  joinBusy: { opacity: 0.6 },
  joinText: { color: WHITE, fontSize: fontSizes.md, fontWeight: '800' },
  hint: { color: WHITE, fontSize: fontSizes.xs, textAlign: 'center', opacity: 0.85, marginTop: -spacing.xs },
});
