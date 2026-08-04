import { useEffect, useMemo, useState } from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { Tabs } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Map, CalendarDays, Bell, MessageSquare, Menu, type LucideIcon } from 'lucide-react-native';
import { MenuSheet } from '@/components/menu-sheet';
import { useColors } from '@/hooks/use-theme';
import { fontSizes } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { notificationService } from '@/services/notification-service';
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

// Notifications is Junto's action center (requests, presence, transport) —
// Scott's call (2026-07-06): it stays a first-class tab, bell + count badge
// (the old wiggle animation intentionally not restored — calmer bar).
function NotificationTabIcon({ focused }: { focused: boolean }) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);

  const { data: count } = useQuery({
    queryKey: ['notifications-count'],
    queryFn: () => notificationService.getUnreadCount(),
    refetchInterval: 30000,
  });

  const hasUnread = (count ?? 0) > 0;

  return (
    <View style={styles.bellContainer}>
      <Bell
        size={26}
        color={focused ? colors.cta : hasUnread ? colors.cta : colors.textSecondary}
        strokeWidth={focused ? 2.4 : 2}
      />
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
  const queryClient = useQueryClient();

  // Needed to scope the realtime subscriptions below to this user.
  const { data: currentUserId } = useQuery({
    queryKey: ['currentUser-id'],
    queryFn: async () => (await supabase.auth.getUser()).data.user?.id,
  });

  // Realtime invalidation for the persistent tab-bar badges. Mounted at
  // the layout level (not inside the animated tab-icon components) so it
  // doesn't race with their wiggle Animated.sequence — that race was the
  // root of the launch-time crash on the original slice 2.
  //
  // Both subscriptions are filtered per-user so the realtime server only
  // forwards events that match this user. Without the filter, every event
  // on these tables would be broadcast to every subscriber — RLS gates
  // realtime.messages access but doesn't suppress the broadcast itself,
  // leaking event-timing metadata. AUDIT_SECURITY_2 M1.
  // Migration 00184 ensures both tables are in supabase_realtime.
  useEffect(() => {
    if (!currentUserId) return;
    const channel = supabase
      .channel(`tabs-badges:${currentUserId}`)
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'notifications',
          filter: `user_id=eq.${currentUserId}`,
        },
        () => {
          queryClient.invalidateQueries({ queryKey: ['notifications'] });
          queryClient.invalidateQueries({ queryKey: ['notifications-count'] });
        },
      )
      .subscribe();
    // Unified store (00359): incoming-message liveness is an 'inbox' broadcast
    // on my personal topic (RLS: strictly self). Single subscriber app-wide —
    // the messagerie screen relies on these invalidations.
    const inboxChannel = supabase
      .channel(`user:${currentUserId}`, { config: { private: true } })
      .on('broadcast', { event: 'inbox' }, () => {
        queryClient.invalidateQueries({ queryKey: ['conversations'] });
        queryClient.invalidateQueries({ queryKey: ['conversations-badge'] });
      })
      .subscribe();
    return () => {
      supabase.removeChannel(channel);
      supabase.removeChannel(inboxChannel);
    };
  }, [queryClient, currentUserId]);

  const [menuOpen, setMenuOpen] = useState(false);

  return (
    <>
    <Tabs
      screenListeners={{
        // An open MenuSheet must not survive a tab switch — pressing any
        // OTHER tab closes it (the menu tab's own press re-opens it).
        tabPress: (e) => {
          if (!String(e.target ?? '').startsWith('menu')) setMenuOpen(false);
        },
      }}
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
      />
      <Tabs.Screen
        name="mes-activites"
        options={{
          title: t('tabs.mesActivites'),
          tabBarIcon: ({ focused }) => <TabIcon icon={CalendarDays} focused={focused} />,
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
      {/* Menu tab — press intercepted: opens the MenuSheet instead of
          navigating (the menu.tsx screen is a null stub). */}
      <Tabs.Screen
        name="menu"
        options={{
          title: t('tabs.menu', { defaultValue: 'Menu' }),
          tabBarIcon: () => <TabIcon icon={Menu} focused={menuOpen} />,
        }}
        listeners={{
          tabPress: (e) => {
            e.preventDefault();
            setMenuOpen(true);
          },
        }}
      />
      {/* Absorbed into the menu sheet — hidden from the bar, route alive. */}
      <Tabs.Screen
        name="profil"
        options={{ title: t('tabs.profil'), href: null }}
      />
    </Tabs>

    <MenuSheet open={menuOpen} onClose={() => setMenuOpen(false)} />
    </>
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
