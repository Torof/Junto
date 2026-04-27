import { useState, useMemo } from 'react';
import { View, Text, TextInput, Pressable, Modal, ScrollView, StyleSheet, KeyboardAvoidingView, Platform } from 'react-native';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import { Plus, Minus, AlertCircle, Check } from 'lucide-react-native';
import * as Burnt from 'burnt';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { gearService, type GearCategoryKey } from '@/services/gear-service';
import { participationService } from '@/services/participation-service';
import { UserAvatar } from './user-avatar';

interface Props {
  activityId: string;
  sportKey: string;
  currentUserId: string | null;
  isParticipant: boolean;
  participantCount: number;
}

type CategoryKey = GearCategoryKey | 'custom';

const CATEGORY_COLORS: Record<CategoryKey, string> = {
  safety: '#E5524E',
  technical: '#F4A373',
  water: '#4B7CB8',
  personal: '#7EC8A3',
  custom: '#8A95AB',
};

const CATEGORY_ORDER: CategoryKey[] = ['safety', 'technical', 'water', 'personal', 'custom'];

interface Bringer {
  user_id: string;
  display_name: string;
  avatar_url: string | null;
  quantity: number;
}

interface ItemView {
  name: string;
  category: CategoryKey;
  display_order: number;
  isCatalog: boolean;
  have: number;
  required: number;
  covered: boolean;
  bringers: Bringer[];
}

