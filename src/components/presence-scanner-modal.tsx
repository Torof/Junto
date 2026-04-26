import { useEffect, useState, useRef, useMemo } from 'react';
import { View, Text, Modal, Pressable, StyleSheet, Alert } from 'react-native';
import { CameraView, useCameraPermissions } from 'expo-camera';
import { useTranslation } from 'react-i18next';
import { useQueryClient } from '@tanstack/react-query';
import * as Burnt from 'burnt';
import { X } from 'lucide-react-native';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import { reliabilityService } from '@/services/reliability-service';
import { getFriendlyError } from '@/utils/friendly-error';
import type { AppColors } from '@/constants/colors';

interface Props {
  visible: boolean;
  onClose: () => void;
}

export function PresenceScannerModal({ visible, onClose }: Props) {
  const { t } = useTranslation();
  const colors = useColors();
  const queryClient = useQueryClient();
  const [permission, requestPermission] = useCameraPermissions();
  const [submitting, setSubmitting] = useState(false);
  const lockRef = useRef(false);
  const styles = useMemo(() => createStyles(colors), [colors]);

  useEffect(() => {
    if (visible && permission && !permission.granted) {
      requestPermission();
    }
    if (visible) lockRef.current = false;
  }, [visible, permission, requestPermission]);

  const parseToken = (raw: string): string | null => {
    const match = raw.match(/token=([a-f0-9]+)/i);
    if (match) return match[1] ?? null;
    // Fallback: if it's just the token itself
    if (/^[a-f0-9]{20,}$/i.test(raw)) return raw;
    return null;
  };

  const handleScanned = async ({ data }: { data: string }) => {
    if (lockRef.current || submitting) return;
    const token = parseToken(data);
    if (!token) return;
    lockRef.current = true;
    setSubmitting(true);
    try {
      const activityId = await reliabilityService.confirmPresenceViaToken(token);
      await queryClient.invalidateQueries({ queryKey: ['participation', activityId] });
      await queryClient.invalidateQueries({ queryKey: ['user-public-stats'] });
      await queryClient.invalidateQueries({ queryKey: ['public-profile'] });
      await queryClient.invalidateQueries({ queryKey: ['participants', activityId] });
      Burnt.toast({ title: t('presence.confirmed'), preset: 'done' });
      onClose();
    } catch (err) {
      Alert.alert(t('auth.error'), getFriendlyError(err, 'generic'));
      // allow re-scan
      setTimeout(() => { lockRef.current = false; }, 1200);
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Modal visible={visible} animationType="slide">
      <View style={styles.container}>
        <Pressable style={styles.close} onPress={onClose}>
          <X size={24} color={colors.textPrimary} strokeWidth={2.2} />
        </Pressable>
        <Text style={styles.title}>{t('presence.scanTitle')}</Text>
        <Text style={styles.subtitle}>{t('presence.scanSubtitle')}</Text>
        <View style={styles.cameraWrap}>
          {permission?.granted ? (
            <CameraView
              style={StyleSheet.absoluteFill}
              facing="back"
              barcodeScannerSettings={{ barcodeTypes: ['qr'] }}
              onBarcodeScanned={handleScanned}
            />
          ) : (
            <View style={styles.permWrap}>
              <Text style={styles.permText}>{t('presence.cameraPermission')}</Text>
              <Pressable style={styles.permButton} onPress={requestPermission}>
                <Text style={styles.permButtonText}>{t('presence.grantCamera')}</Text>
              </Pressable>
            </View>
          )}
          <View style={styles.frame} pointerEvents="none" />
        </View>
      </View>
    </Modal>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background, paddingTop: 60 },
  close: { position: 'absolute', top: 60, right: spacing.lg, padding: spacing.sm, zIndex: 10 },
  title: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: 'bold', textAlign: 'center', marginBottom: spacing.xs },
  subtitle: { color: colors.textSecondary, fontSize: fontSizes.sm, textAlign: 'center', marginBottom: spacing.lg, paddingHorizontal: spacing.lg },
  cameraWrap: { flex: 1, margin: spacing.lg, borderRadius: radius.lg, overflow: 'hidden', backgroundColor: colors.background },
  frame: {
    position: 'absolute', top: '20%', left: '15%', right: '15%', aspectRatio: 1,
    borderWidth: 3, borderColor: colors.cta, borderRadius: radius.lg,
  },
  permWrap: { ...StyleSheet.absoluteFillObject, alignItems: 'center', justifyContent: 'center', padding: spacing.lg, gap: spacing.md },
  permText: { color: colors.textPrimary, fontSize: fontSizes.md, textAlign: 'center' },
  permButton: { backgroundColor: colors.cta, paddingHorizontal: spacing.lg, paddingVertical: spacing.sm, borderRadius: radius.full },
  permButtonText: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: 'bold' },
});
