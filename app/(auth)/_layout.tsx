import { Tabs } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { colors } from '@/constants/theme';

export default function AuthLayout() {
  const { t } = useTranslation();

  return (
    <Tabs
      screenOptions={{
        tabBarStyle: {
          backgroundColor: colors.background,
          borderTopColor: colors.surface,
        },
        tabBarActiveTintColor: colors.cta,
        tabBarInactiveTintColor: colors.textSecondary,
        headerStyle: {
          backgroundColor: colors.background,
        },
        headerTintColor: colors.textPrimary,
      }}
    >
      <Tabs.Screen name="carte" options={{ title: t('tabs.carte') }} />
      <Tabs.Screen name="mes-activites" options={{ title: t('tabs.mesActivites') }} />
      <Tabs.Screen name="messagerie" options={{ title: t('tabs.messagerie') }} />
      <Tabs.Screen name="profil" options={{ title: t('tabs.profil') }} />
    </Tabs>
  );
}