export function GearSection({ activityId, sportKey, currentUserId, isParticipant, participantCount }: Props) {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const queryClient = useQueryClient();

  const [selectedItemName, setSelectedItemName] = useState<string | null>(null);
  const [myQtyDraft, setMyQtyDraft] = useState(1);
  const [isSavingItem, setIsSavingItem] = useState(false);

  const [showCustomSheet, setShowCustomSheet] = useState(false);
  const [customName, setCustomName] = useState('');
  const [customQty, setCustomQty] = useState(1);

  const { data: activityGear } = useQuery({
    queryKey: ['activity-gear', activityId],
    queryFn: () => gearService.getForActivity(activityId),
  });

  const { data: catalog } = useQuery({
    queryKey: ['gear-catalog', sportKey],
    queryFn: () => gearService.getCatalog(sportKey),
  });

  // Shared queryKey with the participant list — TanStack dedupes the fetch.
  const { data: participantsForPresence } = useQuery({
    queryKey: ['participants', activityId],
    queryFn: () => participationService.getForActivity(activityId),
    staleTime: 15_000,
  });

  const confirmedUserIds = useMemo(
    () => new Set((participantsForPresence ?? []).filter((p) => p.confirmed_present === true).map((p) => p.user_id)),
    [participantsForPresence],
  );

  const { grouped, checkedCatalog, totalCatalog, missingCount, items } = useMemo(() => {
    const itemMap = new Map<string, ItemView>();
    (catalog ?? []).forEach((c) => {
      const required = c.per_person ? participantCount : (c.shared_recommended_qty ?? 1);
      itemMap.set(c.name_key, {
        name: c.name_key,
        category: c.category_key,
        display_order: c.display_order,
        isCatalog: true,
        have: 0,
        required,
        covered: false,
        bringers: [],
      });
    });
    (activityGear ?? []).forEach((g) => {
      const existing = itemMap.get(g.gear_name);
      if (existing) {
        existing.have += g.quantity;
        existing.bringers.push({
          user_id: g.user_id,
          display_name: g.display_name,
          avatar_url: g.avatar_url,
          quantity: g.quantity,
        });
      } else {
        itemMap.set(g.gear_name, {
          name: g.gear_name,
          category: 'custom',
          display_order: 999,
          isCatalog: false,
          have: g.quantity,
          required: 0,
          covered: true,
          bringers: [{
            user_id: g.user_id,
            display_name: g.display_name,
            avatar_url: g.avatar_url,
            quantity: g.quantity,
          }],
        });
      }
    });
    itemMap.forEach((item) => {
      item.covered = item.isCatalog ? item.have >= item.required : true;
    });

    const groupsMap = new Map<CategoryKey, ItemView[]>();
    itemMap.forEach((item) => {
      if (!groupsMap.has(item.category)) groupsMap.set(item.category, []);
      groupsMap.get(item.category)!.push(item);
    });
    groupsMap.forEach((g) => g.sort((a, b) => a.display_order - b.display_order));

    const orderedGroups = CATEGORY_ORDER
      .map((key) => ({ key, items: groupsMap.get(key) ?? [] }))
      .filter((g) => g.items.length > 0);

    const catalogItems = Array.from(itemMap.values()).filter((i) => i.isCatalog);
    const checkedCat = catalogItems.filter((i) => i.covered).length;
    const missing = catalogItems.filter((i) => !i.covered).length;

    return {
      grouped: orderedGroups,
      checkedCatalog: checkedCat,
      totalCatalog: catalogItems.length,
      missingCount: missing,
      items: itemMap,
    };
  }, [catalog, activityGear, participantCount]);

  const progressRatio = totalCatalog === 0 ? 0 : checkedCatalog / totalCatalog;
  const selectedItem = selectedItemName ? items.get(selectedItemName) ?? null : null;

  const myCurrentQtyFor = (itemName: string): number => {
    const entry = (activityGear ?? []).find(
      (g) => g.gear_name === itemName && g.user_id === currentUserId,
    );
    return entry?.quantity ?? 0;
  };

  const openItemSheet = (item: ItemView) => {
    const mine = myCurrentQtyFor(item.name);
    setMyQtyDraft(mine > 0 ? mine : 1);
    setSelectedItemName(item.name);
  };

  const persistMyGear = async (transform: (existing: { name: string; quantity: number }[]) => { name: string; quantity: number }[]) => {
    const mine = (activityGear ?? [])
      .filter((g) => g.user_id === currentUserId)
      .map((g) => ({ name: g.gear_name, quantity: g.quantity }));
    const next = transform(mine);
    await gearService.setGear(activityId, next);
    await queryClient.invalidateQueries({ queryKey: ['activity-gear', activityId] });
  };

  const saveMyContribution = async () => {
    if (!selectedItemName) return;
    setIsSavingItem(true);
    try {
      await persistMyGear((mine) => {
        const filtered = mine.filter((m) => m.name !== selectedItemName);
        if (myQtyDraft > 0) filtered.push({ name: selectedItemName, quantity: myQtyDraft });
        return filtered;
      });
      setSelectedItemName(null);
      Burnt.toast({ title: t('gear.saved'), preset: 'done' });
    } catch {
      Burnt.toast({ title: t('auth.unknownError') });
    } finally {
      setIsSavingItem(false);
    }
  };

  const removeMyContribution = async () => {
    if (!selectedItemName) return;
    setIsSavingItem(true);
    try {
      await persistMyGear((mine) => mine.filter((m) => m.name !== selectedItemName));
      setSelectedItemName(null);
      Burnt.toast({ title: t('gear.saved'), preset: 'done' });
    } catch {
      Burnt.toast({ title: t('auth.unknownError') });
    } finally {
      setIsSavingItem(false);
    }
  };

  const addCustomItem = async () => {
    const name = customName.trim();
    if (!name) return;
    setIsSavingItem(true);
    try {
      await persistMyGear((mine) => {
        if (mine.some((m) => m.name === name)) {
          return mine.map((m) => m.name === name ? { ...m, quantity: customQty } : m);
        }
        return [...mine, { name, quantity: customQty }];
      });
      setShowCustomSheet(false);
      setCustomName('');
      setCustomQty(1);
      Burnt.toast({ title: t('gear.saved'), preset: 'done' });
    } catch {
      Burnt.toast({ title: t('auth.unknownError') });
    } finally {
      setIsSavingItem(false);
    }
  };

  const myDraftIsBringing = myQtyDraft > 0;
  const myOriginalQty = selectedItemName ? myCurrentQtyFor(selectedItemName) : 0;
  const iAlreadyBring = myOriginalQty > 0;

  const itemStatusLabel = (item: ItemView): string => {
    if (!item.isCatalog) return t('gear.itemSheetStatusCustom');
    if (item.have === 0) return t('gear.itemSheetStatusMissing', { required: item.required });
    if (item.have < item.required) return t('gear.itemSheetStatusPartial', { have: item.have, required: item.required });
    if (item.have === item.required) return t('gear.itemSheetStatusCovered', { have: item.have, required: item.required });
    return t('gear.itemSheetStatusExtra', { have: item.have });
  };

  const itemStatusColor = (item: ItemView): string => {
    if (!item.isCatalog) return colors.success;
    if (item.have === 0) return colors.error;
    if (item.have < item.required) return colors.cta;
    return colors.success;
  };

  const isEmpty = grouped.length === 0;

  return (
    <View style={styles.section}>
      {totalCatalog > 0 && (
        <>
          <Text style={styles.coveredLabel}>
            {t('gear.covered', { checked: checkedCatalog, total: totalCatalog, count: checkedCatalog })}
          </Text>
          <View style={styles.progressTrack}>
            <View style={[styles.progressFill, { width: `${progressRatio * 100}%` }]} />
          </View>
        </>
      )}

      {missingCount > 0 && (
        <View style={styles.warningCard}>
          <View style={styles.warningIconBox}>
            <AlertCircle size={14} color={colors.error} strokeWidth={2.5} />
          </View>
          <Text style={styles.warningText}>
            {t('gear.missingWarning', { count: missingCount })}
          </Text>
        </View>
      )}

      {isEmpty ? (
        <Text style={styles.emptyText}>{t('gear.empty')}</Text>
      ) : (
        grouped.map((group) => (
          <View key={group.key} style={styles.groupBlock}>
            <View style={styles.groupHeader}>
              <View style={[styles.groupDot, { backgroundColor: CATEGORY_COLORS[group.key] }]} />
              <Text style={styles.groupTitle}>{t(`gear.category.${group.key}`)}</Text>
              <Text style={styles.groupCount}>
                {group.items.filter((i) => i.covered).length}/{group.items.length}
              </Text>
            </View>
            <View style={styles.groupCard}>
              {group.items.map((item, idx) => (
                <ItemRow
                  key={item.name}
                  item={item}
                  isLast={idx === group.items.length - 1}
                  confirmedUserIds={confirmedUserIds}
                  onPress={() => openItemSheet(item)}
                  styles={styles}
                  colors={colors}
                  t={t}
                />
              ))}
            </View>
          </View>
        ))
      )}

      {isParticipant && (
        <Pressable onPress={() => { setCustomName(''); setCustomQty(1); setShowCustomSheet(true); }} style={styles.addCustomBtn}>
          <Text style={styles.addCustomText}>{t('gear.addCustom')}</Text>
        </Pressable>
      )}

      {/* Per-item sheet */}
      <Modal
        visible={selectedItem !== null}
        animationType="slide"
        transparent
        onRequestClose={() => setSelectedItemName(null)}
      >
        <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : 'height'}>
          <Pressable style={styles.backdrop} onPress={() => setSelectedItemName(null)}>
            <ScrollView contentContainerStyle={{ flexGrow: 1, justifyContent: 'flex-end' }} keyboardShouldPersistTaps="handled">
              <Pressable style={styles.sheet} onPress={() => {}}>
                <View style={styles.handle} />
                {selectedItem && (
                  <>
                    <Text style={styles.sheetTitle}>{selectedItem.name}</Text>
                    <Text style={[styles.sheetStatus, { color: itemStatusColor(selectedItem) }]}>
                      {itemStatusLabel(selectedItem)}
                    </Text>

                    <Text style={styles.sheetSectionLabel}>
                      {selectedItem.bringers.length === 0
                        ? t('gear.itemSheetNoBringers')
                        : t('gear.itemSheetBringers')}
                    </Text>
                    {selectedItem.bringers.length > 0 && (
                      <View style={styles.bringersList}>
                        {selectedItem.bringers.map((b) => (
                          <View key={b.user_id} style={styles.bringerRowSheet}>
                            <UserAvatar name={b.display_name} avatarUrl={b.avatar_url} size={24} confirmedPresent={confirmedUserIds.has(b.user_id)} />
                            <Text style={styles.bringerNameSheet} numberOfLines={1}>{b.display_name}</Text>
                            <Text style={styles.bringerQtySheet}>×{b.quantity}</Text>
                          </View>
                        ))}
                      </View>
                    )}

                    {isParticipant && (
                      <>
                        <Text style={[styles.sheetSectionLabel, { marginTop: spacing.md }]}>
                          {t('gear.itemSheetMyContribution')}
                        </Text>
                        <View style={styles.myContribRow}>
                          <Pressable
                            onPress={() => setMyQtyDraft(Math.max(0, myQtyDraft - 1))}
                            style={styles.qtyBtn}
                            hitSlop={8}
                          >
                            <Minus size={18} color={colors.textPrimary} strokeWidth={2.5} />
                          </Pressable>
                          <Text style={styles.qtyValue}>{myQtyDraft}</Text>
                          <Pressable
                            onPress={() => setMyQtyDraft(Math.min(99, myQtyDraft + 1))}
                            style={styles.qtyBtn}
                            hitSlop={8}
                          >
                            <Plus size={18} color={colors.textPrimary} strokeWidth={2.5} />
                          </Pressable>
                        </View>

                        <View style={styles.sheetActions}>
                          {iAlreadyBring && (
                            <Pressable
                              style={[styles.removeBtn, isSavingItem && { opacity: 0.4 }]}
                              onPress={removeMyContribution}
                              disabled={isSavingItem}
                            >
                              <Text style={styles.removeBtnText}>{t('gear.remove')}</Text>
                            </Pressable>
                          )}
                          <Pressable
                            style={[styles.saveBtn, (isSavingItem || !myDraftIsBringing) && { opacity: 0.4 }]}
                            onPress={saveMyContribution}
                            disabled={isSavingItem || !myDraftIsBringing}
                          >
                            <Text style={styles.saveBtnText}>
                              {iAlreadyBring ? t('profil.save') : t('gear.iBringThis')}
                            </Text>
                          </Pressable>
                        </View>
                      </>
                    )}
                  </>
                )}
              </Pressable>
            </ScrollView>
          </Pressable>
        </KeyboardAvoidingView>
      </Modal>

      {/* Custom item sheet */}
      <Modal
        visible={showCustomSheet}
        animationType="slide"
        transparent
        onRequestClose={() => setShowCustomSheet(false)}
      >
        <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : 'height'}>
          <Pressable style={styles.backdrop} onPress={() => setShowCustomSheet(false)}>
            <ScrollView contentContainerStyle={{ flexGrow: 1, justifyContent: 'flex-end' }} keyboardShouldPersistTaps="handled">
              <Pressable style={styles.sheet} onPress={() => {}}>
                <View style={styles.handle} />
                <Text style={styles.sheetTitle}>{t('gear.customSheetTitle')}</Text>

                <View style={styles.fieldBox}>
                  <Text style={styles.fieldLabel}>{t('gear.customSheetNameLabel')}</Text>
                  <TextInput
                    style={styles.fieldInput}
                    value={customName}
                    onChangeText={setCustomName}
                    placeholder={t('gear.customPlaceholder')}
                    placeholderTextColor={colors.textSecondary}
                    maxLength={100}
                  />
                </View>

                <View style={styles.fieldBoxRow}>
                  <Text style={styles.fieldLabel}>{t('gear.customSheetQtyLabel')}</Text>
                  <View style={styles.myContribRow}>
                    <Pressable
                      onPress={() => setCustomQty(Math.max(1, customQty - 1))}
                      style={styles.qtyBtn}
                      hitSlop={8}
                    >
                      <Minus size={18} color={colors.textPrimary} strokeWidth={2.5} />
                    </Pressable>
                    <Text style={styles.qtyValue}>{customQty}</Text>
                    <Pressable
                      onPress={() => setCustomQty(Math.min(99, customQty + 1))}
                      style={styles.qtyBtn}
                      hitSlop={8}
                    >
                      <Plus size={18} color={colors.textPrimary} strokeWidth={2.5} />
                    </Pressable>
                  </View>
                </View>

                <Pressable
                  style={[styles.saveBtn, (isSavingItem || !customName.trim()) && { opacity: 0.4 }]}
                  onPress={addCustomItem}
                  disabled={isSavingItem || !customName.trim()}
                >
                  <Text style={styles.saveBtnText}>{t('profil.save')}</Text>
                </Pressable>
              </Pressable>
            </ScrollView>
          </Pressable>
        </KeyboardAvoidingView>
      </Modal>
    </View>
  );
}

