import { useState, useMemo, useEffect } from 'react';
import { View, Pressable, FlatList, Modal, StyleSheet, Alert, Linking } from 'react-native';
import { AppText, AppTextInput } from '@/components/app-text';
import { useTranslation } from 'react-i18next';
import { useLocalSearchParams , Redirect, useRouter } from 'expo-router';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import dayjs from 'dayjs';
import relativeTime from 'dayjs/plugin/relativeTime';
import 'dayjs/locale/fr';
import * as Burnt from 'burnt';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius, shadows } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { reportService, type Report } from '@/services/report-service';
import { proService, type PendingProApplication } from '@/services/pro-service';
import { Check, X, BadgeCheck, Trash2 } from 'lucide-react-native';
import { useIsAdmin } from '@/hooks/use-is-admin';
import { adminService, type AdminUserInfo } from '@/services/admin-service';
import { getFriendlyError } from '@/utils/friendly-error';

// Content types the admin can take down from a report (never DMs or users).
const REMOVABLE_TYPES = ['activity', 'message', 'group', 'channel', 'pro_review', 'offering_review'];

dayjs.extend(relativeTime);

type FilterTab = 'pending' | 'resolved' | 'pros';

export default function ModerationScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t, i18n } = useTranslation();
  const queryClient = useQueryClient();
  const { tab: tabParam } = useLocalSearchParams<{ tab?: string }>();
  const router = useRouter();
  const { isAdmin, isLoading: adminLoading } = useIsAdmin();
  const [tab, setTab] = useState<FilterTab>(tabParam === 'pros' ? 'pros' : 'pending');
  const [selectedReport, setSelectedReport] = useState<Report | null>(null);
  const [adminNote, setAdminNote] = useState('');
  const [isProcessing, setIsProcessing] = useState(false);
  const [resolvedUser, setResolvedUser] = useState<AdminUserInfo | null>(null);
  const [resolving, setResolving] = useState(false);
  useEffect(() => { setResolvedUser(null); }, [selectedReport?.id]);

  const handleResolveIdentity = async () => {
    if (!selectedReport) return;
    setResolving(true);
    try {
      setResolvedUser(await adminService.resolveUser(selectedReport.target_id));
    } catch (e) {
      Alert.alert(getFriendlyError(e));
    } finally {
      setResolving(false);
    }
  };

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
      message: t('admin.targetMessage', { defaultValue: 'Message' }),
      group: t('admin.targetGroup', { defaultValue: 'Groupe' }),
      channel: t('admin.targetChannel', { defaultValue: 'Discussion ouverte' }),
      pro_review: t('admin.targetProReview', { defaultValue: 'Avis sur un pro' }),
      offering_review: t('admin.targetOfferingReview', { defaultValue: 'Avis sur une offre' }),
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
          <AppText style={[styles.tabText, tab === 'pending' && styles.tabTextActive]}>
            {t('admin.pending')} ({(reports ?? []).filter((r) => r.status === 'pending').length})
          </AppText>
        </Pressable>
        <Pressable style={[styles.tab, tab === 'resolved' && styles.tabActive]} onPress={() => setTab('resolved')}>
          <AppText style={[styles.tabText, tab === 'resolved' && styles.tabTextActive]}>
            {t('admin.resolved')}
          </AppText>
        </Pressable>
        <Pressable style={[styles.tab, tab === 'pros' && styles.tabActive]} onPress={() => setTab('pros')}>
          <AppText style={[styles.tabText, tab === 'pros' && styles.tabTextActive]}>
            {t('admin.prosTab', { defaultValue: 'Pros' })} ({(pendingPros ?? []).length})
          </AppText>
        </Pressable>
      </View>

      {/* List */}
      {tab === 'pros' ? (
        prosLoading ? (
          <View style={styles.center}><AppText style={styles.loadingText}>...</AppText></View>
        ) : (pendingPros ?? []).length === 0 ? (
          <View style={styles.center}><AppText style={styles.emptyText}>{t('admin.noPendingPros', { defaultValue: 'Aucune demande en attente' })}</AppText></View>
        ) : (
          <FlatList
            data={pendingPros}
            keyExtractor={(item) => item.user_id}
            renderItem={({ item }) => (
              <View style={styles.card}>
                <View style={styles.cardHeader}>
                  <View style={styles.proTitleRow}>
                    <BadgeCheck size={16} color={colors.cta} strokeWidth={2.4} />
                    <AppText style={styles.targetType} numberOfLines={1}>{item.company_name ?? item.display_name}</AppText>
                  </View>
                  <AppText style={styles.time}>{dayjs(item.created_at).locale(i18n.language).fromNow()}</AppText>
                </View>
                {item.prior_review_count > 0 && (
                  <AppText style={styles.proHistoryWarning}>
                    ⚠️ Déjà passé en revue ×{item.prior_review_count} — dernier :{' '}
                    {item.last_review_action === 'approve_pro' ? 'approuvé' : 'refusé'}
                    {item.last_review_at ? ` le ${dayjs(item.last_review_at).format('DD/MM/YYYY')}` : ''}.
                    {item.last_review_action === 'approve_pro' ? ' Désinscrit depuis — les avis/photos sont repartis avec (vérifier le passif avant de re-valider).' : ''}
                  </AppText>
                )}
                {/* The WHOLE application (Scott 2026-10-31): the admin validates a
                    pro on everything they declared, not a summary. Contacts are
                    the pro's explicit fields → tappable for checking. */}
                <View style={styles.proDetails}>
                  <ProRow label="Raison sociale" value={item.company_name} styles={styles} />
                  <ProRow label="Page" value={item.display_name} styles={styles} />
                  <ProRow label="Responsable" value={item.real_name} styles={styles} />
                  <ProRow label="Métiers" value={(item.professions?.length ? item.professions : item.profession ? [item.profession] : []).map((c) => t(`pro.profession.${c}`, { defaultValue: c })).join(' · ') || null} styles={styles} />
                  <ProRow label="Lieu" value={item.primary_location_name} styles={styles}
                    onPress={item.primary_lat != null && item.primary_lng != null
                      ? () => Linking.openURL(`https://www.google.com/maps/search/?api=1&query=${item.primary_lat},${item.primary_lng}`)
                      : undefined} />
                  <ProRow label="Accroche" value={item.tagline} styles={styles} />
                  <ProRow label="Description" value={item.description} styles={styles} />
                  <ProRow label="E-mail" value={item.email} styles={styles} onPress={item.email ? () => Linking.openURL(`mailto:${item.email}`) : undefined} />
                  <ProRow label="Téléphone" value={item.phone} styles={styles} onPress={item.phone ? () => Linking.openURL(`tel:${item.phone}`) : undefined} />
                  <ProRow label="Site" value={item.website} styles={styles} onPress={item.website ? () => Linking.openURL(/^https?:\/\//i.test(item.website!) ? item.website! : `https://${item.website}`) : undefined} />
                  <ProRow label="Instagram" value={item.instagram} styles={styles}
                    onPress={item.instagram ? () => Linking.openURL(`https://instagram.com/${item.instagram!.replace(/^@/, '').replace(/^https?:\/\/(www\.)?instagram\.com\//i, '')}`) : undefined} />
                  <ProRow label="Facebook" value={item.facebook} styles={styles}
                    onPress={item.facebook ? () => Linking.openURL(/^https?:\/\//i.test(item.facebook!) ? item.facebook! : `https://facebook.com/${item.facebook}`) : undefined} />
                  <ProRow label="Demande" value={`envoyée le ${dayjs(item.created_at).format('DD/MM/YYYY HH:mm')}${item.updated_at !== item.created_at ? ` · modifiée le ${dayjs(item.updated_at).format('DD/MM/YYYY HH:mm')}` : ''}`} styles={styles} />
                  <ProRow label="Compte" value={`créé le ${dayjs(item.account_created_at).format('DD/MM/YYYY')} · voir le profil`} styles={styles}
                    onPress={() => router.push(`/(auth)/profile/${item.user_id}`)} />
                </View>
                <View style={styles.actionRow}>
                  <Pressable style={[styles.dismissButton, proBusyId === item.user_id && styles.disabled]} onPress={() => handleRejectPro(item)} disabled={proBusyId === item.user_id}>
                    <X size={15} color={colors.error} strokeWidth={2.6} />
                    <AppText style={styles.dismissText}>{t('admin.proReject', { defaultValue: 'Refuser' })}</AppText>
                  </Pressable>
                  <Pressable style={[styles.approveButton, proBusyId === item.user_id && styles.disabled]} onPress={() => handleApprovePro(item)} disabled={proBusyId === item.user_id}>
                    <Check size={15} color="#FFFFFF" strokeWidth={2.6} />
                    <AppText style={styles.approveText}>{t('admin.proApprove', { defaultValue: 'Valider' })}</AppText>
                  </Pressable>
                </View>
              </View>
            )}
            contentContainerStyle={styles.list}
          />
        )
      ) : isLoading ? (
        <View style={styles.center}>
          <AppText style={styles.loadingText}>...</AppText>
        </View>
      ) : filtered.length === 0 ? (
        <View style={styles.center}>
          <AppText style={styles.emptyText}>{t('admin.noReports')}</AppText>
        </View>
      ) : (
        <FlatList
          data={filtered}
          keyExtractor={(item) => item.id}
          renderItem={({ item }) => (
            <Pressable style={styles.card} onPress={() => { setSelectedReport(item); setAdminNote(''); }}>
              <View style={styles.cardHeader}>
                <AppText style={styles.targetType}>{getTargetLabel(item)}</AppText>
                <AppText style={styles.time}>{dayjs(item.created_at).locale(i18n.language).fromNow()}</AppText>
              </View>
              <AppText style={styles.reason} numberOfLines={2}>{item.reason}</AppText>
              {item.status !== 'pending' && (
                <View style={[styles.statusBadge, item.status === 'dismissed' ? styles.dismissedBadge : styles.actionedBadge]}>
                  <AppText style={styles.statusText}>{item.status === 'dismissed' ? t('admin.dismissed') : t('admin.actioned')}</AppText>
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
                <AppText style={styles.sheetTitle}>{getTargetLabel(selectedReport)}</AppText>
                <AppText style={styles.sheetTime}>{dayjs(selectedReport.created_at).locale(i18n.language).format('D MMM YYYY · H[h]mm')}</AppText>

                <AppText style={styles.sectionLabel}>{t('admin.reason')}</AppText>
                <AppText style={styles.reasonFull}>{selectedReport.reason}</AppText>

                <AppText style={styles.sectionLabel}>{t('admin.targetId')}</AppText>
                <AppText style={styles.targetId}>{selectedReport.target_id}</AppText>

                {selectedReport.target_type === 'user' && (
                  resolvedUser ? (
                    <View style={styles.identityCard}>
                      <AppText style={styles.identityName}>{resolvedUser.display_name}{resolvedUser.is_admin ? ' · admin' : ''}</AppText>
                      <AppText style={styles.identityLine} selectable>{resolvedUser.email}</AppText>
                      <AppText style={styles.identityLine}>
                        {resolvedUser.tier} · {resolvedUser.suspended_at ? t('admin.suspended', { defaultValue: 'Suspendu' }) : t('admin.active', { defaultValue: 'Actif' })}
                      </AppText>
                    </View>
                  ) : (
                    <Pressable style={[styles.resolveBtn, resolving && styles.disabled]} onPress={handleResolveIdentity} disabled={resolving}>
                      <AppText style={styles.resolveBtnText}>{resolving ? '…' : t('admin.resolveIdentity', { defaultValue: "Voir l'identité" })}</AppText>
                    </Pressable>
                  )
                )}

                {selectedReport.status === 'pending' ? (
                  <>
                    <AppText style={styles.sectionLabel}>{t('admin.note')}</AppText>
                    <AppTextInput
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
                        <AppText style={styles.removeText}>{t('admin.removeContent', { defaultValue: 'Retirer le contenu' })}</AppText>
                      </Pressable>
                    )}

                    <View style={styles.actionRow}>
                      <Pressable
                        style={[styles.dismissButton, isProcessing && styles.disabled]}
                        onPress={() => handleAction('dismissed')}
                        disabled={isProcessing}
                      >
                        <AppText style={styles.dismissText}>{t('admin.dismiss')}</AppText>
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
                        <AppText style={styles.actionText}>{t('admin.action')}</AppText>
                      </Pressable>
                    </View>
                  </>
                ) : (
                  <>
                    {selectedReport.admin_note && (
                      <>
                        <AppText style={styles.sectionLabel}>{t('admin.note')}</AppText>
                        <AppText style={styles.reasonFull}>{selectedReport.admin_note}</AppText>
                      </>
                    )}
                    <View style={[styles.statusBadge, selectedReport.status === 'dismissed' ? styles.dismissedBadge : styles.actionedBadge]}>
                      <AppText style={styles.statusText}>
                        {selectedReport.status === 'dismissed' ? t('admin.dismissed') : t('admin.actioned')}
                      </AppText>
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
            <AppText style={styles.sheetTitle}>{t('admin.proRejectTitle', { defaultValue: 'Refuser la demande' })}</AppText>
            <AppText style={styles.sheetTime}>{rejectApp?.company_name ?? rejectApp?.display_name}</AppText>
            <AppText style={styles.sectionLabel}>{t('admin.proRejectReason', { defaultValue: 'Motif (optionnel, envoyé au demandeur)' })}</AppText>
            <AppTextInput
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
                <AppText style={styles.dismissText}>{t('activity.no', { defaultValue: 'Annuler' })}</AppText>
              </Pressable>
              <Pressable
                style={[styles.actionButton, proBusyId === rejectApp?.user_id && styles.disabled]}
                onPress={confirmRejectPro}
                disabled={proBusyId === rejectApp?.user_id}
              >
                <AppText style={styles.actionText}>{t('admin.proReject', { defaultValue: 'Refuser' })}</AppText>
              </Pressable>
            </View>
          </Pressable>
        </Pressable>
      </Modal>
    </View>
  );
}

function ProRow({ label, value, onPress, styles }: {
  label: string; value: string | null | undefined; onPress?: () => void;
  styles: ReturnType<typeof createStyles>;
}) {
  if (!value || !value.trim()) return null;
  return (
    <View style={styles.proRow}>
      <AppText style={styles.proRowLabel}>{label}</AppText>
      {onPress ? (
        <Pressable style={{ flex: 1 }} onPress={onPress} accessibilityRole="link">
          <AppText style={[styles.proRowValue, styles.proRowLink]}>{value}</AppText>
        </Pressable>
      ) : (
        <AppText style={styles.proRowValue} selectable>{value}</AppText>
      )}
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  tabs: { flexDirection: 'row', padding: spacing.md, gap: spacing.sm },
  tab: { borderWidth: 1, borderColor: colors.lineStrong, flex: 1, paddingVertical: spacing.sm, alignItems: 'center', borderRadius: radius.md, backgroundColor: colors.surfaceAlt },
  tabActive: { backgroundColor: colors.cta },
  tabText: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: 'bold' },
  tabTextActive: { color: colors.textPrimary },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  loadingText: { color: colors.textSecondary, fontSize: fontSizes.lg },
  emptyText: { color: colors.textSecondary, fontSize: fontSizes.md },
  list: { padding: spacing.md },
  card: { borderWidth: 1, borderColor: colors.lineStrong, ...shadows.card, backgroundColor: colors.surface, borderRadius: radius.md, padding: spacing.md, marginBottom: spacing.sm },
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
  resolveBtn: { alignSelf: 'flex-start', marginTop: spacing.sm, backgroundColor: colors.surface, borderWidth: 1, borderColor: colors.cta, borderRadius: radius.md, paddingVertical: spacing.sm, paddingHorizontal: spacing.md },
  resolveBtnText: { color: colors.cta, fontSize: fontSizes.sm, fontWeight: '700' },
  identityCard: { marginTop: spacing.sm, backgroundColor: colors.surface, borderRadius: radius.md, borderWidth: 1, borderColor: colors.borderMuted, padding: spacing.md, gap: 2 },
  identityName: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '800' },
  identityLine: { color: colors.textSecondary, fontSize: fontSizes.sm },
  noteInput: { borderWidth: 1, borderColor: colors.lineStrong, backgroundColor: colors.surfaceAlt, color: colors.textPrimary, borderRadius: radius.md, paddingHorizontal: spacing.md, paddingVertical: spacing.md, fontSize: fontSizes.sm, minHeight: 60, textAlignVertical: 'top' },
  actionRow: { flexDirection: 'row', gap: spacing.sm, marginTop: spacing.lg },
  dismissButton: { borderWidth: 1, borderColor: colors.lineStrong, flex: 1, flexDirection: 'row', gap: 6, justifyContent: 'center', backgroundColor: colors.surfaceAlt, borderRadius: radius.md, paddingVertical: spacing.md, alignItems: 'center' },
  dismissText: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: 'bold' },
  proTitleRow: { flexDirection: 'row', alignItems: 'center', gap: 6, flex: 1, marginRight: spacing.sm },
  proDetails: { marginTop: spacing.sm, gap: 6 },
  proRow: { flexDirection: 'row', gap: spacing.sm },
  proRowLabel: { width: 104, color: colors.textSecondary, fontSize: fontSizes.xs, fontWeight: '700', paddingTop: 1 },
  proRowValue: { flex: 1, color: colors.textPrimary, fontSize: fontSizes.sm },
  proRowLink: { color: colors.cta, textDecorationLine: 'underline' },
  proLineMuted: { color: colors.textSecondary, fontSize: fontSizes.xs, marginTop: 2 },
  proHistoryWarning: { color: colors.warning, fontSize: fontSizes.xs, fontWeight: '600', marginTop: 6 },
  approveButton: { flex: 1, flexDirection: 'row', gap: 6, justifyContent: 'center', backgroundColor: colors.success, borderRadius: radius.md, paddingVertical: spacing.md, alignItems: 'center' },
  approveText: { color: '#FFFFFF', fontSize: fontSizes.sm, fontWeight: 'bold' },
  actionButton: { flex: 1, backgroundColor: colors.error, borderRadius: radius.md, paddingVertical: spacing.md, alignItems: 'center' },
  actionText: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: 'bold' },
  removeButton: { flexDirection: 'row', gap: 8, justifyContent: 'center', alignItems: 'center', backgroundColor: colors.error, borderRadius: radius.md, paddingVertical: spacing.md, marginTop: spacing.md },
  removeText: { color: '#FFFFFF', fontSize: fontSizes.sm, fontWeight: '800' },
  disabled: { opacity: 0.4 },
});
