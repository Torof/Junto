import { useState, useMemo } from 'react';
import { View, Text, Pressable, FlatList, TextInput, Modal, StyleSheet, Alert } from 'react-native';
import { useTranslation } from 'react-i18next';
import { useLocalSearchParams } from 'expo-router';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import dayjs from 'dayjs';
import relativeTime from 'dayjs/plugin/relativeTime';
import 'dayjs/locale/fr';
import * as Burnt from 'burnt';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { reportService, type Report } from '@/services/report-service';
import { proService, type PendingProApplication } from '@/services/pro-service';
import { Check, X, BadgeCheck, Trash2 } from 'lucide-react-native';
import { Redirect } from 'expo-router';
import { useIsAdmin } from '@/hooks/use-is-admin';
import { adminService } from '@/services/admin-service';
import { getFriendlyError } from '@/utils/friendly-error';

// Content types the admin can take down from a report (never DMs or users).
const REMOVABLE_TYPES = ['activity', 'wall_message', 'pro_review', 'offering_review'];

dayjs.extend(relativeTime);

type FilterTab = 'pending' | 'resolved' | 'pros';

export default function ModerationScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t, i18n } = useTranslation();
  const queryClient = useQueryClient();
  const { tab: tabParam } = useLocalSearchParams<{ tab?: string }>();
  const { isAdmin, isLoading: adminLoading } = useIsAdmin();
  const [tab, setTab] = useState<FilterTab>(tabParam === 'pros' ? 'pros' : 'pending');
  const [selectedReport, setSelectedReport] = useState<Report | null>(null);
  const [adminNote, setAdminNote] = useState('');
  const [isProcessing, setIsProcessing] = useState(false);

  const { data: reports, isLoading } = useQuery({
    queryKey: ['admin-reports'],
    queryFn: () => reportService.getAll(),
  });

  const { data: pendingPros, isLoading: prosLoading } = useQuery({
    queryKey: ['admin-pending-pros'],
    queryFn: () => proService.getPendingApplications(),
  });

  const [proBusyId, setProBusyId] = useState<string | null>(null);
  const [rejectApp, setRejectApp] = useState<PendingProApplication | null>(null);
  const [rejectReason, setRejectReason] = useState('');

  const handleApprovePro = (app: PendingProApplication) => {
    Alert.alert(t('admin.proApproveTitle', { defaultValue: 'Valider cette page pro ?' }), app.company_name ?? app.display_name, [
      { text: t('activity.no'), style: 'cancel' },
      {
        text: t('admin.proApprove', { defaultValue: 'Valider' }),
        onPress: async () => {
          setProBusyId(app.user_id);
          try {
            await proService.approve(app.user_id);
            await queryClient.invalidateQueries({ queryKey: ['admin-pending-pros'] });
            Burnt.toast({ title: t('admin.proApproved', { defaultValue: 'Page pro validée' }), preset: 'done' });
          } catch {
            Alert.alert(t('auth.error'), t('auth.unknownError'));
          } finally {
            setProBusyId(null);
          }
        },
      },
    ]);
  };

  const handleRejectPro = (app: PendingProApplication) => {
    setRejectReason('');
    setRejectApp(app);
  };

  const confirmRejectPro = async () => {
    if (!rejectApp) return;
    setProBusyId(rejectApp.user_id);
    try {
      await proService.reject(rejectApp.user_id, rejectReason.trim() || undefined);
      await queryClient.invalidateQueries({ queryKey: ['admin-pending-pros'] });
      setRejectApp(null);
      Burnt.toast({ title: t('admin.proRejected', { defaultValue: 'Demande refusée' }) });
    } catch {
      Alert.alert(t('auth.error'), t('auth.unknownError'));
    } finally {
      setProBusyId(null);
    }
  };

  const filtered = (reports ?? []).filter((r) =>
    tab === 'pending' ? r.status === 'pending' : r.status !== 'pending'
  );

  const handleAction = async (action: 'dismissed' | 'actioned', suspendUserId?: string) => {
    if (!selectedReport) return;
    setIsProcessing(true);
    try {
      await reportService.moderate(selectedReport.id, action, adminNote || undefined, suspendUserId);
      await queryClient.invalidateQueries({ queryKey: ['admin-reports'] });
      setSelectedReport(null);
      setAdminNote('');
      Burnt.toast({ title: action === 'dismissed' ? t('admin.dismissed') : t('admin.actioned'), preset: 'done' });
    } catch {
      Alert.alert(t('auth.error'), t('auth.unknownError'));
    } finally {
      setIsProcessing(false);
    }
  };

  // Take down the reported content (reason = the admin note) and resolve the
  // report as actioned. Only for removable content types.
  const handleRemoveContent = async () => {
    if (!selectedReport) return;
    if (adminNote.trim().length < 1) {
      Alert.alert(t('admin.removeNeedsReason', { defaultValue: 'Ajoute une note (raison) pour retirer le contenu.' }));
      return;
    }
    setIsProcessing(true);
    try {
      await adminService.removeContent(selectedReport.target_type, selectedReport.target_id, adminNote.trim());
      await reportService.moderate(selectedReport.id, 'actioned', adminNote || undefined);
      await queryClient.invalidateQueries({ queryKey: ['admin-reports'] });
      setSelectedReport(null);
      setAdminNote('');
      Burnt.toast({ title: t('admin.contentRemoved', { defaultValue: 'Contenu retiré' }), preset: 'done' });
    } catch (e) {
      Alert.alert(getFriendlyError(e));
    } finally {
      setIsProcessing(false);
    }
  };

  const getTargetLabel = (report: Report) => {
    const typeLabels: Record<string, string> = {
      user: t('admin.targetUser'),
      activity: t('admin.targetActivity'),
      wall_message: t('admin.targetWallMessage'),
      private_message: t('admin.targetPrivateMessage'),
    };
    return typeLabels[report.target_type] ?? report.target_type;
  };

  if (adminLoading) return null;
  if (!isAdmin) return <Redirect href="/(auth)/(tabs)/carte" />;

  return (
    <View style={styles.container}>
      {/* Tabs */}
      <View style={styles.tabs}>
        <Pressable style={[styles.tab, tab === 'pending' && styles.tabActive]} onPress={() => setTab('pending')}>
          <Text style={[styles.tabText, tab === 'pending' && styles.tabTextActive]}>
            {t('admin.pending')} ({(reports ?? []).filter((r) => r.status === 'pending').length})
          </Text>
        </Pressable>
        <Pressable style={[styles.tab, tab === 'resolved' && styles.tabActive]} onPress={() => setTab('resolved')}>
          <Text style={[styles.tabText, tab === 'resolved' && styles.tabTextActive]}>
            {t('admin.resolved')}
          </Text>
        </Pressable>
        <Pressable style={[styles.tab, tab === 'pros' && styles.tabActive]} onPress={() => setTab('pros')}>
          <Text style={[styles.tabText, tab === 'pros' && styles.tabTextActive]}>
            {t('admin.prosTab', { defaultValue: 'Pros' })} ({(pendingPros ?? []).length})
          </Text>
        </Pressable>
      </View>

      {/* List */}
      {tab === 'pros' ? (
        prosLoading ? (
          <View style={styles.center}><Text style={styles.loadingText}>...</Text></View>
        ) : (pendingPros ?? []).length === 0 ? (
          <View style={styles.center}><Text style={styles.emptyText}>{t('admin.noPendingPros', { defaultValue: 'Aucune demande en attente' })}</Text></View>
        ) : (
          <FlatList
            data={pendingPros}
            keyExtractor={(item) => item.user_id}
            renderItem={({ item }) => (
              <View style={styles.card}>
                <View style={styles.cardHeader}>
                  <View style={styles.proTitleRow}>
                    <BadgeCheck size={16} color={colors.cta} strokeWidth={2.4} />
                    <Text style={styles.targetType} numberOfLines={1}>{item.company_name ?? item.display_name}</Text>
                  </View>
                  <Text style={styles.time}>{dayjs(item.created_at).locale(i18n.language).fromNow()}</Text>
                </View>
                <Text style={styles.proLine}>Page : {item.display_name}</Text>
                {item.real_name && <Text style={styles.proLine}>Responsable : {item.real_name}</Text>}
                <Text style={styles.proLineMuted}>{item.primary_location_name}</Text>
                {(item.email || item.phone || item.website) && (
                  <Text style={styles.proLineMuted} numberOfLines={1}>{[item.email, item.phone, item.website].filter(Boolean).join(' · ')}</Text>
                )}
                <View style={styles.actionRow}>
                  <Pressable style={[styles.dismissButton, proBusyId === item.user_id && styles.disabled]} onPress={() => handleRejectPro(item)} disabled={proBusyId === item.user_id}>
                    <X size={15} color={colors.error} strokeWidth={2.6} />
                    <Text style={styles.dismissText}>{t('admin.proReject', { defaultValue: 'Refuser' })}</Text>
                  </Pressable>
                  <Pressable style={[styles.approveButton, proBusyId === item.user_id && styles.disabled]} onPress={() => handleApprovePro(item)} disabled={proBusyId === item.user_id}>
                    <Check size={15} color="#FFFFFF" strokeWidth={2.6} />
                    <Text style={styles.approveText}>{t('admin.proApprove', { defaultValue: 'Valider' })}</Text>
                  </Pressable>
                </View>
              </View>
            )}
            contentContainerStyle={styles.list}
          />
        )
      ) : isLoading ? (
        <View style={styles.center}>
          <Text style={styles.loadingText}>...</Text>
        </View>
      ) : filtered.length === 0 ? (
        <View style={styles.center}>
          <Text style={styles.emptyText}>{t('admin.noReports')}</Text>
        </View>
      ) : (
        <FlatList
          data={filtered}
          keyExtractor={(item) => item.id}
          renderItem={({ item }) => (
            <Pressable style={styles.card} onPress={() => { setSelectedReport(item); setAdminNote(''); }}>
              <View style={styles.cardHeader}>
                <Text style={styles.targetType}>{getTargetLabel(item)}</Text>
                <Text style={styles.time}>{dayjs(item.created_at).locale(i18n.language).fromNow()}</Text>
              </View>
              <Text style={styles.reason} numberOfLines={2}>{item.reason}</Text>
              {item.status !== 'pending' && (
                <View style={[styles.statusBadge, item.status === 'dismissed' ? styles.dismissedBadge : styles.actionedBadge]}>
                  <Text style={styles.statusText}>{item.status === 'dismissed' ? t('admin.dismissed') : t('admin.actioned')}</Text>
                </View>
              )}
            </Pressable>
          )}
          contentContainerStyle={styles.list}
        />
      )}

      {/* Detail modal */}
      <Modal visible={selectedReport !== null} animationType="slide" transparent>
        <Pressable style={styles.backdrop} onPress={() => setSelectedReport(null)}>
          <Pressable style={styles.sheet} onPress={() => {}}>
            <View style={styles.handle} />

            {selectedReport && (
              <>
                <Text style={styles.sheetTitle}>{getTargetLabel(selectedReport)}</Text>
                <Text style={styles.sheetTime}>{dayjs(selectedReport.created_at).locale(i18n.language).format('D MMM YYYY · H[h]mm')}</Text>

                <Text style={styles.sectionLabel}>{t('admin.reason')}</Text>
                <Text style={styles.reasonFull}>{selectedReport.reason}</Text>

                <Text style={styles.sectionLabel}>{t('admin.targetId')}</Text>
                <Text style={styles.targetId}>{selectedReport.target_id}</Text>

                {selectedReport.status === 'pending' ? (
                  <>
                    <Text style={styles.sectionLabel}>{t('admin.note')}</Text>
                    <TextInput
                      style={styles.noteInput}
                      value={adminNote}
                      onChangeText={setAdminNote}
                      placeholder={t('admin.notePlaceholder')}
                      placeholderTextColor={colors.textSecondary}
                      multiline
                      maxLength={500}
                    />

                    {REMOVABLE_TYPES.includes(selectedReport.target_type) && (
                      <Pressable
                        style={[styles.removeButton, isProcessing && styles.disabled]}
                        onPress={handleRemoveContent}
                        disabled={isProcessing}
                      >
                        <Trash2 size={16} color="#FFFFFF" strokeWidth={2.2} />
                        <Text style={styles.removeText}>{t('admin.removeContent', { defaultValue: 'Retirer le contenu' })}</Text>
                      </Pressable>
                    )}

                    <View style={styles.actionRow}>
                      <Pressable
                        style={[styles.dismissButton, isProcessing && styles.disabled]}
                        onPress={() => handleAction('dismissed')}
                        disabled={isProcessing}
                      >
                        <Text style={styles.dismissText}>{t('admin.dismiss')}</Text>
                      </Pressable>
                      <Pressable
                        style={[styles.actionButton, isProcessing && styles.disabled]}
                        onPress={() => {
                          if (selectedReport.target_type === 'user') {
                            Alert.alert(t('admin.suspendConfirm'), '', [
                              { text: t('activity.no'), style: 'cancel', onPress: () => handleAction('actioned') },
                              { text: t('admin.suspendYes'), style: 'destructive', onPress: () => handleAction('actioned', selectedReport.target_id) },
                            ]);
                          } else {
                            handleAction('actioned');
                          }
                        }}
                        disabled={isProcessing}
                      >
                        <Text style={styles.actionText}>{t('admin.action')}</Text>
                      </Pressable>
                    </View>
                  </>
                ) : (
                  <>
                    {selectedReport.admin_note && (
                      <>
                        <Text style={styles.sectionLabel}>{t('admin.note')}</Text>
                        <Text style={styles.reasonFull}>{selectedReport.admin_note}</Text>
                      </>
                    )}
                    <View style={[styles.statusBadge, selectedReport.status === 'dismissed' ? styles.dismissedBadge : styles.actionedBadge]}>
                      <Text style={styles.statusText}>
                        {selectedReport.status === 'dismissed' ? t('admin.dismissed') : t('admin.actioned')}
                      </Text>
                    </View>
                  </>
                )}
              </>
            )}
          </Pressable>
        </Pressable>
      </Modal>

      {/* Reject-pro reason modal */}
      <Modal visible={rejectApp !== null} animationType="slide" transparent>
        <Pressable style={styles.backdrop} onPress={() => setRejectApp(null)}>
          <Pressable style={styles.sheet} onPress={() => {}}>
            <View style={styles.handle} />
            <Text style={styles.sheetTitle}>{t('admin.proRejectTitle', { defaultValue: 'Refuser la demande' })}</Text>
            <Text style={styles.sheetTime}>{rejectApp?.company_name ?? rejectApp?.display_name}</Text>
            <Text style={styles.sectionLabel}>{t('admin.proRejectReason', { defaultValue: 'Motif (optionnel, envoyé au demandeur)' })}</Text>
            <TextInput
              style={styles.noteInput}
              value={rejectReason}
              onChangeText={setRejectReason}
              placeholder={t('admin.proRejectReasonPlaceholder', { defaultValue: 'Ex : structure non vérifiable, infos incomplètes…' })}
              placeholderTextColor={colors.textSecondary}
              multiline
              maxLength={500}
            />
            <View style={styles.actionRow}>
              <Pressable style={styles.dismissButton} onPress={() => setRejectApp(null)}>
                <Text style={styles.dismissText}>{t('activity.no', { defaultValue: 'Annuler' })}</Text>
              </Pressable>
              <Pressable
                style={[styles.actionButton, proBusyId === rejectApp?.user_id && styles.disabled]}
                onPress={confirmRejectPro}
                disabled={proBusyId === rejectApp?.user_id}
              >
                <Text style={styles.actionText}>{t('admin.proReject', { defaultValue: 'Refuser' })}</Text>
              </Pressable>
            </View>
          </Pressable>
        </Pressable>
      </Modal>
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  tabs: { flexDirection: 'row', padding: spacing.md, gap: spacing.sm },
  tab: { flex: 1, paddingVertical: spacing.sm, alignItems: 'center', borderRadius: radius.md, backgroundColor: colors.surface },
  tabActive: { backgroundColor: colors.cta },
  tabText: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: 'bold' },
  tabTextActive: { color: colors.textPrimary },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  loadingText: { color: colors.textSecondary, fontSize: fontSizes.lg },
  emptyText: { color: colors.textSecondary, fontSize: fontSizes.md },
  list: { padding: spacing.md },
  card: { backgroundColor: colors.surface, borderRadius: radius.md, padding: spacing.md, marginBottom: spacing.sm },
  cardHeader: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: spacing.xs },
  targetType: { color: colors.cta, fontSize: fontSizes.xs, fontWeight: 'bold', textTransform: 'uppercase' },
  time: { color: colors.textSecondary, fontSize: fontSizes.xs },
  reason: { color: colors.textPrimary, fontSize: fontSizes.sm },
  statusBadge: { alignSelf: 'flex-start', borderRadius: radius.full, paddingHorizontal: spacing.sm, paddingVertical: 2, marginTop: spacing.xs },
  dismissedBadge: { backgroundColor: colors.textSecondary + '30' },
  actionedBadge: { backgroundColor: colors.error + '30' },
  statusText: { fontSize: fontSizes.xs, fontWeight: 'bold' },
  backdrop: { flex: 1, backgroundColor: colors.overlay, justifyContent: 'flex-end' },
  sheet: { backgroundColor: colors.background, borderTopLeftRadius: radius.lg, borderTopRightRadius: radius.lg, padding: spacing.lg, paddingBottom: spacing.xl + 16, maxHeight: '80%' },
  handle: { width: 40, height: 4, borderRadius: 2, backgroundColor: colors.textSecondary, alignSelf: 'center', marginBottom: spacing.lg, opacity: 0.4 },
  sheetTitle: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: 'bold' },
  sheetTime: { color: colors.textSecondary, fontSize: fontSizes.xs, marginBottom: spacing.md },
  sectionLabel: { color: colors.textSecondary, fontSize: fontSizes.xs, textTransform: 'uppercase', marginTop: spacing.md, marginBottom: spacing.xs },
  reasonFull: { color: colors.textPrimary, fontSize: fontSizes.sm, lineHeight: 20 },
  targetId: { color: colors.textSecondary, fontSize: fontSizes.xs, fontFamily: 'monospace' },
  noteInput: { backgroundColor: colors.surface, color: colors.textPrimary, borderRadius: radius.md, paddingHorizontal: spacing.md, paddingVertical: spacing.md, fontSize: fontSizes.sm, minHeight: 60, textAlignVertical: 'top' },
  actionRow: { flexDirection: 'row', gap: spacing.sm, marginTop: spacing.lg },
  dismissButton: { flex: 1, flexDirection: 'row', gap: 6, justifyContent: 'center', backgroundColor: colors.surface, borderRadius: radius.md, paddingVertical: spacing.md, alignItems: 'center' },
  dismissText: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: 'bold' },
  proTitleRow: { flexDirection: 'row', alignItems: 'center', gap: 6, flex: 1, marginRight: spacing.sm },
  proLine: { color: colors.textPrimary, fontSize: fontSizes.sm, marginTop: 2 },
  proLineMuted: { color: colors.textSecondary, fontSize: fontSizes.xs, marginTop: 2 },
  approveButton: { flex: 1, flexDirection: 'row', gap: 6, justifyContent: 'center', backgroundColor: colors.success, borderRadius: radius.md, paddingVertical: spacing.md, alignItems: 'center' },
  approveText: { color: '#FFFFFF', fontSize: fontSizes.sm, fontWeight: 'bold' },
  actionButton: { flex: 1, backgroundColor: colors.error, borderRadius: radius.md, paddingVertical: spacing.md, alignItems: 'center' },
  actionText: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: 'bold' },
  removeButton: { flexDirection: 'row', gap: 8, justifyContent: 'center', alignItems: 'center', backgroundColor: colors.error, borderRadius: radius.md, paddingVertical: spacing.md, marginTop: spacing.md },
  removeText: { color: '#FFFFFF', fontSize: fontSizes.sm, fontWeight: '800' },
  disabled: { opacity: 0.4 },
});
