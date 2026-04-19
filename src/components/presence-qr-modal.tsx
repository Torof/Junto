import { useEffect, useState, useMemo } from 'react';
import { View, Text, Modal, Pressable, StyleSheet, Alert } from 'react-native';
import QRCode from 'react-native-qrcode-svg';
import { useTranslation } from 'react-i18next';
import { X } from 'lucide-react-native';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import { reliabilityService } from '@/services/reliability-service';
import { getFriendlyError } from '@/utils/friendly-error';
import type { AppColors } from '@/constants/colors';

interface Props {
  visible: boolean;
  activityId: string;
  onClose: () => void;
}

export function PresenceQrModal({ visible, activityId, onClose }: Props) {
  const { t } = useTranslation();
  const colors = useColors();
  const [token, setToken] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const styles = useMemo(() => createStyles(colors), [colors]);

  useEffect(() => {
    if (!visible) {
      setToken(null);
      return;
    }
    (async () => {
      setLoading(true);
      try {
        const tok = await reliabilityService.createPresenceToken(activityId);
        setToken(tok);
      } catch (err) {
        Alert.alert(t('auth.error'), getFriendlyError(err, 'generic'));
        onClose();
      } finally {
        setLoading(false);
      }
    })();
  }, [visible, activityId]);

  return (
    <Modal visible={visible} animationType="fade" transparent>
      <View style={styles.backdrop}>
        <View style={styles.sheet}>
          <Pressable style={styles.close} onPress={onClose}>
            <X size={22} color={colors.textPrimary} strokeWidth={2.2} />
          </Pressable>
          <Text style={styles.title}>{t('presence.qrTitle')}</Text>
          <Text style={styles.subtitle}>{t('presence.qrSubtitle')}</Text>
          <View style={styles.qrWrap}>
            {token ? (
              <QRCode value={`junto://confirm-presence?token=${token}`} size={240} />
            ) : (
              <View style={styles.qrPlaceholder}>
                <Text style={styles.loadingText}>{loading ? '...' : ''}</Text>
              </View>
            )}
          </View>
          <Text style={styles.hint}>{t('presence.qrHint')}</Text>
        </View>
      </View>
    </Modal>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  backdrop: { flex: 1, backgroundColor: colors.overlay, alignItems: 'center', justifyContent: 'center', padding: spacing.lg },
  sheet: {
    width: '100%', maxWidth: 340, backgroundColor: colors.surface, borderRadius: radius.lg,
    padding: spacing.lg, alignItems: 'center',
  },
  close: { position: 'absolute', top: spacing.sm, right: spacing.sm, padding: spacing.xs, zIndex: 10 },
  title: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: 'bold', marginBottom: spacing.xs, marginTop: spacing.md, textAlign: 'center' },
  subtitle: { color: colors.textSecondary, fontSize: fontSizes.sm, textAlign: 'center', marginBottom: spacing.lg },
  qrWrap: { padding: spacing.md, backgroundColor: '#FFFFFF', borderRadius: radius.md, marginBottom: spacing.md },
  qrPlaceholder: { width: 240, height: 240, alignItems: 'center', justifyContent: 'center' },
  loadingText: { color: colors.textSecondary, fontSize: fontSizes.md },
  hint: { color: colors.textSecondary, fontSize: fontSizes.xs, textAlign: 'center' },
});
