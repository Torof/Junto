import { useState } from 'react';
import { View, Text, Modal, Pressable, StyleSheet, Linking, Platform } from 'react-native';
import * as Location from 'expo-location';
import * as SecureStore from 'expo-secure-store';
import { useTranslation } from 'react-i18next';
import { MapPinCheck } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';

const ASKED_KEY = 'junto.presence.bgAsked';

export async function shouldAskForBackgroundLocation(): Promise<boolean> {
  try {
    const asked = await SecureStore.getItemAsync(ASKED_KEY);
    if (asked) return false;
  } catch { /* fall through */ }
  const bg = await Location.getBackgroundPermissionsAsync();
  return bg.status !== 'granted' && bg.canAskAgain !== false;
}

async function markAsked() {
  try { await SecureStore.setItemAsync(ASKED_KEY, '1'); } catch { /* best effort */ }
}

interface Props {
  visible: boolean;
  onClose: () => void;
}

export function BackgroundLocationPrompt({ visible, onClose }: Props) {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = createStyles(colors);
  const [requesting, setRequesting] = useState(false);

  const handleEnable = async () => {
    setRequesting(true);
    try {
      // Foreground first — iOS won't show the "Always" prompt without it.
      const fg = await Location.getForegroundPermissionsAsync();
      if (fg.status !== 'granted') {
        const fgReq = await Location.requestForegroundPermissionsAsync();
        if (fgReq.status !== 'granted') return;
      }
      const res = await Location.requestBackgroundPermissionsAsync();
      if (res.status !== 'granted' && Platform.OS === 'ios') {
        Linking.openSettings().catch(() => {});
      }
    } finally {
      setRequesting(false);
      await markAsked();
      onClose();
    }
  };

  const handleSkip = async () => {
    await markAsked();
    onClose();
  };

  return (
    <Modal visible={visible} transparent animationType="fade" onRequestClose={handleSkip}>
      <View style={styles.backdrop}>
        <View style={styles.card}>
          <View style={styles.iconWrap}>
            <MapPinCheck size={28} color={colors.cta} strokeWidth={2.4} />
          </View>
          <Text style={styles.title}>{t('bgLocation.title')}</Text>
          <Text style={styles.body}>{t('bgLocation.body')}</Text>

          <Pressable style={[styles.primary, requesting && styles.primaryDisabled]} onPress={handleEnable} disabled={requesting}>
            <Text style={styles.primaryText}>{requesting ? '…' : t('bgLocation.enable')}</Text>
          </Pressable>
          <Pressable style={styles.secondary} onPress={handleSkip}>
            <Text style={styles.secondaryText}>{t('bgLocation.skip')}</Text>
          </Pressable>
        </View>
      </View>
    </Modal>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  backdrop: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.55)',
    alignItems: 'center',
    justifyContent: 'center',
    padding: spacing.lg,
  },
  card: {
    width: '100%',
    maxWidth: 420,
    backgroundColor: colors.surface,
    borderRadius: radius.lg,
    padding: spacing.lg,
    alignItems: 'center',
  },
  iconWrap: {
    width: 56, height: 56, borderRadius: 28,
    backgroundColor: colors.cta + '22',
    alignItems: 'center', justifyContent: 'center',
    marginBottom: spacing.md,
  },
  title: {
    color: colors.textPrimary,
    fontSize: fontSizes.lg,
    fontWeight: '800',
    textAlign: 'center',
    marginBottom: spacing.sm,
  },
  body: {
    color: colors.textSecondary,
    fontSize: fontSizes.sm,
    textAlign: 'center',
    lineHeight: 19,
    marginBottom: spacing.lg,
  },
  primary: {
    width: '100%',
    backgroundColor: colors.cta,
    borderRadius: radius.full,
    paddingVertical: spacing.sm + 2,
    alignItems: 'center',
    marginBottom: spacing.sm,
  },
  primaryDisabled: { opacity: 0.6 },
  primaryText: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '700' },
  secondary: {
    width: '100%',
    paddingVertical: spacing.sm,
    alignItems: 'center',
  },
  secondaryText: { color: colors.textSecondary, fontSize: fontSizes.sm },
});
