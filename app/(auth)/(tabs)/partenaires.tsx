import { useMemo, useState } from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import { useLocalSearchParams } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { Compass, Hash } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { DiscoveryView } from '@/components/discovery-view';
import { ChannelsView } from '@/components/channels-view';

// Partenaires hub (navbar refonte 2026-08-12): the "find + talk to partners"
// family — Découverte (dispos) + Canaux (channels) as two sub-tabs.
type Sub = 'discovery' | 'channels';

export default function PartenairesScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const { tab } = useLocalSearchParams<{ tab?: string }>();
  const [sub, setSub] = useState<Sub>(tab === 'channels' ? 'channels' : 'discovery');

  return (
    <View style={styles.container}>
      <View style={styles.segments}>
        <Pressable style={[styles.segment, sub === 'discovery' && styles.segmentActive]} onPress={() => setSub('discovery')}>
          <Compass size={16} color={sub === 'discovery' ? '#FFFFFF' : colors.textPrimary} strokeWidth={2.2} />
          <Text style={[styles.segmentText, sub === 'discovery' && styles.segmentTextActive]}>
            {t('partenaires.discovery', { defaultValue: 'Découverte' })}
          </Text>
        </Pressable>
        <Pressable style={[styles.segment, sub === 'channels' && styles.segmentActive]} onPress={() => setSub('channels')}>
          <Hash size={16} color={sub === 'channels' ? '#FFFFFF' : colors.textPrimary} strokeWidth={2.2} />
          <Text style={[styles.segmentText, sub === 'channels' && styles.segmentTextActive]}>
            {t('partenaires.channels', { defaultValue: 'Canaux' })}
          </Text>
        </Pressable>
      </View>
      <View style={styles.body}>
        {sub === 'discovery' ? <DiscoveryView /> : <ChannelsView />}
      </View>
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  segments: {
    flexDirection: 'row',
    gap: spacing.sm,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
    borderBottomWidth: 1,
    borderBottomColor: colors.borderMuted,
  },
  segment: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: spacing.xs,
    paddingVertical: spacing.sm,
    borderRadius: radius.full,
    borderWidth: 1,
    borderColor: colors.borderMuted,
  },
  segmentActive: { backgroundColor: colors.cta, borderColor: colors.cta },
  segmentText: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '700' },
  segmentTextActive: { color: '#FFFFFF' },
  body: { flex: 1 },
});
