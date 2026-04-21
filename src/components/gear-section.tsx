import { useState, useMemo } from 'react';
import { View, Text, TextInput, Pressable, Modal, ScrollView, StyleSheet, KeyboardAvoidingView, Platform } from 'react-native';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import { Plus, Minus, X } from 'lucide-react-native';
import * as Burnt from 'burnt';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { gearService, type GearCatalogItem } from '@/services/gear-service';
import { UserAvatar } from './user-avatar';

interface Props {
  activityId: string;
  sportKey: string;
  currentUserId: string | null;
  isParticipant: boolean;
}

interface GearSelection {
  name: string;
  quantity: number;
}

export function GearSection({ activityId, sportKey, currentUserId, isParticipant }: Props) {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const queryClient = useQueryClient();
  const [showEditor, setShowEditor] = useState(false);
  const [selections, setSelections] = useState<GearSelection[]>([]);
  const [customText, setCustomText] = useState('');
  const [isSaving, setIsSaving] = useState(false);
  const [expandedUser, setExpandedUser] = useState<string | null>(null);

  const { data: activityGear } = useQuery({
    queryKey: ['activity-gear', activityId],
    queryFn: () => gearService.getForActivity(activityId),
  });

  const { data: catalog } = useQuery({
    queryKey: ['gear-catalog', sportKey],
    queryFn: () => gearService.getCatalog(sportKey),
    enabled: showEditor,
  });

  const summary = useMemo(() => {
    const map = new Map<string, number>();
    (activityGear ?? []).forEach((g) => {
      map.set(g.gear_name, (map.get(g.gear_name) ?? 0) + g.quantity);
    });
    return [...map.entries()].sort((a, b) => a[0].localeCompare(b[0]));
  }, [activityGear]);

  const byUser = useMemo(() => {
    const map = new Map<string, { display_name: string; avatar_url: string | null; items: { name: string; quantity: number }[] }>();
    (activityGear ?? []).forEach((g) => {
      if (!map.has(g.user_id)) {
        map.set(g.user_id, { display_name: g.display_name, avatar_url: g.avatar_url, items: [] });
      }
      map.get(g.user_id)!.items.push({ name: g.gear_name, quantity: g.quantity });
    });
    return [...map.values()];
  }, [activityGear]);

  const openEditor = () => {
    const myGear = (activityGear ?? []).filter((g) => g.user_id === currentUserId);
    if (myGear.length > 0) {
      setSelections(myGear.map((g) => ({ name: g.gear_name, quantity: g.quantity })));
    } else {
      setSelections([]);
    }
    setCustomText('');
    setShowEditor(true);
  };

  const toggleCatalogItem = (item: GearCatalogItem) => {
    setSelections((prev) => {
      const existing = prev.find((s) => s.name === item.name_key);
      if (existing) return prev.filter((s) => s.name !== item.name_key);
      return [...prev, { name: item.name_key, quantity: 1 }];
    });
  };

  const updateQuantity = (name: string, delta: number) => {
    setSelections((prev) =>
      prev.map((s) => s.name === name ? { ...s, quantity: Math.max(1, Math.min(99, s.quantity + delta)) } : s),
    );
  };

  const removeItem = (name: string) => {
    setSelections((prev) => prev.filter((s) => s.name !== name));
  };

  const addCustom = () => {
    const name = customText.trim();
    if (!name || selections.some((s) => s.name === name)) return;
    setSelections((prev) => [...prev, { name, quantity: 1 }]);
    setCustomText('');
  };

  const handleSave = async () => {
    setIsSaving(true);
    try {
      await gearService.setGear(activityId, selections);
      await queryClient.invalidateQueries({ queryKey: ['activity-gear', activityId] });
      setShowEditor(false);
      Burnt.toast({ title: t('gear.saved'), preset: 'done' });
    } catch {
      Burnt.toast({ title: t('auth.unknownError') });
    } finally {
      setIsSaving(false);
    }
  };

  const hasMyGear = (activityGear ?? []).some((g) => g.user_id === currentUserId);

  return (
    <View style={styles.section}>
      <View style={styles.headerRow}>
        <Text style={styles.sectionTitle}>{t('activity.gear')}</Text>
        {isParticipant && (
          <Pressable onPress={openEditor}>
            <Text style={styles.editLink}>
              {hasMyGear ? t('transport.edit') : t('transport.add')}
            </Text>
          </Pressable>
        )}
      </View>

      {summary.length === 0 ? (
        isParticipant ? (
          <Pressable onPress={openEditor}>
            <Text style={styles.emptyText}>{t('gear.empty')}</Text>
          </Pressable>
        ) : (
          <Text style={styles.emptyText}>{t('gear.empty')}</Text>
        )
      ) : (
        <>
          <View style={styles.summaryBox}>
            {summary.map(([name, qty]) => (
              <View key={name} style={styles.summaryRow}>
                <Text style={styles.summaryName}>{name}</Text>
                <Text style={styles.summaryQty}>×{qty}</Text>
              </View>
            ))}
          </View>

          {byUser.length > 0 && (
            <View style={styles.byUserBox}>
              {byUser.map((user) => {
                const isExpanded = expandedUser === user.display_name;
                const itemsText = user.items.map((i) => i.quantity > 1 ? `${i.name} ×${i.quantity}` : i.name).join(', ');
                return (
                  <Pressable
                    key={user.display_name}
                    onPress={() => setExpandedUser(isExpanded ? null : user.display_name)}
                  >
                    <View style={styles.userRow}>
                      <UserAvatar name={user.display_name} avatarUrl={user.avatar_url} size={24} />
                      <Text style={styles.userName} numberOfLines={1}>{user.display_name}</Text>
                      <Text style={styles.userGear} numberOfLines={isExpanded ? undefined : 1}>
                        {itemsText}
                      </Text>
                    </View>
                  </Pressable>
                );
              })}
            </View>
          )}
        </>
      )}

      <Modal visible={showEditor} animationType="slide" transparent>
        <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : 'height'}>
          <Pressable style={styles.backdrop} onPress={() => setShowEditor(false)}>
            <ScrollView contentContainerStyle={{ flexGrow: 1, justifyContent: 'flex-end' }} keyboardShouldPersistTaps="handled">
              <Pressable style={styles.sheet} onPress={() => {}}>
                <View style={styles.handle} />
                <Text style={styles.sheetTitle}>{t('gear.whatAreYouBringing')}</Text>

                {(catalog ?? []).length > 0 && (
                  <View style={styles.catalogGrid}>
                    {(catalog ?? []).map((item) => {
                      const isSelected = selections.some((s) => s.name === item.name_key);
                      return (
                        <Pressable
                          key={item.id}
                          style={[styles.catalogChip, isSelected && styles.catalogChipActive]}
                          onPress={() => toggleCatalogItem(item)}
                        >
                          <Text style={[styles.catalogChipText, isSelected && styles.catalogChipTextActive]}>
                            {item.name_key}
                          </Text>
                        </Pressable>
                      );
                    })}
                  </View>
                )}

                {selections.length > 0 && (
                  <View style={styles.selectedList}>
                    {selections.map((sel) => (
                      <View key={sel.name} style={styles.selectedRow}>
                        <Text style={styles.selectedName} numberOfLines={1}>{sel.name}</Text>
                        <View style={styles.qtyRow}>
                          <Pressable onPress={() => updateQuantity(sel.name, -1)} hitSlop={8}>
                            <Minus size={16} color={colors.textSecondary} strokeWidth={2} />
                          </Pressable>
                          <Text style={styles.qtyText}>{sel.quantity}</Text>
                          <Pressable onPress={() => updateQuantity(sel.name, 1)} hitSlop={8}>
                            <Plus size={16} color={colors.textSecondary} strokeWidth={2} />
                          </Pressable>
                        </View>
                        <Pressable onPress={() => removeItem(sel.name)} hitSlop={8}>
                          <X size={16} color={colors.error} strokeWidth={2} />
                        </Pressable>
                      </View>
                    ))}
                  </View>
                )}

                <View style={styles.customRow}>
                  <TextInput
                    style={styles.customInput}
                    value={customText}
                    onChangeText={setCustomText}
                    placeholder={t('gear.customPlaceholder')}
                    placeholderTextColor={colors.textSecondary}
                    maxLength={100}
                    onSubmitEditing={addCustom}
                    returnKeyType="done"
                  />
                  <Pressable style={styles.addCustomBtn} onPress={addCustom}>
                    <Plus size={18} color={colors.textPrimary} strokeWidth={2.5} />
                  </Pressable>
                </View>

                <Pressable
                  style={[styles.saveButton, isSaving && { opacity: 0.4 }]}
                  onPress={handleSave}
                  disabled={isSaving}
                >
                  <Text style={styles.saveText}>{t('profil.save')}</Text>
                </Pressable>
              </Pressable>
            </ScrollView>
          </Pressable>
        </KeyboardAvoidingView>
      </Modal>
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  section: { marginBottom: spacing.lg },
  headerRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: spacing.sm },
  sectionTitle: {
    color: colors.textSecondary, fontSize: fontSizes.xs, fontWeight: 'bold',
    letterSpacing: 0.8, textTransform: 'uppercase',
  },
  editLink: { color: colors.cta, fontSize: fontSizes.xs, fontWeight: '600' },
  emptyText: { color: colors.textSecondary, fontSize: fontSizes.sm, fontStyle: 'italic' },

  summaryBox: {
    backgroundColor: colors.surface, borderRadius: radius.md, padding: spacing.md, gap: spacing.xs,
    marginBottom: spacing.sm,
  },
  summaryRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  summaryName: { color: colors.textPrimary, fontSize: fontSizes.sm },
  summaryQty: { color: colors.cta, fontSize: fontSizes.sm, fontWeight: 'bold' },

  byUserBox: { gap: spacing.xs },
  userRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, paddingVertical: spacing.xs },
  userName: { color: colors.textPrimary, fontSize: fontSizes.xs, fontWeight: 'bold', width: 70 },
  userGear: { color: colors.textSecondary, fontSize: fontSizes.xs, flex: 1 },

  backdrop: { flex: 1, backgroundColor: colors.overlay, justifyContent: 'flex-end' },
  sheet: {
    backgroundColor: colors.background, borderTopLeftRadius: radius.lg, borderTopRightRadius: radius.lg,
    padding: spacing.lg, paddingBottom: spacing.xl + 16,
  },
  handle: { width: 40, height: 4, borderRadius: 2, backgroundColor: colors.textSecondary, alignSelf: 'center', marginBottom: spacing.lg, opacity: 0.4 },
  sheetTitle: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: 'bold', marginBottom: spacing.md },

  catalogGrid: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.xs, marginBottom: spacing.md },
  catalogChip: {
    backgroundColor: colors.surface, borderRadius: radius.full,
    paddingHorizontal: spacing.sm, paddingVertical: spacing.xs,
  },
  catalogChipActive: { backgroundColor: colors.cta },
  catalogChipText: { color: colors.textSecondary, fontSize: fontSizes.xs },
  catalogChipTextActive: { color: colors.textPrimary, fontWeight: 'bold' },

  selectedList: { marginBottom: spacing.md, gap: spacing.xs },
  selectedRow: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.sm,
    backgroundColor: colors.surface, borderRadius: radius.md,
    paddingHorizontal: spacing.md, paddingVertical: spacing.sm,
  },
  selectedName: { color: colors.textPrimary, fontSize: fontSizes.sm, flex: 1 },
  qtyRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
  qtyText: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: 'bold', minWidth: 20, textAlign: 'center' },

  customRow: { flexDirection: 'row', gap: spacing.xs, marginBottom: spacing.md },
  customInput: {
    flex: 1, backgroundColor: colors.surface, color: colors.textPrimary,
    borderRadius: radius.md, paddingHorizontal: spacing.md, paddingVertical: spacing.sm,
    fontSize: fontSizes.sm,
  },
  addCustomBtn: {
    width: 40, height: 40, borderRadius: radius.md,
    backgroundColor: colors.surface, alignItems: 'center', justifyContent: 'center',
  },

  saveButton: {
    backgroundColor: colors.cta, borderRadius: radius.md,
    paddingVertical: spacing.md, alignItems: 'center', marginTop: spacing.sm,
  },
  saveText: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: 'bold' },
});
