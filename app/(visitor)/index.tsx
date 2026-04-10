import { View, Text, Pressable, StyleSheet } from 'react-native';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';
import { JuntoMapView, type ActivityPin } from '@/components/map-view';
import { useInitialLocation } from '@/hooks/use-initial-location';
import { useNearbyActivities } from '@/hooks/use-nearby-activities';

export default function VisitorMapScreen() {
  const { t } = useTranslation();
  const router = useRouter();
  const { center } = useInitialLocation();
  const { data: activities } = useNearbyActivities();

  const pins: ActivityPin[] = (activities ?? [])
    .filter((a) => a.lng != null && a.lat != null)
    .map((a) => ({
      id: a.id,
      title: a.title,
      coordinate: [a.lng, a.lat] as [number, number],
    }));

  return (
    <View style={styles.container}>
      <JuntoMapView center={center} pins={pins} />

      <View style={styles.overlay}>
        <Text style={styles.title}>{t('app.name')}</Text>
        <Text style={styles.subtitle}>{t('visitor.explore')}</Text>

        <Pressable style={styles.loginButton} onPress={() => router.push('/(visitor)/login')}>
          <Text style={styles.loginText}>{t('auth.signIn')}</Text>
        </Pressable>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  overlay: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    backgroundColor: colors.background + 'E6',
    paddingHorizontal: spacing.xl,
    paddingVertical: spacing.lg,
    paddingBottom: spacing.xl + 16,
    alignItems: 'center',
  },
  title: {
    color: colors.textPrimary,
    fontSize: fontSizes.xl,
    fontWeight: 'bold',
  },
  subtitle: {
    color: colors.textSecondary,
    fontSize: fontSizes.md,
    marginTop: spacing.xs,
    marginBottom: spacing.md,
    textAlign: 'center',
  },
  loginButton: {
    backgroundColor: colors.cta,
    borderRadius: radius.md,
    paddingHorizontal: spacing.xl,
    paddingVertical: spacing.md,
  },
  loginText: {
    color: colors.textPrimary,
    fontSize: fontSizes.md,
    fontWeight: 'bold',
  },
});
