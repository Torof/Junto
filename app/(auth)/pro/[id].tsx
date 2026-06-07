import { Redirect, useLocalSearchParams, useRouter, useNavigation } from 'expo-router';
import { useQuery } from '@tanstack/react-query';
import { View, Text, StyleSheet } from 'react-native';
import { useTranslation } from 'react-i18next';
import { useMemo, useLayoutEffect } from 'react';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { fontSizes, spacing } from '@/constants/theme';
import { useAuth } from '@/hooks/use-auth';
import { proService } from '@/services/pro-service';
import { LogoSpinner } from '@/components/logo-spinner';
import { ProDetail } from '@/components/pro-detail';
import { PageTypeBadge } from '@/components/page-type-badge';

export default function ProPageScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
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

  // Page-type badge in the navbar — small square pin + "PRO" label,
  // matching the map's pin vocabulary so the user can see at a glance
  // what kind of page they're on.
  useLayoutEffect(() => {
    navigation.setOptions({
      headerTitle: () => <PageTypeBadge type="pro" />,
    });
  }, [navigation]);

  if (authLoading) return <View style={styles.center}><LogoSpinner size={48} /></View>;
  if (!isAuthenticated) return <Redirect href="/(visitor)/login" />;
  if (isSuspended) return <Redirect href="/(visitor)/suspended" />;
  if (isLoading) return <View style={styles.center}><LogoSpinner size={48} /></View>;

  // RLS returns null for non-pros and suspended pros — surface a clean
  // not-found state rather than a blank screen.
  if (!pro) {
    return (
      <View style={styles.center}>
        <Text style={styles.notFound}>{t('pro.notFound', { defaultValue: 'Page introuvable' })}</Text>
      </View>
    );
  }

  const isOwner = session?.user?.id === pro.user_id;

  return (
    <ProDetail
      pro={pro}
      isOwner={isOwner}
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
