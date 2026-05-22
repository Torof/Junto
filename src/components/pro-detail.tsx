import { useMemo, useState } from 'react';
import { View, Text, Pressable, ScrollView, StyleSheet, Linking, Modal } from 'react-native';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTranslation } from 'react-i18next';
import { Phone, Mail, Globe, Instagram, Facebook, MapPin, Pencil, Navigation } from 'lucide-react-native';
import { fontSizes, fonts, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import type { ProProfile } from '@/services/pro-service';
import { JuntoMapView } from './map-view';

interface Props {
  pro: ProProfile;
  isOwner: boolean;
  onEdit?: () => void;
}

const COLLAPSED_DESCRIPTION_CHARS = 280;

export function ProDetail({ pro, isOwner, onEdit }: Props) {
  const { t } = useTranslation();
  const colors = useColors();
  const insets = useSafeAreaInsets();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const [descExpanded, setDescExpanded] = useState(false);
  const [activeTab, setActiveTab] = useState<'info' | 'activities' | 'reviews'>('info');
  const [showFullMap, setShowFullMap] = useState(false);

  const hasContact = Boolean(pro.phone || pro.email || pro.website || pro.instagram || pro.facebook);
  const description = pro.description ?? '';
  const descriptionOverflowing = description.length > COLLAPSED_DESCRIPTION_CHARS;
  const mapCenter: [number, number] = [pro.primary_lng, pro.primary_lat];
  const mapPins = [{ id: 'pro', coordinate: mapCenter, color: colors.cta, label: pro.primary_location_name }];

  return (
    <View style={styles.container}>
      {/* Tab bar — same idiom as activity-detail. Text-only, brutalist. */}
      <View style={styles.tabBar}>
        {(['info', 'activities', 'reviews'] as const).map((tab) => {
          const isActiveTab = activeTab === tab;
          return (
            <Pressable
              key={tab}
              style={[styles.tab, isActiveTab && styles.tabActive]}
              onPress={() => setActiveTab(tab)}
              accessibilityRole="tab"
              accessibilityState={{ selected: isActiveTab }}
              accessibilityLabel={t(`pro.tab.${tab}`, { defaultValue: tab })}
            >
              <Text style={[styles.tabText, isActiveTab && styles.tabTextActive]}>
                {t(`pro.tab.${tab}`, {
                  defaultValue: tab === 'info' ? 'Infos' : tab === 'activities' ? 'Activités' : 'Avis',
                })}
              </Text>
            </Pressable>
          );
        })}
      </View>

      {/* ===== INFO TAB ===== */}
      {activeTab === 'info' && (
        <ScrollView style={{ flex: 1 }} contentContainerStyle={styles.content}>
          {/* === HERO — full-width edge-to-edge, no horizontal margins. === */}
          <View style={[styles.heroCard, styles.heroFullBleed]}>
            <View style={styles.heroHeader}>
              <View style={{ flex: 1 }}>
                <Text style={styles.proLabel}>{t('pro.label', { defaultValue: 'PRO' })}</Text>
                <Text style={styles.heroTitle}>{pro.display_name}</Text>
              </View>
              {isOwner && onEdit && (
                <Pressable
                  onPress={onEdit}
                  hitSlop={10}
                  accessibilityLabel={t('pro.editPage', { defaultValue: 'Edit pro page' })}
                >
                  <Pencil size={18} color={colors.textSecondary} strokeWidth={2.2} />
                </Pressable>
              )}
            </View>
            {pro.tagline && <Text style={styles.tagline}>{pro.tagline}</Text>}
            <View style={styles.locationRow}>
              <MapPin size={14} color={colors.textSecondary} strokeWidth={2.4} />
              <Text style={styles.locationText} numberOfLines={2}>{pro.primary_location_name}</Text>
            </View>
          </View>

          {/* All cards below the hero get standard horizontal padding via
              the wrapper. */}
          <View style={styles.paddedSection}>
            {pro.description && (
              <View style={styles.infoCard}>
                <Text style={styles.sectionTitle}>{t('pro.about', { defaultValue: 'À propos' })}</Text>
                <Text style={styles.descriptionBody}>
                  {descExpanded || !descriptionOverflowing
                    ? description
                    : `${description.slice(0, COLLAPSED_DESCRIPTION_CHARS).trimEnd()}…`}
                </Text>
                {descriptionOverflowing && (
                  <Pressable onPress={() => setDescExpanded((v) => !v)} hitSlop={6}>
                    <Text style={styles.descriptionToggle}>
                      {descExpanded
                        ? t('pro.descSeeLess', { defaultValue: 'Voir moins' })
                        : t('pro.descSeeMore', { defaultValue: 'Voir plus' })}
                    </Text>
                  </Pressable>
                )}
              </View>
            )}

            {hasContact && (
              <View style={styles.infoCard}>
                <Text style={styles.sectionTitle}>{t('pro.contact', { defaultValue: 'Contact' })}</Text>
                {pro.phone && (
                  <ContactRow
                    icon={<Phone size={16} color={colors.cta} strokeWidth={2.4} />}
                    label={pro.phone}
                    onPress={() => Linking.openURL(`tel:${pro.phone}`)}
                    styles={styles}
                  />
                )}
                {pro.email && (
                  <ContactRow
                    icon={<Mail size={16} color={colors.cta} strokeWidth={2.4} />}
                    label={pro.email}
                    onPress={() => Linking.openURL(`mailto:${pro.email}`)}
                    styles={styles}
                  />
                )}
                {pro.website && (
                  <ContactRow
                    icon={<Globe size={16} color={colors.cta} strokeWidth={2.4} />}
                    label={pro.website.replace(/^https?:\/\//, '')}
                    onPress={() => Linking.openURL(pro.website!.startsWith('http') ? pro.website! : `https://${pro.website!}`)}
                    styles={styles}
                  />
                )}
                {pro.instagram && (
                  <ContactRow
                    icon={<Instagram size={16} color={colors.cta} strokeWidth={2.4} />}
                    label={pro.instagram}
                    onPress={() => Linking.openURL(`https://instagram.com/${pro.instagram!.replace(/^@/, '')}`)}
                    styles={styles}
                  />
                )}
                {pro.facebook && (
                  <ContactRow
                    icon={<Facebook size={16} color={colors.cta} strokeWidth={2.4} />}
                    label={pro.facebook}
                    onPress={() => Linking.openURL(pro.facebook!.startsWith('http') ? pro.facebook! : `https://facebook.com/${pro.facebook!}`)}
                    styles={styles}
                  />
                )}
              </View>
            )}

            {/* === LOCATION === Map preview, tap to open full screen +
                navigate. Same idiom as the activity info screen. */}
            <View style={styles.infoCard}>
              <Text style={styles.sectionTitle}>{t('pro.location', { defaultValue: 'Localisation' })}</Text>
              <Pressable style={styles.mapContainer} onPress={() => setShowFullMap(true)}>
                <JuntoMapView center={mapCenter} zoom={13} pins={mapPins} compassEnabled={false} />
                <View style={styles.mapTapOverlay} pointerEvents="box-only" />
                <View style={styles.mapNavHint} pointerEvents="none">
                  <Navigation size={12} color={colors.textPrimary} strokeWidth={2.4} />
                  <Text style={styles.mapNavHintText}>{t('activity.navigate', { defaultValue: 'Y aller' })}</Text>
                </View>
              </Pressable>
            </View>
          </View>
        </ScrollView>
      )}

      {/* ===== ACTIVITIES TAB ===== Phase 3 wires this. */}
      {activeTab === 'activities' && (
        <ScrollView style={{ flex: 1 }} contentContainerStyle={styles.content}>
          <View style={styles.paddedSection}>
            <View style={styles.infoCard}>
              <Text style={styles.placeholderText}>
                {t('pro.activitiesPlaceholder', { defaultValue: 'Bientôt — les activités récurrentes apparaîtront ici.' })}
              </Text>
            </View>
          </View>
        </ScrollView>
      )}

      {/* ===== REVIEWS TAB ===== Phase 4 wires this. */}
      {activeTab === 'reviews' && (
        <ScrollView style={{ flex: 1 }} contentContainerStyle={styles.content}>
          <View style={styles.paddedSection}>
            <View style={styles.infoCard}>
              <Text style={styles.placeholderText}>
                {t('pro.reviewsPlaceholder', { defaultValue: 'Bientôt — les avis des participants apparaîtront ici.' })}
              </Text>
            </View>
          </View>
        </ScrollView>
      )}

      <Modal visible={showFullMap} animationType="slide" onRequestClose={() => setShowFullMap(false)}>
        <SafeAreaView style={styles.fullMapContainer} edges={['top']}>
          <JuntoMapView center={mapCenter} zoom={14} pins={mapPins} />
          <Pressable style={styles.closeMapButton} onPress={() => setShowFullMap(false)} hitSlop={8}>
            <Text style={styles.closeMapText}>✕</Text>
          </Pressable>
          <Pressable
            style={[styles.navigateButton, { bottom: insets.bottom + 24 }]}
            onPress={() => Linking.openURL(`https://www.google.com/maps/dir/?api=1&destination=${pro.primary_lat},${pro.primary_lng}`)}
          >
            <Text style={styles.navigateText}>{t('activity.navigate', { defaultValue: 'Y aller' })}</Text>
          </Pressable>
        </SafeAreaView>
      </Modal>
    </View>
  );
}

function ContactRow({
  icon,
  label,
  onPress,
  styles,
}: {
  icon: React.ReactNode;
  label: string;
  onPress: () => void;
  styles: ReturnType<typeof createStyles>;
}) {
  return (
    <Pressable style={styles.contactRow} onPress={onPress} hitSlop={4}>
      <View style={styles.contactIcon}>{icon}</View>
      <Text style={styles.contactLabel} numberOfLines={1}>{label}</Text>
    </Pressable>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  tabBar: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.lg,
    paddingHorizontal: spacing.md,
    paddingTop: spacing.sm,
    backgroundColor: colors.background,
    borderBottomWidth: 1,
    borderBottomColor: colors.borderMuted,
  },
  tab: {
    paddingVertical: spacing.sm,
    borderBottomWidth: 2,
    borderBottomColor: 'transparent',
  },
  tabActive: { borderBottomColor: colors.borderStrong },
  tabText: { color: colors.textSecondary, fontSize: fontSizes.md, fontWeight: '500' },
  tabTextActive: { color: colors.textPrimary, fontWeight: '700' },
  content: {
    paddingBottom: spacing.xl + 32,
  },
  // Sections below the hero get their own horizontal padding so the
  // hero can be edge-to-edge.
  paddedSection: {
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.md,
  },
  infoCard: {
    backgroundColor: 'transparent',
    borderRadius: radius.lg,
    borderWidth: 1,
    borderColor: colors.borderMuted,
    padding: spacing.md,
    marginBottom: spacing.md,
  },
  heroCard: {
    backgroundColor: 'transparent',
    padding: spacing.lg,
    borderLeftWidth: 4,
    borderLeftColor: colors.cta,
    borderBottomWidth: 1,
    borderBottomColor: colors.borderMuted,
  },
  heroFullBleed: {
    // No horizontal margin — full screen width. Side and bottom borders
    // anchor it visually without a rounded card frame.
    marginHorizontal: 0,
  },
  heroHeader: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: spacing.sm,
  },
  proLabel: {
    color: colors.cta,
    fontSize: fontSizes.xs - 1,
    fontWeight: '800',
    letterSpacing: 1.5,
    marginBottom: spacing.xs - 2,
  },
  heroTitle: {
    color: colors.textPrimary,
    fontSize: fontSizes.xxl,
    fontFamily: fonts.title,
    letterSpacing: -0.5,
    lineHeight: 36,
  },
  tagline: {
    color: colors.textSecondary,
    fontSize: fontSizes.md,
    fontWeight: '500',
    marginTop: spacing.sm,
    lineHeight: 22,
  },
  locationRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    marginTop: spacing.md,
    paddingTop: spacing.sm,
    borderTopWidth: 1,
    borderTopColor: colors.borderMuted,
  },
  locationText: {
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
    fontWeight: '600',
    flex: 1,
  },
  sectionTitle: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    fontWeight: '700',
    letterSpacing: 1,
    textTransform: 'uppercase',
    marginBottom: spacing.sm,
  },
  descriptionBody: {
    color: colors.textPrimary,
    fontSize: fontSizes.md,
    lineHeight: 22,
  },
  descriptionToggle: {
    color: colors.cta,
    fontSize: fontSizes.sm,
    fontWeight: '700',
    marginTop: spacing.xs,
  },
  contactRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm + 2,
    paddingVertical: spacing.sm,
  },
  contactIcon: {
    width: 24,
    alignItems: 'center',
  },
  contactLabel: {
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
    fontWeight: '600',
    flex: 1,
  },
  placeholderText: {
    color: colors.textMuted,
    fontSize: fontSizes.sm,
    fontStyle: 'italic',
  },
  mapContainer: {
    height: 180,
    borderRadius: radius.md,
    overflow: 'hidden',
    borderWidth: 1,
    borderColor: colors.borderMuted,
  },
  mapTapOverlay: {
    position: 'absolute', top: 0, left: 0, right: 0, bottom: 0,
  },
  mapNavHint: {
    position: 'absolute', top: spacing.sm, right: spacing.sm,
    flexDirection: 'row', alignItems: 'center', gap: 4,
    backgroundColor: colors.surface,
    borderWidth: 1, borderColor: colors.borderMuted,
    borderRadius: radius.sm,
    paddingHorizontal: spacing.sm, paddingVertical: 4,
  },
  mapNavHintText: {
    color: colors.textPrimary, fontSize: fontSizes.xs, fontWeight: '700',
    textTransform: 'uppercase', letterSpacing: 0.6,
  },
  fullMapContainer: { flex: 1, backgroundColor: colors.background },
  closeMapButton: {
    position: 'absolute', top: spacing.sm + 4, left: spacing.md,
    width: 36, height: 36, borderRadius: 18,
    backgroundColor: colors.surface,
    alignItems: 'center', justifyContent: 'center',
    borderWidth: 1, borderColor: colors.borderMuted,
  },
  closeMapText: { color: colors.textPrimary, fontSize: 18, fontWeight: '700' },
  navigateButton: {
    position: 'absolute', alignSelf: 'center',
    backgroundColor: colors.cta,
    borderRadius: radius.full,
    paddingHorizontal: spacing.lg, paddingVertical: spacing.sm + 2,
    flexDirection: 'row', alignItems: 'center', gap: 6,
  },
  navigateText: {
    color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '700',
    textTransform: 'uppercase', letterSpacing: 0.6,
  },
});
