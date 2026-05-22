import { Redirect, useLocalSearchParams, useRouter } from 'expo-router';
import { useQuery } from '@tanstack/react-query';
import {
  View,
  Text,
  StyleSheet,
  ScrollView,
  Image,
  Pressable,
  Linking,
} from 'react-native';
import { useTranslation } from 'react-i18next';
import { useMemo } from 'react';
import { Pencil, MapPin, Clock, Users, Calendar, TrendingUp, Mountain } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { fontSizes, fonts, spacing, radius } from '@/constants/theme';
import { useAuth } from '@/hooks/use-auth';
import { proOfferingService } from '@/services/pro-offering-service';
import { proService } from '@/services/pro-service';
import { LogoSpinner } from '@/components/logo-spinner';
import { getSportIcon } from '@/constants/sport-icons';

// Public detail view of a pro_offering. Hero banner if image_url is
// set, otherwise a coloured placeholder with the sport icon. Below:
// title, sport, level, location, schedule, optional metrics,
// description, and a contact CTA that jumps to the pro profile (no
// in-app booking flow in v1).
export default function ProOfferingDetailScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const router = useRouter();
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { session, isAuthenticated, isLoading: authLoading, isSuspended } = useAuth();

  const { data: offering, isLoading } = useQuery({
    queryKey: ['pro-offering', id],
    queryFn: () => proOfferingService.getById(id ?? ''),
    enabled: !!id && isAuthenticated,
  });

  const { data: pro } = useQuery({
    queryKey: ['pro-profile', offering?.pro_id],
    queryFn: () => proService.getById(offering!.pro_id),
    enabled: !!offering?.pro_id,
  });

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

  const isOwner = session?.user?.id === offering.pro_id;

  const formatDuration = (d: string | null): string | null => {
    if (!d) return null;
    const match = d.match(/^(\d+):(\d+):/);
    if (!match) return d;
    const h = parseInt(match[1] ?? '0', 10);
    const m = parseInt(match[2] ?? '0', 10);
    if (h > 0 && m > 0) return `${h}h${m.toString().padStart(2, '0')}`;
    if (h > 0) return `${h}h`;
    return `${m}min`;
  };

  const formattedDuration = formatDuration(offering.duration);

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content}>
      {/* Hero — banner image OR sport-icon placeholder */}
      {offering.image_url ? (
        <Image source={{ uri: offering.image_url }} style={styles.banner} resizeMode="cover" />
      ) : (
        <View style={[styles.banner, styles.bannerPlaceholder]}>
          <Text style={styles.bannerEmoji}>{getSportIcon(offering.sport_key)}</Text>
        </View>
      )}

      {/* Header card */}
      <View style={styles.card}>
        <Text style={styles.title}>{offering.title}</Text>
        <Text style={styles.subtitle}>
          {pro?.display_name ?? offering.location_name}
        </Text>

        {isOwner && (
          <Pressable
            style={styles.editButton}
            onPress={() => router.push({ pathname: '/(auth)/pro/offering/edit', params: { id: offering.id } })}
          >
            <Pencil size={14} color={colors.cta} strokeWidth={2.5} />
            <Text style={styles.editButtonText}>{t('proOffering.edit')}</Text>
          </Pressable>
        )}
      </View>

      {/* Meta grid: location / schedule / duration / participants */}
      <View style={styles.card}>
        <Row icon={<MapPin size={16} color={colors.textSecondary} />}
             label={t('proOffering.locationName')}
             value={offering.location_name}
             styles={styles} />
        {offering.schedule_text && (
          <Row icon={<Calendar size={16} color={colors.textSecondary} />}
               label={t('proOffering.schedule')}
               value={offering.schedule_text}
               styles={styles} />
        )}
        {formattedDuration && (
          <Row icon={<Clock size={16} color={colors.textSecondary} />}
               label={t('proOffering.duration')}
               value={formattedDuration}
               styles={styles} />
        )}
        {offering.max_participants && (
          <Row icon={<Users size={16} color={colors.textSecondary} />}
               label={t('proOffering.maxParticipants')}
               value={`${offering.max_participants}`}
               styles={styles} />
        )}
        {offering.distance_km != null && (
          <Row icon={<TrendingUp size={16} color={colors.textSecondary} />}
               label={t('proOffering.distance')}
               value={`${offering.distance_km} km`}
               styles={styles} />
        )}
        {offering.elevation_gain_m != null && (
          <Row icon={<Mountain size={16} color={colors.textSecondary} />}
               label={t('proOffering.elevation')}
               value={`${offering.elevation_gain_m} m`}
               styles={styles} />
        )}
        <Row icon={<Text style={{ fontSize: 16 }}>{getSportIcon(offering.sport_key)}</Text>}
             label={t('proOffering.level')}
             value={offering.level}
             styles={styles} />
      </View>

      {/* Description */}
      {offering.description && (
        <View style={styles.card}>
          <Text style={styles.section}>{t('proOffering.description')}</Text>
          <Text style={styles.body}>{offering.description}</Text>
        </View>
      )}

      {/* Contact CTA — jump to the pro page where the contact links
          live. No in-app booking in v1. */}
      {!isOwner && (
        <Pressable
          style={styles.contactButton}
          onPress={() => router.push(`/(auth)/pro/${offering.pro_id}`)}
        >
          <Text style={styles.contactButtonText}>{t('proOffering.contactPro')}</Text>
        </Pressable>
      )}
    </ScrollView>
  );
}

