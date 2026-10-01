import { useCallback, useEffect, useRef, useState, useMemo } from 'react';
import { View, Text, Modal, Pressable, StyleSheet, Alert, AppState } from 'react-native';
import QRCode from 'react-native-qrcode-svg';
import dayjs from 'dayjs';
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

  // The token lives 30 min server-side (create_presence_token). With a single
  // fetch on open, a creator who left this sheet up showed a DEAD QR while
  // believing it worked — latecomers got "invalid or expired" and the creator
  // saw nothing wrong. Track the deadline, show it, and refetch when it lapses
  // or when the app comes back to the foreground.
  const [mintedAt, setMintedAt] = useState<number | null>(null);
  const tokenRef = useRef<string | null>(null);
  const [expired, setExpired] = useState(false);

  const fetchToken = useCallback(async () => {
    setLoading(true);
    try {
      const tok = await reliabilityService.createPresenceToken(activityId);
      // Only restart the local clock when the token ACTUALLY changed. The server
      // reuses a still-valid token, so resetting unconditionally made us claim
      // "valid for another 30 min" about a code that was about to die — the QR
      // went dead on screen while the sheet asserted it was fine (worse than the
      // original silent failure, since now we assert). Paired with mig 00436,
      // which stops handing back a token with under 5 minutes left.
      // Compared through a ref, not inside a setState updater: React may run an
      // updater twice, and it must stay free of side effects.
      if (tokenRef.current !== tok) {
        tokenRef.current = tok;
        setMintedAt(Date.now());
      }
      setToken(tok);
      setExpired(false);
    } catch (err) {
      Alert.alert(t('auth.error'), getFriendlyError(err, 'generic'));
      onClose();
    } finally {
      setLoading(false);
    }
  }, [activityId, onClose, t]);

  useEffect(() => {
    if (!visible) {
      setToken(null);
      tokenRef.current = null;
      setMintedAt(null);
      setExpired(false);
      return;
    }
    void fetchToken();
  }, [visible, fetchToken]);

  // The server may hand back an existing token with less than 30 min left, so
  // treat 25 min as the refresh point and re-mint rather than trusting the age.
  useEffect(() => {
    if (!visible || mintedAt == null) return;
    const id = setInterval(() => {
      if (Date.now() - mintedAt > 25 * 60 * 1000) {
        // Renew silently — the creator is holding the phone up, not reading
        // warnings. `expired` only shows if the refetch hasn't landed yet.
        setExpired(true);
        void fetchToken();
      }
    }, 30 * 1000);
    return () => clearInterval(id);
  }, [visible, mintedAt, fetchToken]);

  useEffect(() => {
    if (!visible) return;
    const sub = AppState.addEventListener('change', (s) => {
      if (s === 'active' && mintedAt != null && Date.now() - mintedAt > 25 * 60 * 1000) {
        void fetchToken();
      }
    });
    return () => sub.remove();
  }, [visible, mintedAt, fetchToken]);

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
          <Text style={styles.hint}>
            {expired
              ? t('presence.qrExpired')
              : mintedAt != null
                ? t('presence.qrExpiresAt', { time: dayjs(mintedAt + 30 * 60 * 1000).format('HH:mm') })
                : t('presence.qrHint')}
          </Text>
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
