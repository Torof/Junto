import { useState } from 'react';
import { View, Text, Pressable, FlatList, TextInput, Modal, StyleSheet, Alert } from 'react-native';
import { useTranslation } from 'react-i18next';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import dayjs from 'dayjs';
import relativeTime from 'dayjs/plugin/relativeTime';
import 'dayjs/locale/fr';
import * as Burnt from 'burnt';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';
import { reportService, type Report } from '@/services/report-service';

dayjs.extend(relativeTime);

type FilterTab = 'pending' | 'resolved';

export default function ModerationScreen() {
  const { t, i18n } = useTranslation();
  const queryClient = useQueryClient();
  const [tab, setTab] = useState<FilterTab>('pending');
  const [selectedReport, setSelectedReport] = useState<Report | null>(null);
  const [adminNote, setAdminNote] = useState('');
  const [isProcessing, setIsProcessing] = useState(false);

  const { data: reports, isLoading } = useQuery({
    queryKey: ['admin-reports'],
    queryFn: () => reportService.getAll(),
  });

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

  const getTargetLabel = (report: Report) => {
    const typeLabels: Record<string, string> = {
      user: t('admin.targetUser'),
      activity: t('admin.targetActivity'),
      wall_message: t('admin.targetWallMessage'),
      private_message: t('admin.targetPrivateMessage'),
    };
    return typeLabels[report.target_type] ?? report.target_type;
  };

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
      </View>

      {/* List */}
      {isLoading ? (
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
                <Text style={styles.sheetTime}>{dayjs(selectedReport.created_at).locale(i18n.language).format('D MMM YYYY · HH:mm')}</Text>

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
    </View>
  );
}

const styles = StyleSheet.create({
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
  backdrop: { flex: 1, backgroundColor: 'rgba(0,0,0,0.5)', justifyContent: 'flex-end' },
  sheet: { backgroundColor: colors.background, borderTopLeftRadius: radius.lg, borderTopRightRadius: radius.lg, padding: spacing.lg, paddingBottom: spacing.xl + 16, maxHeight: '80%' },
  handle: { width: 40, height: 4, borderRadius: 2, backgroundColor: colors.textSecondary, alignSelf: 'center', marginBottom: spacing.lg, opacity: 0.4 },
  sheetTitle: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: 'bold' },
  sheetTime: { color: colors.textSecondary, fontSize: fontSizes.xs, marginBottom: spacing.md },
  sectionLabel: { color: colors.textSecondary, fontSize: fontSizes.xs, textTransform: 'uppercase', marginTop: spacing.md, marginBottom: spacing.xs },
  reasonFull: { color: colors.textPrimary, fontSize: fontSizes.sm, lineHeight: 20 },
  targetId: { color: colors.textSecondary, fontSize: fontSizes.xs, fontFamily: 'monospace' },
  noteInput: { backgroundColor: colors.surface, color: colors.textPrimary, borderRadius: radius.md, paddingHorizontal: spacing.md, paddingVertical: spacing.md, fontSize: fontSizes.sm, minHeight: 60, textAlignVertical: 'top' },
  actionRow: { flexDirection: 'row', gap: spacing.sm, marginTop: spacing.lg },
  dismissButton: { flex: 1, backgroundColor: colors.surface, borderRadius: radius.md, paddingVertical: spacing.md, alignItems: 'center' },
  dismissText: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: 'bold' },
  actionButton: { flex: 1, backgroundColor: colors.error, borderRadius: radius.md, paddingVertical: spacing.md, alignItems: 'center' },
  actionText: { color: '#fff', fontSize: fontSizes.sm, fontWeight: 'bold' },
  disabled: { opacity: 0.4 },
});
