import { View, Text, StyleSheet } from 'react-native';
import { Tabs } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { useQuery } from '@tanstack/react-query';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Map, ListChecks, Bell, MessageCircle, User, type LucideIcon } from 'lucide-react-native';
import { colors, fontSizes } from '@/constants/theme';
import { notificationService } from '@/services/notification-service';
import { useMapStore } from '@/store/map-store';
import { conversationService } from '@/services/conversation-service';
import { useMessageStore } from '@/store/message-store';
import { supabase } from '@/services/supabase';

function TabIcon({ icon: IconComponent, focused }: { icon: LucideIcon; focused: boolean }) {
  return (
    <IconComponent
      size={26}
      color={focused ? colors.cta : colors.textSecondary}
      strokeWidth={focused ? 2.4 : 2}
    />
  );
}

function NotificationTabIcon({ focused }: { focused: boolean }) {
  const { data: count } = useQuery({
    queryKey: ['notifications-count'],
    queryFn: () => notificationService.getUnreadCount(),
    refetchInterval: 30000,
  });

  return (
    <View style={styles.bellContainer}>
      <Bell size={26} color={focused ? colors.cta : colors.textSecondary} strokeWidth={focused ? 2.4 : 2} />
      {(count ?? 0) > 0 && (
        <View style={styles.badge}>
          <Text style={styles.badgeText}>{count! > 99 ? '99+' : count}</Text>
        </View>
      )}
    </View>
  );
}

function MessageTabIcon({ focused }: { focused: boolean }) {
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
    (c) => isConversationUnread(c.id, c.last_message_at, c.last_message_sender_id, currentUserId)
  );

  return (
    <View style={styles.bellContainer}>
      <MessageCircle size={26} color={focused ? colors.cta : colors.textSecondary} strokeWidth={focused ? 2.4 : 2} />
      {hasUnread && <View style={styles.dot} />}
    </View>
  );
}

export default function TabsLayout() {
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
          href: null,
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

const styles = StyleSheet.create({
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
    color: '#fff',
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
