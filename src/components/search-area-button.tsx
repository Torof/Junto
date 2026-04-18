import { Pressable, Text, StyleSheet } from 'react-native';
import { useTranslation } from 'react-i18next';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';

interface SearchAreaButtonProps {
  onPress: () => void;
}

export function SearchAreaButton({ onPress }: SearchAreaButtonProps) {
  const { t } = useTranslation();

  return (
    <Pressable style={styles.pill} onPress={onPress}>
      <Text style={styles.text}>{t('map.searchArea')}</Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  pill: {
    position: 'absolute',
    top: 12,
    alignSelf: 'center',
    backgroundColor: colors.cta,
    borderRadius: radius.full,
    paddingHorizontal: spacing.lg,
    paddingVertical: spacing.sm,
    zIndex: 10,
    elevation: 5,
    shadowColor: colors.background,
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.3,
    shadowRadius: 4,
  },
  text: {
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
    fontWeight: 'bold',
  },
});
