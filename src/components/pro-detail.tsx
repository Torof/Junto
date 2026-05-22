import { useMemo, useState } from 'react';
import { View, Text, Pressable, ScrollView, StyleSheet, Linking } from 'react-native';
import { useTranslation } from 'react-i18next';
import { Phone, Mail, Globe, Instagram, Facebook, MapPin, Pencil } from 'lucide-react-native';
import { fontSizes, fonts, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import type { ProProfile } from '@/services/pro-service';

interface Props {
  pro: ProProfile;
  isOwner: boolean;
  onEdit?: () => void;
}

const COLLAPSED_DESCRIPTION_CHARS = 280;

export function ProDetail({ pro, isOwner, onEdit }: Props) {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const [descExpanded, setDescExpanded] = useState(false);

  const hasContact = Boolean(pro.phone || pro.email || pro.website || pro.instagram || pro.facebook);
  const description = pro.description ?? '';
  const descriptionOverflowing = description.length > COLLAPSED_DESCRIPTION_CHARS;

  return (
    <ScrollView style={{ flex: 1 }} contentContainerStyle={styles.content}>
      {/* === HERO CARD === Pro name + tagline + location anchor */}
      <View style={[styles.infoCard, styles.heroCard]}>
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

      {/* === ABOUT === */}
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

      {/* === CONTACT === */}
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

      {/* === ACTIVITIES placeholder === wired in Phase 3 */}
      <View style={styles.infoCard}>
        <Text style={styles.sectionTitle}>{t('pro.activities', { defaultValue: 'Activités' })}</Text>
        <Text style={styles.placeholderText}>
          {t('pro.activitiesPlaceholder', { defaultValue: 'Bientôt — les activités récurrentes apparaîtront ici.' })}
        </Text>
      </View>

      {/* === REVIEWS placeholder === wired in Phase 4 */}
      <View style={styles.infoCard}>
        <Text style={styles.sectionTitle}>{t('pro.reviews', { defaultValue: 'Avis' })}</Text>
        <Text style={styles.placeholderText}>
          {t('pro.reviewsPlaceholder', { defaultValue: 'Bientôt — les avis des participants apparaîtront ici.' })}
        </Text>
      </View>
    </ScrollView>
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
  content: {
    padding: spacing.lg,
    paddingBottom: spacing.xl + 32,
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
    borderLeftWidth: 4,
    borderLeftColor: colors.cta,
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
});
