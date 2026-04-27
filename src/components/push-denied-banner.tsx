import { useEffect, useState } from 'react';
import { View, Text, Pressable, StyleSheet, Linking, AppState } from 'react-native';
import * as Notifications from 'expo-notifications';
import { useTranslation } from 'react-i18next';
import { BellOff } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';

export function PushDeniedBanner() {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = createStyles(colors);
  const [denied, setDenied] = useState(false);

  useEffect(() => {
    let cancelled = false;
    const check = async () => {
      const { status, canAskAgain } = await Notifications.getPermissionsAsync();
      if (!cancelled) setDenied(status !== 'granted' && !canAskAgain);
    };
    check();
    const sub = AppState.addEventListener('change', (next) => {
      if (next === 'active') check();
    });
    return () => {
      cancelled = true;
      sub.remove();
    };
  }, []);

  if (!denied) return null;

  return (
    <Pressable style={styles.banner} onPress={() => Linking.openSettings()}>
      <BellOff size={18} color={colors.warning} strokeWidth={2.2} />
      <View style={styles.text}>
        <Text style={styles.title}>{t('pushDenied.title')}</Text>
        <Text style={styles.body}>{t('pushDenied.body')}</Text>
      </View>
      <Text style={styles.cta}>{t('pushDenied.cta')}</Text>
    </Pressable>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  banner: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    backgroundColor: colors.warning + '15',
    borderColor: colors.warning + '40',
    borderWidth: 1,
    borderRadius: radius.md,
    padding: spacing.sm,
    marginHorizontal: spacing.md,
    marginTop: spacing.sm,
  },
  text: { flex: 1 },
  title: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '600' },
  body: { color: colors.textSecondary, fontSize: fontSizes.xs, marginTop: 1 },
  cta: { color: colors.warning, fontSize: fontSizes.xs, fontWeight: '700' },
});
