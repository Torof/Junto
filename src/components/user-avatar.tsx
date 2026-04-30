import { useMemo } from 'react';
import { View, Text, Image, StyleSheet } from 'react-native';
import { Check } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';

interface UserAvatarProps {
  name: string;
  avatarUrl?: string | null;
  size?: number;
  // When true, overlays a small green tick at the bottom-right indicating
  // presence has been confirmed for this user on a given activity.
  confirmedPresent?: boolean;
  // When true, overlays a small orange tick at the top-right indicating
  // this user is the activity's creator/organizer. Coexists with
  // `confirmedPresent` (different corner).
  isOrganizer?: boolean;
}

export function UserAvatar({ name, avatarUrl, size = 40, confirmedPresent = false, isOrganizer = false }: UserAvatarProps) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const borderRadius = size / 2;
  const fontSize = size * 0.4;

  // Badge size scales with the avatar — kept readable down to 14px avatars.
  const badgeSize = Math.max(10, Math.round(size * 0.38));
  const iconSize = Math.max(7, Math.round(badgeSize * 0.6));
  const borderWidth = size >= 36 ? 2 : 1.5;

  const inner = avatarUrl ? (
    <Image
      source={{ uri: avatarUrl }}
      style={[styles.image, { width: size, height: size, borderRadius }]}
    />
  ) : (
    <View style={[styles.fallback, { width: size, height: size, borderRadius }]}>
      <Text style={[styles.initial, { fontSize }]}>
        {(name || '?').charAt(0).toUpperCase()}
      </Text>
    </View>
  );

  if (!confirmedPresent && !isOrganizer) return inner;

  return (
    <View style={{ width: size, height: size }}>
      {inner}
      {confirmedPresent && (
        <View
          style={[
            styles.badge,
            styles.badgePresence,
            {
              width: badgeSize,
              height: badgeSize,
              borderRadius: badgeSize / 2,
              borderWidth,
              bottom: -borderWidth,
              right: -borderWidth,
            },
          ]}
        >
          <Check size={iconSize} color="#FFFFFF" strokeWidth={3.2} />
        </View>
      )}
      {isOrganizer && (
        <View
          style={[
            styles.badge,
            styles.badgeOrganizer,
            {
              width: badgeSize,
              height: badgeSize,
              borderRadius: badgeSize / 2,
              borderWidth,
              top: -borderWidth,
              right: -borderWidth,
            },
          ]}
        >
          <Check size={iconSize} color="#FFFFFF" strokeWidth={3.2} />
        </View>
      )}
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  image: {
    backgroundColor: colors.surface,
  },
  fallback: {
    backgroundColor: colors.surface,
    alignItems: 'center',
    justifyContent: 'center',
  },
  initial: {
    color: colors.cta,
    fontWeight: 'bold',
  },
  badge: {
    position: 'absolute',
    borderColor: colors.surface,
    alignItems: 'center',
    justifyContent: 'center',
  },
  badgePresence: { backgroundColor: colors.success },
  badgeOrganizer: { backgroundColor: colors.cta },
});
