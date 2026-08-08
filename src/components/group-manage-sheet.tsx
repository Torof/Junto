import { useEffect, useMemo, useState } from 'react';
import { View, Text, Modal, Pressable, TextInput, ScrollView, StyleSheet } from 'react-native';
import { useTranslation } from 'react-i18next';
import { useQueryClient } from '@tanstack/react-query';
import * as Burnt from 'burnt';
import { UserPlus, Check } from 'lucide-react-native';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { groupService, type GroupInfo } from '@/services/group-service';
import { getFriendlyError } from '@/utils/friendly-error';
import { UserAvatar } from './user-avatar';
import { InvitePartnersSheet } from './invite-partners-sheet';

interface Props {
  visible: boolean;
  conversationId: string;
  group: GroupInfo;
  onClose: () => void;
}

// Manage a group (Brique 4d-2): rename (name + emoji), see members, add members.
// Leaving lives in the header menu. MVP — no roles/admin (any member manages).
export function GroupManageSheet({ visible, conversationId, group, onClose }: Props) {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const queryClient = useQueryClient();

  const [name, setName] = useState(group.name);
  const [icon, setIcon] = useState(group.icon ?? '');
  const [saving, setSaving] = useState(false);
  const [addOpen, setAddOpen] = useState(false);

  useEffect(() => {
    if (visible) { setName(group.name); setIcon(group.icon ?? ''); }
  }, [visible, group.name, group.icon]);

  const dirty = name.trim() !== group.name || (icon.trim() || null) !== (group.icon ?? null);

  const refresh = async () => {
    await queryClient.invalidateQueries({ queryKey: ['group-info', conversationId] });
    await queryClient.invalidateQueries({ queryKey: ['conversations'] });
  };

  const handleRename = async () => {
    if (!dirty || !name.trim() || saving) return;
    setSaving(true);
    try {
      await groupService.rename(conversationId, name.trim(), icon.trim() || null);
      await refresh();
      Burnt.toast({ title: t('group.renamed', { defaultValue: 'Groupe mis à jour' }), preset: 'done' });
    } catch (e) {
      Burnt.toast({ title: getFriendlyError(e, 'generic') });
    } finally {
      setSaving(false);
    }
  };

  const handleAdd = async (ids: string[]) => {
    const existing = new Set(group.members.map((m) => m.id));
    const fresh = ids.filter((x) => !existing.has(x));
    if (fresh.length === 0) return;
    // Resilient: one add failing (e.g. a block rule) must not abort the rest.
    let added = 0;
    let lastErr: unknown = null;
    for (const uid of fresh) {
      try { await groupService.addMember(conversationId, uid); added++; }
      catch (e) { lastErr = e; }
    }
    await refresh();
    if (added > 0) Burnt.toast({ title: t('group.membersAdded', { defaultValue: 'Membres ajoutés' }), preset: 'done' });
    else if (lastErr) Burnt.toast({ title: getFriendlyError(lastErr, 'generic') });
  };

  return (
    <Modal visible={visible} animationType="slide" transparent onRequestClose={onClose}>
      <Pressable style={styles.backdrop} onPress={onClose}>
        <Pressable style={styles.sheet} onPress={() => {}}>
          <View style={styles.handle} />

          <View style={styles.nameRow}>
            <TextInput style={styles.iconInput} value={icon} onChangeText={setIcon} placeholder="🏔️" placeholderTextColor={colors.textSecondary} maxLength={8} />
            <TextInput style={styles.nameInput} value={name} onChangeText={setName} placeholder={t('group.namePlaceholder', { defaultValue: 'Nom du groupe' })} placeholderTextColor={colors.textSecondary} maxLength={60} />
            {dirty && (
              <Pressable style={[styles.saveBtn, saving && styles.disabled]} onPress={handleRename} disabled={saving}>
                <Check size={18} color="#FFFFFF" strokeWidth={3} />
              </Pressable>
            )}
          </View>

          <View style={styles.membersHeader}>
            <Text style={styles.section}>{t('group.membersSection', { defaultValue: 'Membres' })} · {group.members.length}</Text>
            <Pressable style={styles.addBtn} onPress={() => setAddOpen(true)} hitSlop={6}>
              <UserPlus size={16} color={colors.cta} strokeWidth={2.4} />
              <Text style={styles.addLabel}>{t('group.addMembers', { defaultValue: 'Ajouter' })}</Text>
            </Pressable>
          </View>

          <ScrollView style={styles.list}>
            {group.members.map((m) => (
              <View key={m.id} style={styles.row}>
                <UserAvatar name={m.display_name} avatarUrl={m.avatar_url} size={36} />
                <Text style={styles.memberName} numberOfLines={1}>{m.display_name}</Text>
              </View>
            ))}
          </ScrollView>
        </Pressable>
      </Pressable>

      <InvitePartnersSheet
        visible={addOpen}
        onConfirm={handleAdd}
        excludeIds={group.members.map((m) => m.id)}
        onClose={() => setAddOpen(false)}
      />
    </Modal>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  backdrop: { flex: 1, backgroundColor: colors.overlay, justifyContent: 'flex-end' },
  sheet: {
    backgroundColor: colors.background,
    borderTopLeftRadius: radius.lg, borderTopRightRadius: radius.lg,
    padding: spacing.lg, paddingBottom: spacing.xl + 16, maxHeight: '80%',
  },
  handle: { width: 40, height: 4, borderRadius: 2, backgroundColor: colors.textSecondary, alignSelf: 'center', marginBottom: spacing.lg, opacity: 0.4 },
  nameRow: { flexDirection: 'row', gap: spacing.sm, alignItems: 'center' },
  iconInput: {
    width: 52, textAlign: 'center', color: colors.textPrimary, fontSize: fontSizes.lg,
    borderWidth: 1, borderColor: colors.borderMuted, borderRadius: radius.sm, paddingVertical: spacing.sm,
  },
  nameInput: {
    flex: 1, color: colors.textPrimary, fontSize: fontSizes.md,
    borderWidth: 1, borderColor: colors.borderMuted, borderRadius: radius.sm,
    paddingHorizontal: spacing.md, paddingVertical: spacing.sm,
  },
  saveBtn: { width: 40, height: 40, borderRadius: radius.sm, backgroundColor: colors.cta, alignItems: 'center', justifyContent: 'center' },
  disabled: { opacity: 0.4 },
  membersHeader: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginTop: spacing.lg, marginBottom: spacing.xs },
  section: { color: colors.textSecondary, fontSize: fontSizes.xs, fontWeight: '800', letterSpacing: 0.8, textTransform: 'uppercase' },
  addBtn: { flexDirection: 'row', alignItems: 'center', gap: spacing.xs },
  addLabel: { color: colors.cta, fontSize: fontSizes.sm, fontWeight: '700' },
  list: { maxHeight: 360 },
  row: { flexDirection: 'row', alignItems: 'center', gap: spacing.md, paddingVertical: spacing.sm },
  memberName: { flex: 1, color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '600' },
});
