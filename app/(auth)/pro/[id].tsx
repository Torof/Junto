import { Redirect, useLocalSearchParams, useRouter, useNavigation } from 'expo-router';
import { useQuery } from '@tanstack/react-query';
import { View, Text, Image, Pressable, StyleSheet } from 'react-native';
import { useTranslation } from 'react-i18next';
import { useMemo, useLayoutEffect } from 'react';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { useAuth } from '@/hooks/use-auth';
import { proService } from '@/services/pro-service';
import { LogoSpinner } from '@/components/logo-spinner';
import { ProDetail } from '@/components/pro-detail';

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

  // Fill the navbar with the pro's identity instead of an empty title.
  // Avatar uses pin_image_url first (the square photo the pro picked
  // for the map pin), falling back to a CTA-colored letter chip.
  const headerLabel = pro?.display_name ?? '';
  const headerThumb = pro?.pin_image_url ?? null;
  const headerInitial = (pro?.display_name?.trim().charAt(0) ?? '?').toUpperCase();
  useLayoutEffect(() => {
    if (!pro) return;
    navigation.setOptions({
      headerTitle: () => (
        <View style={styles.headerRow}>
          {headerThumb ? (
            <Image source={{ uri: headerThumb }} style={styles.headerThumb} />
          ) : (
            <View style={[styles.headerThumb, styles.headerThumbPlaceholder]}>
              <Text style={styles.headerThumbInitial}>{headerInitial}</Text>
            </View>
          )}
          <Text style={styles.headerName} numberOfLines={1}>{headerLabel}</Text>
        </View>
      ),
    });
  }, [navigation, pro, headerLabel, headerThumb, headerInitial, styles]);

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
  headerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.xs + 2,
    maxWidth: 220,
  },
  headerThumb: {
    width: 26,
    height: 26,
    borderRadius: radius.sm,
    backgroundColor: colors.surface,
  },
  headerThumbPlaceholder: {
    backgroundColor: colors.cta,
    alignItems: 'center',
    justifyContent: 'center',
  },
  headerThumbInitial: {
    color: '#FFFFFF',
    fontSize: fontSizes.sm,
    fontWeight: '800',
  },
  headerName: {
    color: colors.textPrimary,
    fontSize: fontSizes.md,
    fontWeight: '700',
    flexShrink: 1,
  },
});
