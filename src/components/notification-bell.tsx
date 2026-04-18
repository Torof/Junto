import { useEffect, useRef } from 'react';
import { Animated, Pressable, View, Text, StyleSheet } from 'react-native';
import { useRouter } from 'expo-router';
import { useQuery } from '@tanstack/react-query';
import { Bell } from 'lucide-react-native';
import { colors, fontSizes, spacing } from '@/constants/theme';
import { notificationService } from '@/services/notification-service';

export function NotificationBell() {
  const router = useRouter();
  const rotation = useRef(new Animated.Value(0)).current;

  const { data: count } = useQuery({
    queryKey: ['notifications-count'],
    queryFn: () => notificationService.getUnreadCount(),
    refetchInterval: 30000,
  });

  const hasUnread = (count ?? 0) > 0;

  useEffect(() => {
    if (!hasUnread) {
      rotation.setValue(0);
      return;
    }

    const wiggle = () => {
      Animated.sequence([
        Animated.timing(rotation, { toValue: 1, duration: 80, useNativeDriver: true }),
        Animated.timing(rotation, { toValue: -1, duration: 80, useNativeDriver: true }),
        Animated.timing(rotation, { toValue: 1, duration: 80, useNativeDriver: true }),
        Animated.timing(rotation, { toValue: -1, duration: 80, useNativeDriver: true }),
        Animated.timing(rotation, { toValue: 0, duration: 80, useNativeDriver: true }),
      ]).start();
    };

    wiggle();
    const interval = setInterval(wiggle, 4000);
    return () => clearInterval(interval);
  }, [hasUnread, rotation]);

  const rotate = rotation.interpolate({
    inputRange: [-1, 0, 1],
    outputRange: ['-15deg', '0deg', '15deg'],
  });

  return (
    <Pressable style={styles.container} onPress={() => router.push('/(auth)/(tabs)/notifications')}>
      <Animated.View style={{ transform: [{ rotate }] }}>
        <Bell
          size={36}
          color={hasUnread ? colors.cta : '#000000'}
          strokeWidth={2}
        />
      </Animated.View>
      {hasUnread && (
        <View style={styles.badge}>
          <Text style={styles.badgeText}>{count! > 99 ? '99+' : count}</Text>
        </View>
      )}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  container: {
    position: 'absolute',
    top: spacing.md,
    left: spacing.md,
    zIndex: 10,
  },
  badge: {
    position: 'absolute',
    top: -6,
    right: -10,
    backgroundColor: colors.error,
    borderRadius: 10,
    minWidth: 16,
    height: 16,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 3,
  },
  badgeText: {
    color: '#fff',
    fontSize: fontSizes.xs - 2,
    fontWeight: 'bold',
  },
});
