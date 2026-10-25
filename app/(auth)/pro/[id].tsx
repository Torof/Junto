import { Redirect, useLocalSearchParams, useRouter, useNavigation } from 'expo-router';
import { useQuery } from '@tanstack/react-query';
import { View, StyleSheet } from 'react-native';
import { AppText } from '@/components/app-text';
import { useTranslation } from 'react-i18next';
import { useMemo, useLayoutEffect } from 'react';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { fontSizes, spacing } from '@/constants/theme';
import { useAuth } from '@/hooks/use-auth';
import { proService } from '@/services/pro-service';
import { LogoSpinner } from '@/components/logo-spinner';
import { StatusBar } from 'expo-status-bar';
import { ProDetail } from '@/components/pro-detail';
import { ProPage } from '@/components/pro-page';

export default function ProPageScreen() {
  const { id, tab } = useLocalSearchParams<{ id: string; tab?: string }>();
  const router = useRouter();
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { session, isAuthenticated, isLoading: authLoading, isSuspended } = useAuth();
  const navigation = useNavigation();

  const { data: pro, isLoading } = useQuery({
    queryKey: ['pro-profile', id],
    queryFn: () => proService.getById(id ?? ''),
    enabled: !!id && isAuthenticated,
  });

  // Navbar header — small square pin + "Page pro · {display_name}".
  // Matches the map's pin vocabulary so the user knows what kind of
  // page they're on AND which specific pro it is.
  // The page itself (no tab) is full screen: its own top row sits on the
  // photo, no navbar, status bar hidden (Scott 2026-10-25). The old tabs
  // (catalogue, photos, avis) keep the navbar badge.
  const soloTab = tab === 'catalog' || tab === 'pictures' || tab === 'reviews' ? tab : undefined;
  useLayoutEffect(() => {
    if (!soloTab) {
      navigation.setOptions({ headerShown: false });
      return;
    }
    if (!pro) return;
    const label = soloTab === 'catalog'
      ? t('pro.page.outings', { defaultValue: 'Sorties encadrées' })
      : soloTab === 'reviews'
        ? t('pro.tab.reviews', { defaultValue: 'Avis' })
        : t('pro.tab.pictures', { defaultValue: 'Photos' });
    navigation.setOptions({ headerShown: true, headerTitle: `${label} · ${pro.display_name}` });
  }, [navigation, pro, soloTab, t]);

  if (authLoading) return <View style={styles.center}><LogoSpinner size={48} /></View>;
  if (!isAuthenticated) return <Redirect href="/(visitor)/login" />;
  if (isSuspended) return <Redirect href="/(visitor)/suspended" />;
  if (isLoading) return <View style={styles.center}><LogoSpinner size={48} /></View>;

  // RLS returns null for non-pros and suspended pros — surface a clean
  // not-found state rather than a blank screen.
  if (!pro) {
    return (
      <View style={styles.center}>
        <AppText style={styles.notFound}>{t('pro.notFound', { defaultValue: 'Page introuvable' })}</AppText>
      </View>
    );
  }

  const isOwner = session?.user?.id === pro.user_id;

  if (!soloTab) {
    return (
      <>
        <StatusBar hidden />
        <ProPage pro={pro} isOwner={isOwner} />
      </>
    );
  }
  return (
    <ProDetail
      pro={pro}
      isOwner={isOwner}
      soloTab={soloTab}
      onEdit={isOwner ? () => router.push('/(auth)/pro/edit') : undefined}
    />
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  center: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.background,
    paddingHorizontal: spacing.lg,
  },
  notFound: {
    color: colors.textSecondary,
    fontSize: fontSizes.md,
  },
});
