import { useMemo } from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import { useTranslation } from 'react-i18next';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';

export type OrganisationSubTab = 'transport' | 'gear';

interface Props {
  active: OrganisationSubTab;
  onChange: (tab: OrganisationSubTab) => void;
  carCount: number;
  gearMissingCount: number | null;
}

export function OrganisationSubTabs({ active, onChange, carCount, gearMissingCount }: Props) {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);

  const transportCaption = carCount === 0
    ? t('organisation.tabs.transportEmpty')
    : t('organisation.tabs.transportCount', { count: carCount });

  const gearCaption = gearMissingCount == null
    ? t('organisation.tabs.gearEmpty')
    : gearMissingCount === 0
      ? t('organisation.tabs.gearComplete')
      : t('organisation.tabs.gearMissing', { count: gearMissingCount });

  return (
    <View style={styles.container}>
      <TabButton
        label={t('organisation.tabs.transport')}
        caption={transportCaption}
        isActive={active === 'transport'}
        onPress={() => onChange('transport')}
        styles={styles}
      />
      <TabButton
        label={t('organisation.tabs.gear')}
        caption={gearCaption}
        isActive={active === 'gear'}
        onPress={() => onChange('gear')}
        styles={styles}
      />
    </View>
  );
}

interface TabButtonProps {
  label: string;
  caption: string;
  isActive: boolean;
  onPress: () => void;
  styles: ReturnType<typeof createStyles>;
}

function TabButton({ label, caption, isActive, onPress, styles }: TabButtonProps) {
  return (
    <Pressable
      accessibilityRole="tab"
      accessibilityState={{ selected: isActive }}
      onPress={onPress}
      style={[styles.tab, isActive && styles.tabActive]}
    >
      <Text style={[styles.label, isActive ? styles.labelActive : styles.labelInactive]}>
        {label}
      </Text>
      <Text style={[styles.caption, isActive ? styles.captionActive : styles.captionInactive]}>
        {caption}
      </Text>
    </Pressable>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: {
    flexDirection: 'row',
    backgroundColor: colors.surface,
    borderRadius: radius.md,
    padding: 4,
    marginBottom: spacing.md,
    gap: 4,
  },
  tab: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: spacing.sm + 2,
    paddingHorizontal: spacing.sm,
    borderRadius: radius.sm,
    gap: 2,
  },
  tabActive: {
    backgroundColor: colors.surfaceAlt,
  },
  label: {
    fontSize: fontSizes.sm,
    fontWeight: '600',
  },
  labelActive: {
    color: colors.textPrimary,
  },
  labelInactive: {
    color: colors.textSecondary,
  },
  caption: {
    fontSize: 11,
    fontWeight: '500',
  },
  captionActive: {
    color: colors.cta,
  },
  captionInactive: {
    color: colors.textSecondary,
    opacity: 0.8,
  },
});
