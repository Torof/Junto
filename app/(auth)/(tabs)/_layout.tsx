import { View, Text, StyleSheet } from 'react-native';
import { Tabs } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { useQuery } from '@tanstack/react-query';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { colors, fontSizes } from '@/constants/theme';
import { notificationService } from '@/services/notification-service';

function TabIcon({ icon, focused }: { icon: string; focused: boolean }) {
  return <Text style={{ fontSize: 22, opacity: focused ? 1 : 0.6 }}>{icon}</Text>;
}

function NotificationTabIcon({ focused }: { focused: boolean }) {
  const { data: count } = useQuery({
    queryKey: ['notifications-count'],
    queryFn: () => notificationService.getUnreadCount(),
    refetchInterval: 30000,
  });

  return (
    <View style={styles.bellContainer}>
      <Text style={{ fontSize: 22, opacity: focused ? 1 : 0.6 }}>🔔</Text>
      {(count ?? 0) > 0 && (
        <View style={styles.badge}>
          <Text style={styles.badgeText}>{count! > 99 ? '99+' : count}</Text>
        </View>
      )}
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
          height: 56 + insets.bottom,
          paddingBottom: insets.bottom,
          paddingTop: 4,
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
          tabBarIcon: ({ focused }) => <TabIcon icon="🌍" focused={focused} />,
        }}
      />
      <Tabs.Screen
        name="mes-activites"
        options={{
          title: t('tabs.mesActivites'),
          tabBarIcon: ({ focused }) => <TabIcon icon="📋" focused={focused} />,
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
          tabBarIcon: ({ focused }) => <TabIcon icon="💬" focused={focused} />,
        }}
      />
      <Tabs.Screen
        name="profil"
        options={{
          title: t('tabs.profil'),
          tabBarIcon: ({ focused }) => <TabIcon icon="👤" focused={focused} />,
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
});
