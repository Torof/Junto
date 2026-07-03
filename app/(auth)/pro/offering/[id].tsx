import { Redirect, useLocalSearchParams, useNavigation } from 'expo-router';
import { useQuery } from '@tanstack/react-query';
import { View, Text, StyleSheet } from 'react-native';
import { useTranslation } from 'react-i18next';
import { useMemo, useLayoutEffect } from 'react';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { fontSizes } from '@/constants/theme';
import { useAuth } from '@/hooks/use-auth';
import { proOfferingService } from '@/services/pro-offering-service';
import { LogoSpinner } from '@/components/logo-spinner';
import { PageTypeBadge } from '@/components/page-type-badge';
import { OfferingDetail } from '@/components/offering-detail';

// Deep-link / catalogue page for a pro_offering (RA). Thin wrapper around the
// shared OfferingDetail so the page and the map drawer are identical.
export default function ProOfferingDetailScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { isAuthenticated, isLoading: authLoading, isSuspended } = useAuth();
  const navigation = useNavigation();

  const { data: offering, isLoading } = useQuery({
    queryKey: ['pro-offering', id],
    queryFn: () => proOfferingService.getById(id ?? ''),
    enabled: !!id && isAuthenticated,
  });

  useLayoutEffect(() => {
    if (!offering) return;
    navigation.setOptions({
      headerTitle: () => <PageTypeBadge type="offering" name={offering.title} />,
    });
  }, [navigation, offering]);

  if (authLoading) return <View style={styles.center}><LogoSpinner size={48} /></View>;
  if (!isAuthenticated) return <Redirect href="/(visitor)/login" />;
  if (isSuspended) return <Redirect href="/(visitor)/suspended" />;
  if (isLoading) return <View style={styles.center}><LogoSpinner size={48} /></View>;

  if (!offering) {
    return (
      <View style={styles.center}>
        <Text style={styles.notFound}>{t('proOffering.notFound')}</Text>
      </View>
    );
  }

  return <OfferingDetail offering={offering} />;
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  center: { flex: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: colors.surfaceAlt },
  notFound: { color: colors.textSecondary, fontSize: fontSizes.md },
});
