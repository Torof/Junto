import { useState, useMemo } from 'react';
import { View, Text, Pressable, StyleSheet, ScrollView, TextInput, Modal, ActivityIndicator, Alert } from 'react-native';
import { Stack, Redirect } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { Search, User, Briefcase, Ban, ShieldCheck, Mail, Clock } from 'lucide-react-native';
import dayjs from 'dayjs';
import 'dayjs/locale/fr';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { useIsAdmin } from '@/hooks/use-is-admin';
import { adminService, type AdminUserInfo, type AdminProOwner } from '@/services/admin-service';
import { getFriendlyError } from '@/utils/friendly-error';

export default function AdminLookupScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const { isAdmin, isLoading: adminLoading } = useIsAdmin();

  const [mode, setMode] = useState<'user' | 'pro'>('user');
  const [idInput, setIdInput] = useState('');
  const [loading, setLoading] = useState(false);
  const [userResult, setUserResult] = useState<AdminUserInfo | null>(null);
  const [proResult, setProResult] = useState<AdminProOwner | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [reasonFor, setReasonFor] = useState<{ kind: 'suspend' | 'unsuspend'; userId: string } | null>(null);
  const [reason, setReason] = useState('');
  const [acting, setActing] = useState(false);

  // Route guard — server re-checks anyway, this just keeps non-admins out of the UI.
  if (adminLoading) return null;
  if (!isAdmin) return <Redirect href="/(auth)/(tabs)/carte" />;

  const runUserLookup = async (id: string) => {
    setLoading(true); setError(null); setProResult(null);
    try {
      setUserResult(await adminService.resolveUser(id.trim()));
    } catch (e) {
      setUserResult(null); setError(getFriendlyError(e));
    } finally { setLoading(false); }
  };

  const handleSearch = async () => {
    const id = idInput.trim();
    if (id.length < 8) { setError(t('admin.lookupBadId', { defaultValue: 'Colle un identifiant valide.' })); return; }
    if (mode === 'user') { await runUserLookup(id); return; }
    setLoading(true); setError(null); setUserResult(null);
    try {
      setProResult(await adminService.proOwner(id));
    } catch (e) {
      setProResult(null); setError(getFriendlyError(e));
    } finally { setLoading(false); }
  };

  const submitReason = async () => {
    if (!reasonFor || reason.trim().length < 1) return;
    setActing(true);
    try {
      if (reasonFor.kind === 'suspend') await adminService.suspendUser(reasonFor.userId, reason.trim());
      else await adminService.unsuspendUser(reasonFor.userId, reason.trim());
      setReasonFor(null); setReason('');
      await runUserLookup(reasonFor.userId); // refresh status
    } catch (e) {
      Alert.alert(getFriendlyError(e));
    } finally { setActing(false); }
  };

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content} keyboardShouldPersistTaps="handled">
      <Stack.Screen options={{ headerTitle: t('admin.lookupTitle', { defaultValue: 'Recherche & modération' }) }} />

      <View style={styles.toggle}>
        <Pressable style={[styles.toggleBtn, mode === 'user' && styles.toggleActive]} onPress={() => setMode('user')}>
          <User size={16} color={mode === 'user' ? '#FFFFFF' : colors.textSecondary} strokeWidth={2.2} />
          <Text style={[styles.toggleText, mode === 'user' && styles.toggleTextActive]}>{t('admin.lookupUser', { defaultValue: 'Utilisateur' })}</Text>
        </Pressable>
        <Pressable style={[styles.toggleBtn, mode === 'pro' && styles.toggleActive]} onPress={() => setMode('pro')}>
          <Briefcase size={16} color={mode === 'pro' ? '#FFFFFF' : colors.textSecondary} strokeWidth={2.2} />
          <Text style={[styles.toggleText, mode === 'pro' && styles.toggleTextActive]}>{t('admin.lookupPro', { defaultValue: 'Page pro' })}</Text>
        </Pressable>
      </View>

      <Text style={styles.hint}>{t('admin.lookupHint', { defaultValue: "Colle l'identifiant (UUID) à résoudre." })}</Text>
      <View style={styles.searchRow}>
        <TextInput
          style={styles.input}
          value={idInput}
          onChangeText={setIdInput}
          placeholder="8e1e6a62-…"
          placeholderTextColor={colors.textMuted}
          autoCapitalize="none"
          autoCorrect={false}
        />
        <Pressable style={styles.searchBtn} onPress={handleSearch} disabled={loading}>
          <Search size={18} color="#FFFFFF" strokeWidth={2.4} />
        </Pressable>
      </View>

      {loading ? <ActivityIndicator color={colors.cta} style={{ marginTop: spacing.lg }} /> : null}
      {error ? <Text style={styles.error}>{error}</Text> : null}

      {userResult ? (
        <View style={styles.card}>
          <Text style={styles.cardName}>{userResult.display_name}{userResult.is_admin ? ' · admin' : ''}</Text>
          <View style={styles.line}><Mail size={14} color={colors.textSecondary} strokeWidth={2} /><Text style={styles.lineText} selectable>{userResult.email}</Text></View>
          <View style={styles.line}><Clock size={14} color={colors.textSecondary} strokeWidth={2} /><Text style={styles.lineText}>{t('admin.tier', { defaultValue: 'Tier' })}: {userResult.tier} · {t('admin.since', { defaultValue: 'inscrit le' })} {dayjs(userResult.created_at).locale('fr').format('D MMM YYYY')}</Text></View>
          <View style={[styles.statusPill, { backgroundColor: (userResult.suspended_at ? colors.error : colors.success) + '18' }]}>
            <Text style={[styles.statusText, { color: userResult.suspended_at ? colors.error : colors.success }]}>
              {userResult.suspended_at ? t('admin.suspended', { defaultValue: 'Suspendu' }) : t('admin.active', { defaultValue: 'Actif' })}
            </Text>
          </View>
          {!userResult.is_admin ? (
            userResult.suspended_at ? (
              <Pressable style={[styles.actionBtn, { backgroundColor: colors.success }]} onPress={() => { setReason(''); setReasonFor({ kind: 'unsuspend', userId: userResult.id }); }}>
                <ShieldCheck size={16} color="#FFFFFF" strokeWidth={2.2} />
                <Text style={styles.actionText}>{t('admin.unsuspend', { defaultValue: 'Lever la suspension' })}</Text>
              </Pressable>
            ) : (
              <Pressable style={[styles.actionBtn, { backgroundColor: colors.error }]} onPress={() => { setReason(''); setReasonFor({ kind: 'suspend', userId: userResult.id }); }}>
                <Ban size={16} color="#FFFFFF" strokeWidth={2.2} />
                <Text style={styles.actionText}>{t('admin.suspend', { defaultValue: 'Suspendre' })}</Text>
              </Pressable>
            )
          ) : (
            <Text style={styles.adminNote}>{t('admin.cantActAdmin', { defaultValue: 'Un admin ne se gère pas depuis l’app.' })}</Text>
          )}
        </View>
      ) : null}

      {proResult ? (
        <View style={styles.card}>
          <Text style={styles.cardName}>{proResult.pro_name}</Text>
          <View style={[styles.statusPill, { backgroundColor: colors.surfaceAlt }]}>
            <Text style={[styles.statusText, { color: colors.textSecondary }]}>{t('admin.proStatus', { defaultValue: 'Statut PP' })}: {proResult.status}</Text>
          </View>
          <Text style={styles.ownerLabel}>{t('admin.owner', { defaultValue: 'Propriétaire' })}</Text>
          <Text style={styles.cardName}>{proResult.owner_display_name}</Text>
          <View style={styles.line}><Mail size={14} color={colors.textSecondary} strokeWidth={2} /><Text style={styles.lineText} selectable>{proResult.owner_email}</Text></View>
          <Pressable style={[styles.actionBtn, { backgroundColor: colors.cta }]} onPress={() => { setMode('user'); setIdInput(proResult.pro_id); runUserLookup(proResult.pro_id); }}>
            <User size={16} color="#FFFFFF" strokeWidth={2.2} />
            <Text style={styles.actionText}>{t('admin.manageOwner', { defaultValue: 'Gérer ce compte' })}</Text>
          </Pressable>
        </View>
      ) : null}

      <Modal visible={reasonFor !== null} transparent animationType="fade" onRequestClose={() => setReasonFor(null)}>
        <View style={styles.overlay}>
          <View style={styles.reasonCard}>
            <Text style={styles.reasonTitle}>
              {reasonFor?.kind === 'suspend' ? t('admin.suspendReason', { defaultValue: 'Raison de la suspension' }) : t('admin.unsuspendReason', { defaultValue: 'Raison de la levée' })}
            </Text>
            <TextInput
              style={styles.reasonInput}
              value={reason}
              onChangeText={setReason}
              placeholder={t('admin.reasonPlaceholder', { defaultValue: 'Obligatoire (tracé dans le journal)' })}
              placeholderTextColor={colors.textMuted}
              maxLength={500}
              multiline
              autoFocus
            />
            <View style={styles.reasonActions}>
              <Pressable style={styles.reasonCancel} onPress={() => setReasonFor(null)}>
                <Text style={styles.reasonCancelText}>{t('common.cancel', { defaultValue: 'Annuler' })}</Text>
              </Pressable>
              <Pressable
                style={[styles.reasonConfirm, (reason.trim().length < 1 || acting) && styles.disabled]}
                disabled={reason.trim().length < 1 || acting}
                onPress={submitReason}
              >
                <Text style={styles.reasonConfirmText}>{t('common.confirm', { defaultValue: 'Confirmer' })}</Text>
              </Pressable>
            </View>
          </View>
        </View>
      </Modal>
    </ScrollView>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  content: { padding: spacing.md, gap: spacing.sm },
  toggle: { flexDirection: 'row', gap: spacing.sm },
  toggleBtn: {
    flex: 1, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 6,
    paddingVertical: spacing.sm, borderRadius: radius.md,
    borderWidth: 1, borderColor: colors.borderMuted, backgroundColor: colors.surface,
  },
  toggleActive: { backgroundColor: colors.cta, borderColor: colors.cta },
  toggleText: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: '700' },
  toggleTextActive: { color: '#FFFFFF' },
  hint: { color: colors.textSecondary, fontSize: fontSizes.sm, marginTop: spacing.xs },
  searchRow: { flexDirection: 'row', gap: spacing.sm, alignItems: 'center' },
  input: {
    flex: 1, borderWidth: 1, borderColor: colors.borderMuted, borderRadius: radius.md,
    paddingHorizontal: spacing.md, paddingVertical: spacing.sm,
    color: colors.textPrimary, fontSize: fontSizes.sm, backgroundColor: colors.surface,
  },
  searchBtn: { backgroundColor: colors.cta, borderRadius: radius.md, padding: spacing.sm + 2 },
  error: { color: colors.error, fontSize: fontSizes.sm, marginTop: spacing.sm },
  card: {
    marginTop: spacing.md, backgroundColor: colors.surface, borderRadius: radius.md,
    borderWidth: 1, borderColor: colors.borderMuted, padding: spacing.md, gap: spacing.xs,
  },
  cardName: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: '800' },
  line: { flexDirection: 'row', alignItems: 'center', gap: 6 },
  lineText: { flex: 1, color: colors.textSecondary, fontSize: fontSizes.sm },
  statusPill: { alignSelf: 'flex-start', borderRadius: radius.full, paddingHorizontal: 10, paddingVertical: 3, marginTop: 2 },
  statusText: { fontSize: fontSizes.xs, fontWeight: '800' },
  ownerLabel: { color: colors.textMuted, fontSize: fontSizes.xs, fontWeight: '700', textTransform: 'uppercase', letterSpacing: 0.5, marginTop: spacing.sm },
  actionBtn: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 8,
    borderRadius: radius.md, paddingVertical: spacing.sm + 2, marginTop: spacing.sm,
  },
  actionText: { color: '#FFFFFF', fontSize: fontSizes.sm, fontWeight: '800' },
  adminNote: { color: colors.textMuted, fontSize: fontSizes.sm, marginTop: spacing.sm, fontStyle: 'italic' },
  overlay: { flex: 1, backgroundColor: 'rgba(0,0,0,0.45)', alignItems: 'center', justifyContent: 'center', paddingHorizontal: spacing.lg },
  reasonCard: { width: '100%', backgroundColor: colors.background, borderRadius: radius.lg, padding: spacing.lg, gap: spacing.md },
  reasonTitle: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: '800' },
  reasonInput: {
    borderWidth: 1, borderColor: colors.borderMuted, borderRadius: radius.md,
    paddingHorizontal: spacing.md, paddingVertical: spacing.sm, minHeight: 70,
    color: colors.textPrimary, fontSize: fontSizes.md, backgroundColor: colors.surface, textAlignVertical: 'top',
  },
  reasonActions: { flexDirection: 'row', justifyContent: 'flex-end', gap: spacing.sm },
  reasonCancel: { paddingVertical: spacing.sm, paddingHorizontal: spacing.md },
  reasonCancelText: { color: colors.textSecondary, fontSize: fontSizes.md, fontWeight: '700' },
  reasonConfirm: { backgroundColor: colors.cta, borderRadius: radius.md, paddingVertical: spacing.sm, paddingHorizontal: spacing.lg },
  reasonConfirmText: { color: '#FFFFFF', fontSize: fontSizes.md, fontWeight: '800' },
  disabled: { opacity: 0.5 },
});