function Row({
  icon,
  label,
  value,
  styles,
}: {
  icon: React.ReactNode;
  label: string;
  value: string;
  styles: ReturnType<typeof createStyles>;
}) {
  return (
    <View style={styles.row}>
      <View style={styles.rowIcon}>{icon}</View>
      <View style={{ flex: 1 }}>
        <Text style={styles.rowLabel}>{label}</Text>
        <Text style={styles.rowValue}>{value}</Text>
      </View>
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  content: { paddingBottom: spacing.xl + 32 },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: colors.background },
  notFound: { color: colors.textSecondary, fontSize: fontSizes.md },
  banner: { width: '100%', aspectRatio: 3, backgroundColor: colors.surface },
  bannerPlaceholder: { alignItems: 'center', justifyContent: 'center' },
  bannerEmoji: { fontSize: 64 },
  card: {
    marginHorizontal: spacing.md,
    marginTop: spacing.md,
    padding: spacing.md,
    borderWidth: 1,
    borderColor: colors.borderMuted,
    borderRadius: radius.md,
    backgroundColor: colors.surface,
  },
  title: { color: colors.textPrimary, fontSize: fontSizes.xl, fontFamily: fonts.title, marginBottom: 4 },
  subtitle: { color: colors.textSecondary, fontSize: fontSizes.sm },
  section: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    fontWeight: '700',
    letterSpacing: 1,
    textTransform: 'uppercase',
    marginBottom: spacing.sm,
  },
  body: { color: colors.textPrimary, fontSize: fontSizes.md, lineHeight: 22 },
  row: { flexDirection: 'row', alignItems: 'center', paddingVertical: spacing.xs },
  rowIcon: { width: 28, alignItems: 'center' },
  rowLabel: {
    color: colors.textMuted,
    fontSize: fontSizes.xs,
    textTransform: 'uppercase',
    letterSpacing: 0.8,
  },
  rowValue: { color: colors.textPrimary, fontSize: fontSizes.md, marginTop: 1 },
  editButton: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.xs,
    alignSelf: 'flex-start',
    marginTop: spacing.sm,
    paddingVertical: spacing.xs,
    paddingHorizontal: spacing.sm,
    borderWidth: 1,
    borderColor: colors.cta,
    borderRadius: radius.sm,
  },
  editButtonText: { color: colors.cta, fontSize: fontSizes.sm, fontWeight: '700' },
  contactButton: {
    marginHorizontal: spacing.md,
    marginTop: spacing.lg,
    paddingVertical: spacing.sm + 2,
    borderRadius: radius.sm,
    backgroundColor: colors.cta,
    alignItems: 'center',
  },
  contactButtonText: { color: '#FFFFFF', fontSize: fontSizes.md, fontWeight: '700' },
});
