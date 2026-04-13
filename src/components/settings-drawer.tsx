import { useState } from 'react';
import { View, Text, TextInput, Pressable, Switch, ScrollView, StyleSheet, Modal, Alert } from 'react-native';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import * as Burnt from 'burnt';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';
import { authService } from '@/services/auth-service';
import { supabase } from '@/services/supabase';

const NOTIFICATION_TYPES = [
  'join_request',
  'participant_joined',
  'request_accepted',
  'request_refused',
  'participant_removed',
  'participant_left',
  'activity_cancelled',
  'activity_updated',
] as const;

type NotificationPreferences = Record<string, boolean>;

interface SettingsDrawerProps {
  visible: boolean;
  onClose: () => void;
}

export function SettingsDrawer({ visible, onClose }: SettingsDrawerProps) {
  const { t } = useTranslation();
  const router = useRouter();
  const queryClient = useQueryClient();
  const [showNotifPrefs, setShowNotifPrefs] = useState(false);
  const [editingName, setEditingName] = useState(false);
  const [newName, setNewName] = useState('');

  const { data: user } = useQuery({
    queryKey: ['currentUser'],
    queryFn: async () => {
      const { data: { session } } = await supabase.auth.getSession();
      if (!session) return null;
      const { data } = await supabase
        .from('users')
        .select('display_name, email, tier, sports, avatar_url, reliability_score, is_admin, created_at, notification_preferences')
        .single();
      return data as { display_name: string; email: string; tier: string; sports: string[]; avatar_url: string | null; reliability_score: number | null; is_admin: boolean; created_at: string; notification_preferences: NotificationPreferences } | null;
    },
    retry: 2,
  });

  const prefs = user?.notification_preferences ?? {};

  const togglePref = async (type: string) => {
    const current = prefs[type] !== false;
    const updated = { ...prefs, [type]: !current };
    await supabase
      .from('users')
      .update({ notification_preferences: updated } as unknown as { bio: string })
      .eq('id', (await supabase.auth.getUser()).data.user?.id ?? '');
    await queryClient.invalidateQueries({ queryKey: ['currentUser'] });
  };

  const handleEditName = () => {
    setNewName(user?.display_name ?? '');
    setEditingName(true);
  };

  const handleSaveName = async () => {
    if (newName.trim().length < 2) {
      Alert.alert(t('auth.error'), t('profil.nameTooShort'));
      return;
    }
    await supabase
      .from('users')
      .update({ display_name: newName.trim() })
      .eq('id', (await supabase.auth.getUser()).data.user?.id ?? '');
    await queryClient.invalidateQueries({ queryKey: ['currentUser'] });
    setEditingName(false);
    Burnt.toast({ title: t('toast.profileUpdated'), preset: 'done' });
  };

  const handleLogout = async () => {
    onClose();
    await authService.signOut();
  };

  const tierLabel = user?.tier === 'pro' ? 'Pro' : user?.tier === 'premium' ? 'Premium' : 'Free';

  return (
    <Modal visible={visible} animationType="none" transparent>
      <View style={styles.backdrop}>
        <Pressable style={styles.backdropTouch} onPress={onClose} />
        <View style={styles.drawer}>
          <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={styles.scrollContent} bounces={false}>
            {/* Close */}
            <Pressable style={styles.closeButton} onPress={onClose}>
              <Text style={styles.closeText}>✕</Text>
            </Pressable>

            {/* Account section */}
            <Text style={styles.sectionTitle}>{t('drawer.account')}</Text>

            <View style={styles.row}>
              <Text style={styles.rowLabel}>{t('drawer.email')}</Text>
              <Text style={styles.rowValue}>{user?.email ?? ''}</Text>
            </View>

            <View style={styles.row}>
              <Text style={styles.rowLabel}>{t('drawer.pseudo')}</Text>
              {editingName ? (
                <View style={styles.editNameRow}>
                  <TextInput
                    style={styles.nameInput}
                    value={newName}
                    onChangeText={setNewName}
                    maxLength={30}
                    autoFocus
                  />
                  <Pressable onPress={handleSaveName}>
                    <Text style={styles.saveLink}>✓</Text>
                  </Pressable>
                  <Pressable onPress={() => setEditingName(false)}>
                    <Text style={styles.cancelLink}>✕</Text>
                  </Pressable>
                </View>
              ) : (
                <Pressable onPress={handleEditName}>
                  <Text style={styles.rowValueEditable}>{user?.display_name ?? '...'}</Text>
                </Pressable>
              )}
            </View>

            <View style={styles.row}>
              <Text style={styles.rowLabel}>{t('drawer.subscription')}</Text>
              <Text style={[styles.rowValue, styles.tierBadge]}>{tierLabel}</Text>
            </View>

            {/* Preferences section */}
            <Text style={styles.sectionTitle}>{t('drawer.preferences')}</Text>

            <Pressable style={styles.row} onPress={() => setShowNotifPrefs(!showNotifPrefs)}>
              <Text style={styles.rowLabel}>{t('profil.notificationPrefs')}</Text>
              <Text style={styles.arrow}>{showNotifPrefs ? '▲' : '▼'}</Text>
            </Pressable>

            {showNotifPrefs && (
              <View style={styles.notifContent}>
                {NOTIFICATION_TYPES.map((type) => (
                  <View key={type} style={styles.prefRow}>
                    <Text style={styles.prefLabel}>{t(`profil.notifType.${type}`)}</Text>
                    <Switch
                      value={prefs[type] !== false}
                      onValueChange={() => togglePref(type)}
                      trackColor={{ false: colors.surface, true: colors.cta }}
                      thumbColor="#fff"
                    />
                  </View>
                ))}
              </View>
            )}

            {/* Admin */}
            {user?.is_admin && (
              <Pressable style={styles.row} onPress={() => { onClose(); router.push('/(auth)/admin/moderation'); }}>
                <Text style={styles.rowLabel}>{t('admin.moderation')}</Text>
                <Text style={styles.arrow}>›</Text>
              </Pressable>
            )}

            {/* Legal */}
            <Text style={styles.sectionTitle}>{t('drawer.legal')}</Text>
            <Pressable style={styles.row} onPress={() => { onClose(); router.push('/(auth)/legal/terms'); }}>
              <Text style={styles.rowLabel}>{t('legal.terms')}</Text>
              <Text style={styles.arrow}>›</Text>
            </Pressable>
            <Pressable style={styles.row} onPress={() => { onClose(); router.push('/(auth)/legal/privacy'); }}>
              <Text style={styles.rowLabel}>{t('legal.privacy')}</Text>
              <Text style={styles.arrow}>›</Text>
            </Pressable>

            {/* Delete account */}
            <Pressable style={styles.deleteButton} onPress={() => {
              Alert.alert(
                t('account.deleteTitle'),
                t('account.deleteMessage'),
                [
                  { text: t('activity.no'), style: 'cancel' },
                  {
                    text: t('account.deleteConfirm'),
                    style: 'destructive',
                    onPress: () => {
                      // Second confirmation
                      Alert.alert(
                        t('account.deleteTitle2'),
                        t('account.deleteMessage2'),
                        [
                          { text: t('activity.no'), style: 'cancel' },
                          {
                            text: t('account.deleteFinal'),
                            style: 'destructive',
                            onPress: async () => {
                              try {
                                await supabase.rpc('delete_own_account' as 'accept_tos');
                                await supabase.auth.signOut();
                                onClose();
                              } catch {
                                Alert.alert(t('auth.error'), t('auth.unknownError'));
                              }
                            },
                          },
                        ],
                      );
                    },
                  },
                ],
              );
            }}>
              <Text style={styles.deleteText}>{t('account.delete')}</Text>
            </Pressable>

            {/* Logout */}
            <Pressable style={styles.logoutButton} onPress={handleLogout}>
              <Text style={styles.logoutText}>{t('profil.logout')}</Text>
            </Pressable>
          </ScrollView>
        </View>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  backdrop: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.5)',
    flexDirection: 'row',
  },
  backdropTouch: {
    width: '20%',
  },
  drawer: {
    flex: 1,
    width: '80%',
    backgroundColor: colors.background,
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.xl + 16,
    paddingBottom: spacing.xl,
  },
  scrollContent: {
    paddingBottom: spacing.xl,
  },
  closeButton: {
    alignSelf: 'flex-end',
    width: 32,
    height: 32,
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: spacing.lg,
  },
  closeText: { color: colors.textSecondary, fontSize: 18 },
  sectionTitle: {
    color: colors.textSecondary, fontSize: fontSizes.xs,
    textTransform: 'uppercase', marginBottom: spacing.md, marginTop: spacing.lg,
  },
  row: {
    backgroundColor: colors.surface, borderRadius: radius.md,
    paddingHorizontal: spacing.md, paddingVertical: spacing.md,
    marginBottom: spacing.xs, flexDirection: 'row',
    justifyContent: 'space-between', alignItems: 'center',
  },
  rowLabel: { color: colors.textSecondary, fontSize: fontSizes.sm },
  rowValue: { color: colors.textPrimary, fontSize: fontSizes.sm },
  rowValueEditable: { color: colors.cta, fontSize: fontSizes.sm, fontWeight: 'bold' },
  tierBadge: { color: colors.cta, fontWeight: 'bold', textTransform: 'uppercase', fontSize: fontSizes.xs },
  editNameRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
  nameInput: {
    color: colors.textPrimary, fontSize: fontSizes.sm,
    backgroundColor: colors.background, borderRadius: radius.sm,
    paddingHorizontal: spacing.sm, paddingVertical: spacing.xs,
    minWidth: 120,
  },
  saveLink: { color: colors.cta, fontSize: 18, fontWeight: 'bold' },
  cancelLink: { color: colors.textSecondary, fontSize: 16 },
  arrow: { color: colors.textSecondary, fontSize: fontSizes.xs },
  notifContent: { marginBottom: spacing.sm },
  prefRow: {
    flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center',
    backgroundColor: colors.surface, borderRadius: radius.md,
    paddingHorizontal: spacing.md, paddingVertical: spacing.sm, marginBottom: spacing.xs,
  },
  prefLabel: { color: colors.textPrimary, fontSize: fontSizes.sm, flex: 1, marginRight: spacing.md },
  deleteButton: {
    paddingVertical: spacing.sm, alignItems: 'center', marginTop: spacing.xl,
  },
  deleteText: { color: colors.error, fontSize: fontSizes.xs },
  logoutButton: {
    paddingVertical: spacing.md, alignItems: 'center', marginTop: spacing.md,
  },
  logoutText: { color: colors.textSecondary, fontSize: fontSizes.sm },
});
