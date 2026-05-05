import { useState, useMemo, forwardRef, useImperativeHandle } from 'react';
import { View, Text, TextInput, Pressable, Modal, ScrollView, StyleSheet, KeyboardAvoidingView, Platform } from 'react-native';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import { Plus, Minus, ChevronDown, Check } from 'lucide-react-native';
import * as Burnt from 'burnt';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { gearService } from '@/services/gear-service';

interface Props {
  activityId: string;
  sportKey: string;
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
  // `fromRequest` flips the stepper default to `mine + 1` so tapping
  // save actually contributes one more (instead of resaving the same
  // qty for delta=0). When omitted / false, the stepper defaults to
  // the user's current qty (regular edit flow).
  openItemByName: (name: string, isShared?: boolean, fromRequest?: boolean) => void;
  openCustomSheet: () => void;
  // Personal vs group request — feeds is_shared on the new request row.
  openRequestSheet: (isShared: boolean) => void;
}

export const GearSection = forwardRef<GearSectionHandle, Props>(function GearSection({ activityId, sportKey, currentUserId, isParticipant }, ref) {
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

  // Custom-item modal state — same sheet shape for two flows:
  //   bring   → user adds to their own gear list (setGear path)
  //   request → user flags a missing item for the group
  //             (request_activity_gear RPC, no personal qty change)
  // Same UI to keep behaviour predictable; the title, save label,
  // and save handler swap based on mode.
  const [showCustomSheet, setShowCustomSheet] = useState(false);
  const [customSheetMode, setCustomSheetMode] = useState<'bring' | 'request'>('bring');
  const [customName, setCustomName] = useState('');
  const [customQty, setCustomQty] = useState(1);
  const [customIsShared, setCustomIsShared] = useState(false);
  const [catalogOpen, setCatalogOpen] = useState(false);
  // Per-item modal: when opened from a missing pill, the request's
  // is_shared informs the gear write so the auto-decrement matches.
  // Tracked separately so opening from inventory (catalog item) vs
  // missing pill (request-driven) is unambiguous.
  const [selectedItemIsShared, setSelectedItemIsShared] = useState(false);

  const { data: activityGear } = useQuery({
    queryKey: ['activity-gear', activityId],
    queryFn: () => gearService.getForActivity(activityId),
  });

  // Catalog only fetched once the custom sheet opens — saves a request
  // for the common case where the user just edits an existing item.
  const { data: catalog = [] } = useQuery({
    queryKey: ['gear-catalog', sportKey],
    queryFn: () => gearService.getCatalog(sportKey),
    enabled: showCustomSheet,
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
    openItemByName: (name: string, isShared?: boolean, fromRequest?: boolean) => {
      const existing = (activityGear ?? []).find(
        (g) => g.gear_name === name && g.user_id === currentUserId,
      );
      const mine = existing?.quantity ?? 0;
      // From a missing pill: default to `mine + 1` so save actually
      // adds one more (otherwise default = mine = no delta = no
      // decrement, which is the "lending 1 didn't work" bug).
      // From inventory pill / regular edit: default to current qty.
      const draft = fromRequest
        ? Math.min(99, mine + 1)
        : (mine > 0 ? mine : 1);
      setMyQtyDraft(draft);
      setSelectedItemIsShared(existing?.is_shared ?? isShared ?? false);
      setSelectedItemName(name);
    },
    openCustomSheet: () => {
      setCustomSheetMode('bring');
      setCustomName('');
      setCustomQty(1);
      setCustomIsShared(false);
      setCatalogOpen(false);
      setShowCustomSheet(true);
    },
    openRequestSheet: (isShared: boolean) => {
      setCustomSheetMode('request');
      setCustomName('');
      setCustomQty(1);
      setCustomIsShared(isShared);
      setCatalogOpen(false);
      setShowCustomSheet(true);
    },
  }), [activityGear, currentUserId]);

  // Drives both Save and Remove on the per-item modal — sets the user's
  // gear to the transformed list and invalidates the caches. Also
  // invalidates activity-gear-requests since set_activity_gear may
  // auto-decrement matching requests server-side.
  type GearWriteItem = { name: string; quantity: number; is_shared: boolean };

  const persistMyGear = async (transform: (existing: GearWriteItem[]) => GearWriteItem[]) => {
    const mine: GearWriteItem[] = (activityGear ?? [])
      .filter((g) => g.user_id === currentUserId)
      .map((g) => ({ name: g.gear_name, quantity: g.quantity, is_shared: g.is_shared }));
    const next = transform(mine);
    await gearService.setGear(activityId, next);
    await queryClient.invalidateQueries({ queryKey: ['activity-gear', activityId] });
    await queryClient.invalidateQueries({ queryKey: ['activity-gear-requests', activityId] });
  };

  const saveMyContribution = async () => {
    if (!selectedItemName) return;
    setIsSavingItem(true);
    try {
      await persistMyGear((mine) => {
        const filtered = mine.filter((m) => m.name !== selectedItemName);
        if (myQtyDraft > 0) filtered.push({
          name: selectedItemName,
          quantity: myQtyDraft,
          is_shared: selectedItemIsShared,
        });
        return filtered;
      });
      setSelectedItemName(null);
      Burnt.toast({ title: t('gear.saved'), preset: 'done' });
    } catch (err) {
      // PostgrestError doesn't always pass `instanceof Error` in RN
      // bundles — duck-type the message field instead.
      const msg = (err && typeof err === 'object' && 'message' in err && typeof (err as { message: unknown }).message === 'string')
        ? (err as { message: string }).message
        : t('auth.unknownError');
      Burnt.toast({ title: msg });
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
    } catch (err) {
      // PostgrestError doesn't always pass `instanceof Error` in RN
      // bundles — duck-type the message field instead.
      const msg = (err && typeof err === 'object' && 'message' in err && typeof (err as { message: unknown }).message === 'string')
        ? (err as { message: string }).message
        : t('auth.unknownError');
      Burnt.toast({ title: msg });
    } finally {
      setIsSavingItem(false);
    }
  };

  const submitCustomSheet = async () => {
    const name = customName.trim();
    if (!name) return;
    setIsSavingItem(true);
    try {
      // Catalog match wins over the toggle on the server, but we send
      // the toggle value so free-form items get classified correctly.
      const catalogMatch = catalog.find((c) => c.name_key === name);
      const effectiveIsShared = catalogMatch?.is_shared ?? customIsShared;

      if (customSheetMode === 'bring') {
        await persistMyGear((mine) => {
          if (mine.some((m) => m.name === name)) {
            return mine.map((m) => m.name === name
              ? { ...m, quantity: customQty, is_shared: effectiveIsShared }
              : m);
          }
          return [...mine, { name, quantity: customQty, is_shared: effectiveIsShared }];
        });
        Burnt.toast({ title: t('gear.saved'), preset: 'done' });
      } else {
        await gearService.requestGear(activityId, name, customQty, effectiveIsShared);
        await queryClient.invalidateQueries({ queryKey: ['activity-gear-requests', activityId] });
        Burnt.toast({ title: t('gear.requestSaved', { defaultValue: 'Demande envoyée' }), preset: 'done' });
      }
      setShowCustomSheet(false);
      setCustomName('');
      setCustomQty(1);
    } catch (err) {
      // PostgrestError doesn't always pass `instanceof Error` in RN
      // bundles — duck-type the message field instead.
      const msg = (err && typeof err === 'object' && 'message' in err && typeof (err as { message: unknown }).message === 'string')
        ? (err as { message: string }).message
        : t('auth.unknownError');
      Burnt.toast({ title: msg });
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
                <Text style={styles.sheetTitle}>
                  {customSheetMode === 'request'
                    ? t('gear.requestSheetTitle', { defaultValue: 'Demander un manquant' })
                    : t('gear.customSheetTitle')}
                </Text>

                {catalog.length > 0 && (
                  <View style={styles.dropdownWrapper}>
                    <Pressable
                      style={styles.dropdownHeader}
                      onPress={() => setCatalogOpen((v) => !v)}
                      hitSlop={4}
                    >
                      <Text style={styles.dropdownHeaderText}>
                        {t('gear.pickFromList')}
                      </Text>
                      <ChevronDown
                        size={16}
                        color={colors.textSecondary}
                        strokeWidth={2.2}
                        style={{ transform: [{ rotate: catalogOpen ? '180deg' : '0deg' }] }}
                      />
                    </Pressable>
                    {catalogOpen && (
                      <View style={styles.dropdownList}>
                        {catalog.map((item) => {
                          const selected = customName.trim() === item.name_key;
                          return (
                            <Pressable
                              key={item.id}
                              onPress={() => {
                                setCustomName(item.name_key);
                                setCatalogOpen(false);
                              }}
                              style={({ pressed }) => [
                                styles.dropdownRow,
                                pressed && { backgroundColor: colors.surface },
                              ]}
                            >
                              <Text style={styles.dropdownRowText}>{item.name_key}</Text>
                              {selected && (
                                <Check size={16} color={colors.cta} strokeWidth={2.5} />
                              )}
                            </Pressable>
                          );
                        })}
                      </View>
                    )}
                  </View>
                )}

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

                {/* Personnel / Partagé — for free-form items only.
                    Catalog matches lock the toggle since the server
                    overrides client input for known items anyway. */}
                {(() => {
                  const trimmed = customName.trim();
                  const catalogMatch = catalog.find((c) => c.name_key === trimmed);
                  const locked = !!catalogMatch;
                  const sharedValue = locked ? catalogMatch.is_shared : customIsShared;
                  return (
                    <View style={styles.fieldBoxRow}>
                      <Text style={styles.fieldLabel}>{t('gear.customSheetTypeLabel', { defaultValue: 'Type' })}</Text>
                      <View style={styles.typeToggleRow}>
                        <Pressable
                          onPress={() => !locked && setCustomIsShared(false)}
                          style={[
                            styles.typeToggleBtn,
                            !sharedValue && styles.typeToggleBtnActive,
                            locked && styles.typeToggleBtnLocked,
                          ]}
                          disabled={locked}
                          hitSlop={4}
                        >
                          <Text style={[styles.typeToggleText, !sharedValue && styles.typeToggleTextActive]}>
                            {t('gear.typePersonal', { defaultValue: 'Personnel' })}
                          </Text>
                        </Pressable>
                        <Pressable
                          onPress={() => !locked && setCustomIsShared(true)}
                          style={[
                            styles.typeToggleBtn,
                            sharedValue && styles.typeToggleBtnActive,
                            locked && styles.typeToggleBtnLocked,
                          ]}
                          disabled={locked}
                          hitSlop={4}
                        >
                          <Text style={[styles.typeToggleText, sharedValue && styles.typeToggleTextActive]}>
                            {t('gear.typeShared', { defaultValue: 'Partagé' })}
                          </Text>
                        </Pressable>
                      </View>
                    </View>
                  );
                })()}

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
                  onPress={submitCustomSheet}
                  disabled={isSavingItem || !customName.trim()}
                >
                  <Text style={styles.saveBtnText}>
                    {customSheetMode === 'request'
                      ? t('gear.requestSheetSave', { defaultValue: 'Demander' })
                      : t('profil.save')}
                  </Text>
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

  // Personnel / Partagé toggle — segmented control for free-form
  // items. Catalog matches show the active side as locked (faded
  // disabled state) since the server overrides client input.
  typeToggleRow: {
    flexDirection: 'row',
    backgroundColor: colors.surface,
    borderRadius: radius.md,
    padding: 2,
    gap: 2,
  },
  typeToggleBtn: {
    flex: 1,
    paddingVertical: spacing.sm,
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: radius.md - 2,
  },
  typeToggleBtnActive: {
    backgroundColor: colors.cta + '26',
  },
  typeToggleBtnLocked: {
    opacity: 0.6,
  },
  typeToggleText: {
    color: colors.textSecondary,
    fontSize: fontSizes.sm,
    fontWeight: '600',
  },
  typeToggleTextActive: {
    color: colors.cta,
    fontWeight: '700',
  },

  dropdownWrapper: {
    marginBottom: spacing.md,
    borderWidth: 1,
    borderColor: colors.line,
    borderRadius: radius.md,
    overflow: 'hidden',
  },
  dropdownHeader: {
    flexDirection: 'row', alignItems: 'center',
    paddingVertical: spacing.sm + 2,
    paddingHorizontal: spacing.md,
    backgroundColor: colors.surface,
  },
  dropdownHeaderText: {
    flex: 1, color: colors.textPrimary,
    fontSize: fontSizes.sm, fontWeight: '600',
  },
  dropdownList: {
    backgroundColor: colors.background,
  },
  dropdownRow: {
    flexDirection: 'row', alignItems: 'center',
    paddingVertical: spacing.sm + 2,
    paddingHorizontal: spacing.md,
    borderTopWidth: 1, borderTopColor: colors.line,
  },
  dropdownRowText: {
    flex: 1, color: colors.textPrimary,
    fontSize: fontSizes.sm,
  },
});
