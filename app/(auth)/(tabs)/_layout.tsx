import { useEffect, useMemo, useRef } from 'react';
import { Animated, View, Text, StyleSheet } from 'react-native';
import { Tabs } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { useQuery } from '@tanstack/react-query';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Map, ListChecks, Bell, MessageSquare, User, type LucideIcon } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import { fontSizes } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { notificationService } from '@/services/notification-service';
import { useMapStore } from '@/store/map-store';
import { conversationService } from '@/services/conversation-service';
import { useMessageStore } from '@/store/message-store';
import { supabase } from '@/services/supabase';

function TabIcon({ icon: IconComponent, focused }: { icon: LucideIcon; focused: boolean }) {
  const colors = useColors();
  return (
    <IconComponent
      size={26}
      color={focused ? colors.cta : colors.textSecondary}
      strokeWidth={focused ? 2.4 : 2}
    />
  );
}

function NotificationTabIcon({ focused }: { focused: boolean }) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const rotation = useRef(new Animated.Value(0)).current;

  const { data: count } = useQuery({
    queryKey: ['notifications-count'],
    queryFn: () => notificationService.getUnreadCount(),
    refetchInterval: 30000,
  });

  const hasUnread = (count ?? 0) > 0;

  useEffect(() => {
    if (!hasUnread || focused) {
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
  }, [hasUnread, focused, rotation]);

  const rotate = rotation.interpolate({
    inputRange: [-1, 0, 1],
    outputRange: ['-15deg', '0deg', '15deg'],
  });

  return (
    <View style={styles.bellContainer}>
      <Animated.View style={{ transform: [{ rotate }] }}>
        <Bell
          size={26}
          color={focused ? colors.cta : (hasUnread ? colors.cta : colors.textSecondary)}
          strokeWidth={focused ? 2.4 : 2}
        />
      </Animated.View>
      {hasUnread && (
        <View style={styles.badge}>
          <Text style={styles.badgeText}>{count! > 99 ? '99+' : count}</Text>
        </View>
      )}
    </View>
  );
}

function MessageTabIcon({ focused }: { focused: boolean }) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { isConversationUnread } = useMessageStore();

  const { data: currentUserId } = useQuery({
    queryKey: ['currentUser-id'],
    queryFn: async () => (await supabase.auth.getUser()).data.user?.id,
  });

  const { data: conversations } = useQuery({
    queryKey: ['conversations-badge'],
    queryFn: () => conversationService.getAll(),
    refetchInterval: 30000,
  });

  const hasUnread = (conversations ?? []).some(
    (c) => isConversationUnread(c.id, c.last_message_at, c.last_message_sender_id, c.last_message_metadata, currentUserId)
  );

  return (
    <View style={styles.bellContainer}>
      <MessageSquare size={26} color={focused ? colors.cta : colors.textSecondary} strokeWidth={focused ? 2.4 : 2} />
      {hasUnread && <View style={styles.dot} />}
    </View>
  );
}

export default function TabsLayout() {
  const colors = useColors();
  const { t } = useTranslation();
  const insets = useSafeAreaInsets();

  return (
    <Tabs
      screenOptions={{
        tabBarStyle: {
          backgroundColor: colors.background,
          borderTopColor: colors.surface,
          height: 64 + insets.bottom,
          paddingBottom: insets.bottom + 4,
          paddingTop: 8,
        },
        tabBarShowLabel: false,
        tabBarActiveTintColor: colors.cta,
        tabBarInactiveTintColor: colors.textSecondary,
        headerStyle: {
          backgroundColor: colors.background,
        },
        headerTintColor: colors.textPrimary,
      }}
    >
      <Tabs.Screen
        name="carte"
        options={{
          title: t('tabs.carte'),
          headerShown: false,
          tabBarIcon: ({ focused }) => <TabIcon icon={Map} focused={focused} />,
        }}
        listeners={{
          tabPress: () => {
            useMapStore.getState().setViewMode('map');
          },
        }}
      />
      <Tabs.Screen
        name="mes-activites"
        options={{
          title: t('tabs.mesActivites'),
          tabBarIcon: ({ focused }) => <TabIcon icon={ListChecks} focused={focused} />,
        }}
      />
      <Tabs.Screen
        name="notifications"
        options={{
          title: t('tabs.notifications'),
          tabBarIcon: ({ focused }) => <NotificationTabIcon focused={focused} />,
        }}
      />
      <Tabs.Screen
        name="messagerie"
        options={{
          title: t('tabs.messagerie'),
          tabBarIcon: ({ focused }) => <MessageTabIcon focused={focused} />,
        }}
      />
      <Tabs.Screen
        name="profil"
        options={{
          title: t('tabs.profil'),
          tabBarIcon: ({ focused }) => <TabIcon icon={User} focused={focused} />,
        }}
      />
    </Tabs>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  bellContainer: {
    width: 28,
    height: 28,
    alignItems: 'center',
    justifyContent: 'center',
  },
  badge: {
    position: 'absolute',
    top: -4,
    right: -8,
    backgroundColor: colors.error,
    borderRadius: 10,
    minWidth: 16,
    height: 16,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 3,
  },
  badgeText: {
    color: colors.textPrimary,
    fontSize: fontSizes.xs - 2,
    fontWeight: 'bold',
  },
  dot: {
    position: 'absolute',
    top: -2,
    right: -4,
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: colors.error,
  },
});
