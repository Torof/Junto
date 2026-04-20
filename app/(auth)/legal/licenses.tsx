import { useMemo } from 'react';
import { ScrollView, Text, View, StyleSheet, Linking, Pressable } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTranslation } from 'react-i18next';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';

type License = {
  name: string;
  license: string;
  url: string;
};

const LICENSES: { group: string; items: License[] }[] = [
  {
    group: 'Framework',
    items: [
      { name: 'React', license: 'MIT', url: 'https://github.com/facebook/react' },
      { name: 'React Native', license: 'MIT', url: 'https://github.com/facebook/react-native' },
      { name: 'Expo', license: 'MIT', url: 'https://github.com/expo/expo' },
      { name: 'Expo Router', license: 'MIT', url: 'https://github.com/expo/expo/tree/main/packages/expo-router' },
    ],
  },
  {
    group: 'Backend',
    items: [
      { name: '@supabase/supabase-js', license: 'MIT', url: 'https://github.com/supabase/supabase-js' },
    ],
  },
  {
    group: 'Map',
    items: [
      { name: '@rnmapbox/maps', license: 'MIT', url: 'https://github.com/rnmapbox/maps' },
      { name: 'Mapbox GL', license: 'Mapbox Terms of Service', url: 'https://www.mapbox.com/legal/tos' },
      { name: 'Supercluster', license: 'ISC', url: 'https://github.com/mapbox/supercluster' },
    ],
  },
  {
    group: 'State & Data',
    items: [
      { name: '@tanstack/react-query', license: 'MIT', url: 'https://github.com/TanStack/query' },
      { name: 'Zustand', license: 'MIT', url: 'https://github.com/pmndrs/zustand' },
      { name: 'React Hook Form', license: 'MIT', url: 'https://github.com/react-hook-form/react-hook-form' },
      { name: 'Zod', license: 'MIT', url: 'https://github.com/colinhacks/zod' },
    ],
  },
  {
    group: 'UI',
    items: [
      { name: '@gorhom/bottom-sheet', license: 'MIT', url: 'https://github.com/gorhom/react-native-bottom-sheet' },
      { name: 'Lucide Icons', license: 'ISC', url: 'https://github.com/lucide-icons/lucide' },
      { name: 'Burnt (toasts)', license: 'MIT', url: 'https://github.com/nandorojo/burnt' },
      { name: 'react-native-svg', license: 'MIT', url: 'https://github.com/software-mansion/react-native-svg' },
      { name: 'react-native-gesture-handler', license: 'MIT', url: 'https://github.com/software-mansion/react-native-gesture-handler' },
      { name: 'react-native-reanimated', license: 'MIT', url: 'https://github.com/software-mansion/react-native-reanimated' },
      { name: 'react-native-safe-area-context', license: 'MIT', url: 'https://github.com/th3rdwave/react-native-safe-area-context' },
    ],
  },
  {
    group: 'Utilities',
    items: [
      { name: 'day.js', license: 'MIT', url: 'https://github.com/iamkun/dayjs' },
      { name: 'i18next', license: 'MIT', url: 'https://github.com/i18next/i18next' },
      { name: 'react-i18next', license: 'MIT', url: 'https://github.com/i18next/react-i18next' },
      { name: '@react-native-async-storage/async-storage', license: 'MIT', url: 'https://github.com/react-native-async-storage/async-storage' },
    ],
  },
  {
    group: 'Monitoring',
    items: [
      { name: '@sentry/react-native', license: 'MIT', url: 'https://github.com/getsentry/sentry-react-native' },
    ],
  },
];

export default function LicensesScreen() {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const insets = useSafeAreaInsets();

  return (
    <ScrollView style={styles.container} contentContainerStyle={[styles.content, { paddingBottom: insets.bottom + spacing.xl }]}>
      <Text style={styles.title}>{t('legal.licensesTitle')}</Text>
      <Text style={styles.intro}>
        {t('legal.licensesIntro')}
      </Text>

      {LICENSES.map((group) => (
        <View key={group.group} style={styles.group}>
          <Text style={styles.groupTitle}>{group.group}</Text>
          {group.items.map((item) => (
            <Pressable
              key={item.name}
              style={styles.row}
              onPress={() => Linking.openURL(item.url)}
            >
              <View style={{ flex: 1 }}>
                <Text style={styles.name}>{item.name}</Text>
                <Text style={styles.license}>{item.license}</Text>
              </View>
              <Text style={styles.arrow}>›</Text>
            </Pressable>
          ))}
        </View>
      ))}

      <Text style={styles.footer}>
        © Mapbox — © OpenStreetMap contributors
      </Text>
    </ScrollView>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  content: { padding: spacing.lg },
  title: { color: colors.textPrimary, fontSize: fontSizes.xl, fontWeight: 'bold', marginBottom: spacing.sm },
  intro: { color: colors.textSecondary, fontSize: fontSizes.sm, lineHeight: 20, marginBottom: spacing.xl },
  group: { marginBottom: spacing.lg },
  groupTitle: {
    color: colors.textSecondary, fontSize: fontSizes.xs, fontWeight: 'bold',
    letterSpacing: 0.8, textTransform: 'uppercase', marginBottom: spacing.sm,
  },
  row: {
    flexDirection: 'row', alignItems: 'center',
    backgroundColor: colors.surface, borderRadius: radius.md,
    padding: spacing.md, marginBottom: spacing.xs, gap: spacing.sm,
  },
  name: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '600' },
  license: { color: colors.textSecondary, fontSize: fontSizes.xs, marginTop: 2 },
  arrow: { color: colors.textSecondary, fontSize: fontSizes.lg },
  footer: {
    color: colors.textSecondary, fontSize: fontSizes.xs,
    textAlign: 'center', marginTop: spacing.xl,
  },
});
