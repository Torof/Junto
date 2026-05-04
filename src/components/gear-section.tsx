import { useState, useMemo, forwardRef, useImperativeHandle } from 'react';
import { View, Text, TextInput, Pressable, Modal, ScrollView, StyleSheet, KeyboardAvoidingView, Platform } from 'react-native';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import { Plus, Minus } from 'lucide-react-native';
import * as Burnt from 'burnt';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { gearService } from '@/services/gear-service';

interface Props {
  activityId: string;
  currentUserId: string | null;
  isParticipant: boolean;
}

// Modal-only host: the dense "Voir tous les détails" gear surface
// (catalog list, missing/covered split, status, warning card) was
// pruned alongside the rest of the legacy organization view. The
// component now just holds the two editor modals — per-item edit
// (Save / Remove) and custom-item add — exposed via imperative refs
// the cards drive. No catalog dependency, no quotas, no per-person
// logic; matches the simplified gear philosophy.
export interface GearSectionHandle {
  openItemByName: (name: string) => void;
  openCustomSheet: () => void;
}

export const GearSection = forwardRef<GearSectionHandle, Props>(function GearSection({ activityId, currentUserId, isParticipant }, ref) {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const queryClient = useQueryClient();

  // Per-item modal state — opened either by name (Mine's chip tap or
  // Mon matériel sheet's row tap). Quantity stepper defaults to the
  // user's existing quantity for that item, or 1 if not yet brought.
  const [selectedItemName, setSelectedItemName] = useState<string | null>(null);
  const [myQtyDraft, setMyQtyDraft] = useState(1);
  const [isSavingItem, setIsSavingItem] = useState(false);

  // Custom-item modal state — opened by Mine's "+ Ajouter du matériel"
  // button. User types a free-form name + quantity.
  const [showCustomSheet, setShowCustomSheet] = useState(false);
  const [customName, setCustomName] = useState('');
  const [customQty, setCustomQty] = useState(1);

  const { data: activityGear } = useQuery({
    queryKey: ['activity-gear', activityId],
    queryFn: () => gearService.getForActivity(activityId),
  });

  const myCurrentQtyFor = (itemName: string): number => {
    const entry = (activityGear ?? []).find(
      (g) => g.gear_name === itemName && g.user_id === currentUserId,
    );
    return entry?.quantity ?? 0;
  };

  const myOriginalQty = selectedItemName ? myCurrentQtyFor(selectedItemName) : 0;
  const iAlreadyBring = myOriginalQty > 0;

  useImperativeHandle(ref, () => ({
    openItemByName: (name: string) => {
      const mine = (activityGear ?? []).find(
        (g) => g.gear_name === name && g.user_id === currentUserId,
      )?.quantity ?? 0;
      setMyQtyDraft(mine > 0 ? mine : 1);
      setSelectedItemName(name);
    },
    openCustomSheet: () => {
      setCustomName('');
      setCustomQty(1);
      setShowCustomSheet(true);
    },
  }), [activityGear, currentUserId]);

  // Drives both Save and Remove on the per-item modal — sets the user's
  // gear to the transformed list and invalidates the cache.
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

  return (
    <>
      {/* Per-item modal — edit my quantity for an existing item, or
          remove it from my contributions. */}
      <Modal
        visible={selectedItemName !== null}
        animationType="fade"
        transparent
        onRequestClose={() => setSelectedItemName(null)}
      >
        <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
          <Pressable style={styles.backdrop} onPress={() => setSelectedItemName(null)}>
            <Pressable style={styles.sheet} onPress={() => {}}>
              <ScrollView keyboardShouldPersistTaps="handled" showsVerticalScrollIndicator={false}>
                {selectedItemName && (
                  <>
                    <Text style={styles.sheetTitle}>{selectedItemName}</Text>

                    {isParticipant && (
                      <>
                        <Text style={styles.sheetSectionLabel}>
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
              </ScrollView>
            </Pressable>
          </Pressable>
        </KeyboardAvoidingView>
      </Modal>

      {/* Custom-item modal — name + qty. Used by Mine's "+ Ajouter du
          matériel" button to declare a free-form gear item. */}
      <Modal
        visible={showCustomSheet}
        animationType="fade"
        transparent
        onRequestClose={() => setShowCustomSheet(false)}
      >
        <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
          <Pressable style={styles.backdrop} onPress={() => setShowCustomSheet(false)}>
            <Pressable style={styles.sheet} onPress={() => {}}>
              <ScrollView keyboardShouldPersistTaps="handled" showsVerticalScrollIndicator={false}>
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
              </ScrollView>
            </Pressable>
          </Pressable>
        </KeyboardAvoidingView>
      </Modal>
    </>
  );
});

const createStyles = (colors: AppColors) => StyleSheet.create({
  backdrop: {
    flex: 1, backgroundColor: 'rgba(0,0,0,0.92)',
    alignItems: 'center', justifyContent: 'center',
    padding: spacing.lg,
  },
  sheet: {
    width: '100%', maxWidth: 380, maxHeight: '85%',
    backgroundColor: colors.background, borderRadius: radius.lg,
    borderWidth: 1, borderColor: colors.line,
    padding: spacing.lg,
  },
  sheetTitle: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: 'bold', marginBottom: spacing.xs },
  sheetSectionLabel: {
    color: colors.textSecondary, fontSize: fontSizes.xs - 1, fontWeight: 'bold',
    letterSpacing: 1.2, textTransform: 'uppercase',
    marginBottom: spacing.xs + 2,
    marginTop: spacing.md,
  },
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