interface ItemRowProps {
  item: ItemView;
  isLast: boolean;
  confirmedUserIds: Set<string>;
  onPress: () => void;
  colors: AppColors;
  styles: ReturnType<typeof createStyles>;
  t: (k: string, opts?: Record<string, unknown>) => string;
}

function ItemRow({ item, isLast, confirmedUserIds, onPress, colors, styles, t }: ItemRowProps) {
  const firstBringer = item.bringers[0];
  const extraBringers = item.bringers.length - 1;

  const qtyLabel =
    !item.isCatalog ? `×${item.have}` :
    item.have === 0 ? `0/${item.required}` :
    item.covered ? `×${item.have}` :
    `${item.have}/${item.required}`;

  const qtyColor =
    !item.isCatalog ? colors.success :
    item.have === 0 ? colors.error :
    item.covered ? colors.success :
    colors.cta;

  return (
    <Pressable onPress={onPress} style={[styles.itemRow, !isLast && styles.itemRowBorder]}>
      <View style={[styles.checkbox, item.covered ? styles.checkboxChecked : styles.checkboxEmpty]}>
        {item.covered && <Check size={12} color="#FFFFFF" strokeWidth={3.5} />}
      </View>
      <View style={{ flex: 1, minWidth: 0 }}>
        <Text
          style={[styles.itemName, item.covered && styles.itemNameCovered]}
          numberOfLines={1}
        >
          {item.name}
        </Text>
        {item.bringers.length > 0 && firstBringer && (
          <View style={styles.bringerRow}>
            <UserAvatar name={firstBringer.display_name} avatarUrl={firstBringer.avatar_url} size={14} confirmedPresent={confirmedUserIds.has(firstBringer.user_id)} />
            <Text style={styles.bringerText} numberOfLines={1}>
              {t('gear.broughtBy')} <Text style={styles.bringerName}>{firstBringer.display_name}</Text>
              {extraBringers > 0 && <Text style={styles.bringerExtra}> +{extraBringers}</Text>}
            </Text>
          </View>
        )}
      </View>
      <Text style={[styles.qty, { color: qtyColor }]}>{qtyLabel}</Text>
    </Pressable>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  section: { marginBottom: spacing.lg },

  coveredLabel: {
    color: colors.textSecondary, fontSize: fontSizes.xs - 2, fontWeight: 'bold',
    letterSpacing: 1.4, textTransform: 'uppercase',
    marginBottom: spacing.xs + 2,
  },

  progressTrack: {
    height: 6, borderRadius: 999,
    backgroundColor: colors.surface,
    marginBottom: spacing.md,
    overflow: 'hidden',
  },
  progressFill: {
    height: '100%', borderRadius: 999,
    backgroundColor: colors.cta,
  },

  warningCard: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.sm,
    backgroundColor: colors.error + '14',
    borderWidth: 1, borderColor: colors.error + '40',
    borderRadius: radius.md,
    paddingHorizontal: spacing.sm + 2, paddingVertical: spacing.sm,
    marginBottom: spacing.md,
  },
  warningIconBox: {
    width: 28, height: 28, borderRadius: 8,
    backgroundColor: colors.error + '30',
    alignItems: 'center', justifyContent: 'center',
  },
  warningText: {
    flex: 1, color: colors.textPrimary,
    fontSize: fontSizes.xs + 1, fontWeight: '500',
  },

  emptyText: { color: colors.textSecondary, fontSize: fontSizes.sm, fontStyle: 'italic' },

  groupBlock: { marginBottom: spacing.md },
  groupHeader: { flexDirection: 'row', alignItems: 'center', gap: spacing.xs + 2, marginBottom: spacing.xs + 2 },
  groupDot: { width: 8, height: 8, borderRadius: 4 },
  groupTitle: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '700', letterSpacing: -0.2 },
  groupCount: { color: colors.textMuted, fontSize: fontSizes.xs - 1 },

  groupCard: {
    backgroundColor: colors.surface, borderRadius: radius.md,
    borderWidth: 1, borderColor: colors.line,
    paddingHorizontal: spacing.sm + 4,
  },

  itemRow: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.sm + 2,
    paddingVertical: spacing.sm,
  },
  itemRowBorder: { borderBottomWidth: 1, borderBottomColor: colors.line },

  checkbox: {
    width: 22, height: 22, borderRadius: 7,
    alignItems: 'center', justifyContent: 'center',
  },
  checkboxChecked: { backgroundColor: colors.cta, borderWidth: 1, borderColor: colors.cta },
  checkboxEmpty: { backgroundColor: 'transparent', borderWidth: 1.5, borderColor: colors.line },

  itemName: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '500' },
  itemNameCovered: {
    color: colors.textSecondary,
    textDecorationLine: 'line-through',
    textDecorationColor: colors.textMuted,
  },

  bringerRow: { flexDirection: 'row', alignItems: 'center', gap: 5, marginTop: 2 },
  bringerText: { color: colors.textMuted, fontSize: 11 },
  bringerName: { color: colors.cta, fontWeight: '600' },
  bringerExtra: { color: colors.textMuted, fontWeight: '500' },

  qty: { fontSize: fontSizes.sm, fontWeight: '700' },

  addCustomBtn: {
    marginTop: spacing.xs,
    paddingVertical: spacing.sm + 2,
    borderRadius: radius.md,
    borderWidth: 1, borderStyle: 'dashed', borderColor: colors.line,
    alignItems: 'center',
  },
  addCustomText: { color: colors.textSecondary, fontSize: fontSizes.xs + 1, fontWeight: '500' },

  // Sheet styles
  backdrop: { flex: 1, backgroundColor: colors.overlay, justifyContent: 'flex-end' },
  sheet: {
    backgroundColor: colors.background, borderTopLeftRadius: radius.lg, borderTopRightRadius: radius.lg,
    padding: spacing.lg, paddingBottom: spacing.xl + 16,
  },
  handle: { width: 40, height: 4, borderRadius: 2, backgroundColor: colors.textSecondary, alignSelf: 'center', marginBottom: spacing.lg, opacity: 0.4 },
  sheetTitle: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: 'bold', marginBottom: spacing.xs },
  sheetStatus: { fontSize: fontSizes.sm, fontWeight: '600', marginBottom: spacing.md },
  sheetSectionLabel: {
    color: colors.textSecondary, fontSize: fontSizes.xs - 1, fontWeight: 'bold',
    letterSpacing: 1.2, textTransform: 'uppercase',
    marginBottom: spacing.xs + 2,
  },

  bringersList: {
    backgroundColor: colors.surface, borderRadius: radius.md,
    paddingHorizontal: spacing.md, paddingVertical: spacing.xs,
  },
  bringerRowSheet: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.sm,
    paddingVertical: spacing.xs + 2,
  },
  bringerNameSheet: { color: colors.textPrimary, fontSize: fontSizes.sm, flex: 1 },
  bringerQtySheet: { color: colors.cta, fontSize: fontSizes.sm, fontWeight: '700' },

  myContribRow: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'center',
    gap: spacing.lg,
    backgroundColor: colors.surface, borderRadius: radius.md,
    paddingVertical: spacing.sm, paddingHorizontal: spacing.md,
    marginBottom: spacing.md,
  },
  qtyBtn: {
    width: 36, height: 36, borderRadius: radius.full,
    backgroundColor: colors.background,
    alignItems: 'center', justifyContent: 'center',
  },
  qtyValue: { color: colors.textPrimary, fontSize: fontSizes.xl, fontWeight: 'bold', minWidth: 40, textAlign: 'center' },

  sheetActions: { flexDirection: 'row', gap: spacing.sm },
  saveBtn: {
    flex: 1, height: 48, borderRadius: radius.md,
    backgroundColor: colors.cta,
    alignItems: 'center', justifyContent: 'center',
  },
  saveBtnText: { color: '#FFFFFF', fontSize: fontSizes.md, fontWeight: '700' },
  removeBtn: {
    height: 48, paddingHorizontal: spacing.lg, borderRadius: radius.md,
    borderWidth: 1, borderColor: colors.error,
    alignItems: 'center', justifyContent: 'center',
  },
  removeBtnText: { color: colors.error, fontSize: fontSizes.sm, fontWeight: '600' },

  fieldBox: {
    backgroundColor: colors.surface, borderRadius: radius.md,
    padding: spacing.md, marginBottom: spacing.md,
  },
  fieldBoxRow: {
    marginBottom: spacing.md,
  },
  fieldLabel: {
    color: colors.textSecondary, fontSize: fontSizes.xs, marginBottom: spacing.xs,
  },
  fieldInput: { color: colors.textPrimary, fontSize: fontSizes.md },
});
