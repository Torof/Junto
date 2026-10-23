import { useEffect, useMemo, useRef, useState } from 'react';
import { View, Pressable, StyleSheet, Share, Alert } from 'react-native';
import { AppText } from '@/components/app-text';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import * as Burnt from 'burnt';
import QRCode from 'react-native-qrcode-svg';
import { CameraView, useCameraPermissions } from 'expo-camera';
import { X, Share2, ScanLine } from 'lucide-react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { supabase } from '@/services/supabase';
import { contactService } from '@/services/contact-service';
import { LogoSpinner } from '@/components/logo-spinner';

const WEB_HOST = process.env.EXPO_PUBLIC_JUNTO_WEB_HOST ?? 'getjunto.app';
// Only Junto contact links: getjunto.app/u/<uuid> or junto://profile/<uuid>,
// optionally followed by #t=<token> — the QR's short-lived token (mig 00456)
// that turns a scan into an instant connection. A shared link never has one.
// The token rides in the URL fragment (never sent to the web server if the
// code is opened in a browser); `?t=` is still read for older QR codes.
const CONTACT_LINK_RE = /(?:\/u\/|profile\/)([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})(?:[?#]t=([0-9a-f]{64}))?/i;
// The server token lives 2 minutes (mig 00469); refresh every minute.
const TOKEN_REFRESH_MS = 60_000;

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

  const queryClient = useQueryClient();
  const { data: userId } = useQuery({
    queryKey: ['currentUser-id'],
    queryFn: async () => (await supabase.auth.getUser()).data.user?.id ?? null,
  });
  // Rotating token for the QR only. Not cached across openings; refreshed
  // while the screen is up. On failure the QR falls back to the bare link
  // (profile → request), never blank.
  const { data: qrToken, dataUpdatedAt } = useQuery({
    queryKey: ['contact-qr-token'],
    queryFn: () => contactService.createQrToken(),
    enabled: !!userId,
    gcTime: 0,
    staleTime: TOKEN_REFRESH_MS,
    refetchInterval: TOKEN_REFRESH_MS,
    retry: false,
  });

  // Leaving the screen kills the token it was showing: a screenshot relayed
  // elsewhere is dead before anyone can scan it (audit 2026-10, M2). Only that
  // token — a quick reopen's fresher one survives a late revoke.
  const shownTokenRef = useRef<string | null>(null);
  useEffect(() => { shownTokenRef.current = qrToken ?? null; }, [qrToken]);
  useEffect(() => () => {
    const tok = shownTokenRef.current;
    if (tok) void contactService.revokeQrTokens(tok).catch(() => {});
  }, []);

  // A failed refresh (no network, quota) would leave a dead token on screen:
  // past 110 s the QR falls back to the plain link (request flow).
  const [now, setNow] = useState(Date.now());
  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), 10_000);
    return () => clearInterval(id);
  }, []);
  const tokenFresh = !!qrToken && now - dataUpdatedAt < 110_000;

  const link = userId ? `https://${WEB_HOST}/u/${userId}` : '';
  const qrValue = link && tokenFresh ? `${link}#t=${qrToken}` : link;

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
    const token = match[2];
    if (!scannedId || scannedId === userId) return; // your own code — no-op
    handledRef.current = true;
    setScanning(false);
    if (!token) {
      router.push(`/(auth)/profile/${scannedId}`);
      return;
    }
    // A live QR: connect on the spot. An expired or unknown token falls back
    // to the profile, where the request flow still works.
    void contactService.connectViaQrToken(token, scannedId)
      .then(async (conversationId) => {
        if (!conversationId) {
          router.push(`/(auth)/profile/${scannedId}`);
          return;
        }
        await queryClient.invalidateQueries({ queryKey: ['conversations'] });
        Burnt.toast({ title: t('contactShare.connected', { defaultValue: 'Vous êtes connectés' }), preset: 'done' });
        router.replace(`/(auth)/conversation/${conversationId}`);
      })
      .catch(() => {
        router.push(`/(auth)/profile/${scannedId}`);
      });
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
          <AppText style={styles.scanHint}>{t('contactShare.scanHint', { defaultValue: 'Vise le QR code de ton partenaire' })}</AppText>
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
        <AppText style={styles.headerTitle}>{t('contactShare.title', { defaultValue: 'Mon QR Junto' })}</AppText>
        <View style={{ width: 24 }} />
      </View>

      <AppText style={styles.intro}>{t('contactShare.intro', { defaultValue: 'Fais scanner ce QR par un partenaire : vous êtes connectés aussitôt.' })}</AppText>

      <View style={styles.qrCard}>
        {userId ? (
          <QRCode value={qrValue} size={220} backgroundColor="#FFFFFF" color="#000000" />
        ) : (
          <View style={styles.qrPlaceholder}><LogoSpinner /></View>
        )}
      </View>

      <Pressable style={styles.primaryBtn} onPress={handleShare} disabled={!link}>
        <Share2 size={18} color="#FFFFFF" strokeWidth={2.4} />
        <AppText style={styles.primaryText}>{t('contactShare.shareLink', { defaultValue: 'Partager le lien' })}</AppText>
      </Pressable>

      <Pressable style={styles.secondaryBtn} onPress={openScanner}>
        <ScanLine size={18} color={colors.textPrimary} strokeWidth={2.4} />
        <AppText style={styles.secondaryText}>{t('contactShare.scanContact', { defaultValue: 'Scanner un QR' })}</AppText>
      </Pressable>

      <View style={{ flex: 1 }} />
      <AppText style={[styles.footnote, { marginBottom: insets.bottom + spacing.md }]}>
        {t('contactShare.footnote', { defaultValue: 'Le QR change toutes les 10 minutes. Un lien envoyé reste une demande à accepter.' })}
      </AppText>
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
