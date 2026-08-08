import { useMemo, useRef, useState } from 'react';
import { View, Text, Pressable, StyleSheet, Share, Alert } from 'react-native';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { useQuery } from '@tanstack/react-query';
import QRCode from 'react-native-qrcode-svg';
import { CameraView, useCameraPermissions } from 'expo-camera';
import { X, Share2, ScanLine } from 'lucide-react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { supabase } from '@/services/supabase';
import { LogoSpinner } from '@/components/logo-spinner';

const WEB_HOST = process.env.EXPO_PUBLIC_JUNTO_WEB_HOST ?? 'getjunto.app';
// Only Junto contact links: getjunto.app/u/<uuid> or junto://profile/<uuid>.
const CONTACT_LINK_RE = /(?:\/u\/|profile\/)([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/i;

export default function MyContactScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const router = useRouter();
  const insets = useSafeAreaInsets();

  const [scanning, setScanning] = useState(false);
  const [permission, requestPermission] = useCameraPermissions();
  // onBarcodeScanned fires every frame — latch so one QR pushes exactly once.
  const handledRef = useRef(false);

  const { data: userId } = useQuery({
    queryKey: ['currentUser-id'],
    queryFn: async () => (await supabase.auth.getUser()).data.user?.id ?? null,
  });

  const link = userId ? `https://${WEB_HOST}/u/${userId}` : '';

  const handleShare = async () => {
    if (!link) return;
    try {
      await Share.share({ message: t('contactShare.shareMessage', { defaultValue: 'Ajoute-moi sur Junto — {{link}}', link }) });
    } catch { /* cancelled */ }
  };

  const openScanner = async () => {
    if (!permission?.granted) {
      const res = await requestPermission();
      if (!res.granted) {
        Alert.alert(t('contactShare.cameraDeniedTitle', { defaultValue: 'Caméra refusée' }), t('contactShare.cameraDeniedBody', { defaultValue: 'Autorise la caméra pour scanner un contact.' }));
        return;
      }
    }
    handledRef.current = false;
    setScanning(true);
  };

  const handleScanned = ({ data }: { data: string }) => {
    if (handledRef.current) return;
    const match = data.match(CONTACT_LINK_RE);
    if (!match) return;
    const scannedId = match[1];
    if (scannedId === userId) return; // your own code — no-op
    handledRef.current = true;
    setScanning(false);
    router.push(`/(auth)/profile/${scannedId}`);
  };

  if (scanning) {
    return (
      <View style={styles.scannerContainer}>
        <CameraView
          style={StyleSheet.absoluteFill}
          facing="back"
          barcodeScannerSettings={{ barcodeTypes: ['qr'] }}
          onBarcodeScanned={handleScanned}
        />
        <View style={[styles.scannerFrame, { top: insets.top + spacing.xl }]} pointerEvents="none">
          <View style={styles.reticle} />
          <Text style={styles.scanHint}>{t('contactShare.scanHint', { defaultValue: 'Vise le QR code de ton partenaire' })}</Text>
        </View>
        <Pressable style={[styles.scannerClose, { top: insets.top + spacing.sm }]} onPress={() => setScanning(false)} hitSlop={8}>
          <X size={26} color="#FFFFFF" strokeWidth={2.4} />
        </Pressable>
      </View>
    );
  }

  return (
    <View style={[styles.container, { paddingTop: insets.top }]}>
      <View style={styles.header}>
        <Pressable onPress={() => router.back()} hitSlop={8}><X size={24} color={colors.textPrimary} strokeWidth={2.2} /></Pressable>
        <Text style={styles.headerTitle}>{t('contactShare.title', { defaultValue: 'Mon contact' })}</Text>
        <View style={{ width: 24 }} />
      </View>

      <Text style={styles.intro}>{t('contactShare.intro', { defaultValue: 'Montre ce QR code à un partenaire, ou envoie ton lien — il pourra t\'ajouter en un geste.' })}</Text>

      <View style={styles.qrCard}>
        {userId ? (
          <QRCode value={link} size={220} backgroundColor="#FFFFFF" color="#000000" />
        ) : (
          <View style={styles.qrPlaceholder}><LogoSpinner /></View>
        )}
      </View>

      <Pressable style={styles.primaryBtn} onPress={handleShare} disabled={!link}>
        <Share2 size={18} color="#FFFFFF" strokeWidth={2.4} />
        <Text style={styles.primaryText}>{t('contactShare.shareLink', { defaultValue: 'Partager le lien' })}</Text>
      </Pressable>

      <Pressable style={styles.secondaryBtn} onPress={openScanner}>
        <ScanLine size={18} color={colors.textPrimary} strokeWidth={2.4} />
        <Text style={styles.secondaryText}>{t('contactShare.scanContact', { defaultValue: 'Scanner un contact' })}</Text>
      </Pressable>

      <View style={{ flex: 1 }} />
      <Text style={[styles.footnote, { marginBottom: insets.bottom + spacing.md }]}>
        {t('contactShare.footnote', { defaultValue: 'Une demande de contact reste toujours à accepter — tu gardes la main.' })}
      </Text>
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background, paddingHorizontal: spacing.lg },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingVertical: spacing.md },
  headerTitle: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: '800' },
  intro: { color: colors.textSecondary, fontSize: fontSizes.sm, textAlign: 'center', marginTop: spacing.sm, marginBottom: spacing.lg },
  qrCard: {
    alignSelf: 'center', backgroundColor: '#FFFFFF', padding: spacing.lg, borderRadius: radius.lg,
    borderWidth: 1, borderColor: colors.borderStrong,
  },
  qrPlaceholder: { width: 220, height: 220, alignItems: 'center', justifyContent: 'center' },
  primaryBtn: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: spacing.sm,
    backgroundColor: colors.cta, borderRadius: radius.md, paddingVertical: spacing.sm + 2, marginTop: spacing.xl,
  },
  primaryText: { color: '#FFFFFF', fontSize: fontSizes.md, fontWeight: '800' },
  secondaryBtn: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: spacing.sm,
    borderWidth: 1, borderColor: colors.borderStrong, borderRadius: radius.md, paddingVertical: spacing.sm + 2, marginTop: spacing.sm,
  },
  secondaryText: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '700' },
  footnote: { color: colors.textSecondary, fontSize: fontSizes.xs, textAlign: 'center' },
  // Scanner
  scannerContainer: { flex: 1, backgroundColor: '#000000' },
  scannerFrame: { position: 'absolute', left: 0, right: 0, alignItems: 'center' },
  reticle: { width: 240, height: 240, borderRadius: radius.lg, borderWidth: 3, borderColor: '#FFFFFF' },
  scanHint: { color: '#FFFFFF', fontSize: fontSizes.md, fontWeight: '600', marginTop: spacing.lg, textAlign: 'center', paddingHorizontal: spacing.xl },
  scannerClose: { position: 'absolute', right: spacing.lg },
});
