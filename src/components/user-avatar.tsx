import { View, Text, Image, StyleSheet } from 'react-native';
import { colors, fontSizes } from '@/constants/theme';

interface UserAvatarProps {
  name: string;
  avatarUrl?: string | null;
  size?: number;
}

export function UserAvatar({ name, avatarUrl, size = 40 }: UserAvatarProps) {
  const borderRadius = size / 2;
  const fontSize = size * 0.4;

  if (avatarUrl) {
    return (
      <Image
        source={{ uri: avatarUrl }}
        style={[styles.image, { width: size, height: size, borderRadius }]}
      />
    );
  }

  return (
    <View style={[styles.fallback, { width: size, height: size, borderRadius }]}>
      <Text style={[styles.initial, { fontSize }]}>
        {(name || '?').charAt(0).toUpperCase()}
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
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
});
