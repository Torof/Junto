import { Redirect, useLocalSearchParams, useNavigation, useRouter } from 'expo-router';
import { useQuery } from '@tanstack/react-query';
import { View, ScrollView, StyleSheet } from 'react-native';
import { AppText } from '@/components/app-text';
import { useTranslation } from 'react-i18next';
import { useMemo, useLayoutEffect } from 'react';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { fontSizes, spacing } from '@/constants/theme';
import { useAuth } from '@/hooks/use-auth';
import { proOfferingService } from '@/services/pro-offering-service';
import { LogoSpinner } from '@/components/logo-spinner';
import { PageTypeBadge } from '@/components/page-type-badge';
import { StatusBar } from 'expo-status-bar';
import { OfferingDetail } from '@/components/offering-detail';
import { OfferingPage } from '@/components/offering-page';
import { ReviewSection } from '@/components/review-section';
import { OfferingPhotosPage } from '@/components/offering-photos-page';

// Deep-link / catalogue page for a pro_offering (RA). Thin wrapper around the
// shared OfferingDetail so the page and the map drawer are identical.
export default function ProOfferingDetailScreen() {
  const { id, tab } = useLocalSearchParams<{ id: string; tab?: string }>();
  // No tab: the full page (own top row on the photo, no navbar, status bar
  // hidden). `?tab=reviews` / `?tab=photos` are plain pages behind it;
  // `?tab=details` keeps the old sheet.
  const old = tab === 'details';
  const reviewsPage = tab === 'reviews';
  const photosPage = tab === 'photos';
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { session, isAuthenticated, isLoading: authLoading, isSuspended } = useAuth();
  const navigation = useNavigation();
  const router = useRouter();

  const { data: offering, isLoading } = useQuery({
    queryKey: ['pro-offering', id],
    queryFn: () => proOfferingService.getById(id ?? ''),
    enabled: !!id && isAuthenticated,
  });

  useLayoutEffect(() => {
    if (!old && !reviewsPage && !photosPage) {
      navigation.setOptions({ headerShown: false });
      return;
    }
    if (!offering) return;
    if (reviewsPage || photosPage) {
      const label = reviewsPage
        ? t('proOffering.tab.reviews', { defaultValue: 'Avis' })
        : t('proOffering.tab.pictures', { defaultValue: 'Photos' });
      navigation.setOptions({ headerShown: true, headerTitle: `${label} · ${offering.title}` });
      return;
    }
    navigation.setOptions({
      headerShown: true,
      headerTitle: () => <PageTypeBadge type="offering" name={offering.title} />,
    });
  }, [navigation, offering, old, reviewsPage, photosPage, t]);

  if (authLoading) return <View style={styles.center}><LogoSpinner size={48} /></View>;
  if (!isAuthenticated) return <Redirect href="/(visitor)/login" />;
  if (isSuspended) return <Redirect href="/(visitor)/suspended" />;
  if (isLoading) return <View style={styles.center}><LogoSpinner size={48} /></View>;

  if (!offering) {
    return (
      <View style={styles.center}>
        <AppText style={styles.notFound}>{t('proOffering.notFound')}</AppText>
      </View>
    );
  }

  const isOwner = session?.user?.id === offering.pro_id;
  if (reviewsPage) {
    return (
      <ScrollView style={styles.page} contentContainerStyle={styles.pageContent} showsVerticalScrollIndicator={false}>
        <ReviewSection targetType="offering" targetId={offering.id} isOwner={isOwner} currentUserId={session?.user?.id ?? null} />
      </ScrollView>
    );
  }
  if (photosPage) {
    return <OfferingPhotosPage offering={offering} isOwner={isOwner} currentUserId={session?.user?.id ?? null} />;
  }
  if (!old) {
    return (
      <>
        <StatusBar hidden />
        <OfferingPage offering={offering} isOwner={isOwner} />
      </>
    );
  }
  return (
    <OfferingDetail
      offering={offering}
      onEdit={isOwner ? () => router.push(`/(auth)/pro/offering/edit?id=${offering.id}`) : undefined}
    />
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  center: { flex: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: colors.surfaceAlt },
  page: { flex: 1, backgroundColor: colors.background },
  pageContent: { padding: spacing.md, paddingBottom: spacing.xl + 24 },
  notFound: { color: colors.textSecondary, fontSize: fontSizes.md },
});
