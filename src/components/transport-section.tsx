import { View, Text, Pressable, Modal, StyleSheet, TextInput, KeyboardAvoidingView, Platform, ScrollView } from 'react-native';
import { useState, useMemo, useCallback, forwardRef, useImperativeHandle } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import { router } from 'expo-router';
import { Car, Bike, TrainFront, Footprints, HelpCircle, Clock } from 'lucide-react-native';
import DateTimePicker from '@react-native-community/datetimepicker';
import dayjs from 'dayjs';
import * as Burnt from 'burnt';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { getFriendlyError } from '@/utils/friendly-error';
import { transportService } from '@/services/transport-service';
import { supabase } from '@/services/supabase';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';

interface Props {
  activityId: string;
  currentUserId: string | null;
}

// Modal-only host: the dense "Voir tous les détails" surface (cars list,
// city filter, others footer, header CTA) was pruned. MyOutingCard +
// GroupCard now own all visible transport state. This component just
// holds the two editor modals (declare/edit transport, reserve a seat)
// and exposes them via imperative refs the cards already drive.
export interface TransportSectionHandle {
  openEditor: () => void;
  openRequestSheet: (driverId: string, defaultPickupFrom?: string | null) => void;
}

const TRANSPORT_TYPES = ['car', 'carpool', 'bike', 'on_foot', 'other', 'public_transport'] as const;
const CAR_TYPES = ['car', 'carpool'] as const;

const TRANSPORT_ICONS: Record<string, typeof Car> = {
  car: Car,
  carpool: Car,
  public_transport: TrainFront,
  bike: Bike,
  on_foot: Footprints,
  other: HelpCircle,
};

export const TransportSection = forwardRef<TransportSectionHandle, Props>(function TransportSection({ activityId, currentUserId }, ref) {
  const { t } = useTranslation();
  const queryClient = useQueryClient();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);

  // Editor (declare / edit own transport) state.
  const [showEditor, setShowEditor] = useState(false);
  const [selectedType, setSelectedType] = useState<string | null>(null);
  const [seats, setSeats] = useState(0);
  const [fromName, setFromName] = useState('');
  const [departsAt, setDepartsAt] = useState<Date | null>(null);
  const [showDepartsPicker, setShowDepartsPicker] = useState(false);
  const [isSaving, setIsSaving] = useState(false);

  // Seat-reserve state.
  const [requestingFromDriver, setRequestingFromDriver] = useState<string | null>(null);
  const [requestPickup, setRequestPickup] = useState('');
  const [requestMessage, setRequestMessage] = useState('');
  const [requestedPickupAt, setRequestedPickupAt] = useState<Date | null>(null);
  const [showPickupPicker, setShowPickupPicker] = useState(false);
  const [requestSending, setRequestSending] = useState(false);

  // Drives the default departs/pickup time (= activity start - 30min).
  const { data: activityRow } = useQuery({
    queryKey: ['activity-starts-at', activityId],
    queryFn: async () => {
      const { data } = await supabase.from('activities').select('starts_at').eq('id', activityId).single();
      return data as { starts_at: string } | null;
    },
  });
  const activityStartsAt = activityRow?.starts_at ? new Date(activityRow.starts_at) : null;

  // Used by openEditor to prefill from the user's existing transport,
  // and by openRequestSheet's default-pickup-city fallback. TanStack
  // dedupes with the same query in MyOutingCard / GroupCard.
  const { data: participants } = useQuery({
    queryKey: ['transport', activityId],
    queryFn: () => transportService.getForActivity(activityId),
    staleTime: 0,
  });

  const myTransport = (participants ?? []).find((p) => p.user_id === currentUserId);

  const openEditor = useCallback(() => {
    if (myTransport) {
      setSelectedType(myTransport.transport_type);
      setSeats(myTransport.transport_seats ?? 0);
      setFromName(myTransport.transport_from_name ?? '');
      setDepartsAt(myTransport.transport_departs_at ? new Date(myTransport.transport_departs_at) : null);
    } else {
      setSelectedType(null);
      setSeats(0);
      setFromName('');
      setDepartsAt(activityStartsAt ? new Date(activityStartsAt.getTime() - 30 * 60 * 1000) : null);
    }
    setShowEditor(true);
  }, [myTransport, activityStartsAt]);

  const openRequestSheet = useCallback((driverId: string, defaultPickupFrom?: string | null) => {
    setRequestingFromDriver(driverId);
    setRequestPickup(defaultPickupFrom ?? '');
    setRequestMessage('');
    // Sensible default — activity-start - 30min. Pickup-vs-driver-
    // departure is not constrained: a passenger en route (Sisteron
    // between Marseille and Briançon) is picked up AFTER the driver's
    // start. Mig 00176 dropped the wrong DB bound that used to force
    // pickup ≤ driver_departs_at.
    setRequestedPickupAt(activityStartsAt ? new Date(activityStartsAt.getTime() - 30 * 60 * 1000) : null);
  }, [activityStartsAt]);

  useImperativeHandle(ref, () => ({ openEditor, openRequestSheet }), [openEditor, openRequestSheet]);

  const handleSave = async () => {
    if (!selectedType) return;
    const isCar = (CAR_TYPES as readonly string[]).includes(selectedType);
    setIsSaving(true);
    try {
      await transportService.setTransport(
        activityId,
        selectedType,
        isCar ? seats : null,
        fromName.trim() || null,
        // Departure time persists for every mode now — cyclists and
        // pedestrians can log when they leave too. Seats stay car-only.
        departsAt ? departsAt.toISOString() : null,
      );
      await queryClient.invalidateQueries({ queryKey: ['transport', activityId] });
      await queryClient.invalidateQueries({ queryKey: ['transport-summary', activityId] });
      setShowEditor(false);
      Burnt.toast({ title: t('transport.saved'), preset: 'done' });
    } catch (err) {
      Burnt.toast({ title: getFriendlyError(err, 'generic') });
    } finally {
      setIsSaving(false);
    }
  };

  const handleRequestSeat = async () => {
    if (!requestingFromDriver) return;
    setRequestSending(true);
    try {
      const conversationId = await transportService.requestSeat(
        activityId,
        requestingFromDriver,
        requestPickup.trim() || undefined,
        requestMessage.trim() || undefined,
        requestedPickupAt ? requestedPickupAt.toISOString() : null,
      );
      await queryClient.invalidateQueries({ queryKey: ['seat-requests', activityId] });
      await queryClient.invalidateQueries({ queryKey: ['transport-summary', activityId] });
      await queryClient.invalidateQueries({ queryKey: ['conversations'] });
      setRequestingFromDriver(null);
      Burnt.toast({ title: t('transport.seatRequested'), preset: 'done' });
      // Land on the chat — driver will be there too once they tap the
      // push or open messagerie. Both sides can discuss pickup/timing
      // before the driver accepts. Falls through silently when the
      // two are blocked (no conversation to route to).
      if (conversationId) {
        router.push(`/(auth)/conversation/${conversationId}`);
      }
    } catch (err) {
      Burnt.toast({ title: getFriendlyError(err, 'generic') });
    } finally {
      setRequestSending(false);
    }
  };

  return (
    <>
      {/* Transport editor modal — declare / edit own transport. */}
      <Modal visible={showEditor} animationType="fade" transparent>
        <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
          <Pressable style={styles.backdrop} onPress={() => setShowEditor(false)}>
            <Pressable style={styles.sheet} onPress={() => {}}>
              <ScrollView keyboardShouldPersistTaps="handled" showsVerticalScrollIndicator={false}>
                <Text style={styles.sheetTitle}>{t('transport.howAreYouGoing')}</Text>

                <View style={styles.typeGrid}>
                  {TRANSPORT_TYPES.map((type) => {
                    const IconComp = TRANSPORT_ICONS[type] ?? HelpCircle;
                    const isSelected = selectedType === type;
                    return (
                      <Pressable
                        key={type}
                        style={[styles.typeChip, isSelected && styles.typeChipActive]}
                        onPress={() => setSelectedType(type)}
                      >
                        <IconComp size={18} color={isSelected ? colors.textPrimary : colors.textSecondary} strokeWidth={2} />
                        <Text style={[styles.typeChipText, isSelected && styles.typeChipTextActive]}>
                          {t(`transport.type.${type}`)}
                        </Text>
                      </Pressable>
                    );
                  })}
                </View>

                {selectedType && (CAR_TYPES as readonly string[]).includes(selectedType) && (
                  <View style={styles.seatsRow}>
                    <Text style={styles.seatsLabel}>{t('transport.freeSeats')}</Text>
                    <View style={styles.seatsPicker}>
                      <Pressable style={styles.seatsBtn} onPress={() => setSeats(Math.max(0, seats - 1))}>
                        <Text style={styles.seatsBtnText}>-</Text>
                      </Pressable>
                      <Text style={styles.seatsValue}>{seats}</Text>
                      <Pressable style={styles.seatsBtn} onPress={() => setSeats(Math.min(8, seats + 1))}>
                        <Text style={styles.seatsBtnText}>+</Text>
                      </Pressable>
                    </View>
                  </View>
                )}

                <View style={styles.fromRow}>
                  <Text style={styles.fromLabel}>{t('transport.from')}</Text>
                  <TextInput
                    style={styles.fromInput}
                    value={fromName}
                    onChangeText={setFromName}
                    placeholder={t('transport.fromPlaceholder')}
                    placeholderTextColor={colors.textSecondary}
                    maxLength={100}
                  />
                </View>

                {/* Departure time is useful for any mode — a cyclist or
                    pedestrian leaving Gap at 7h to make a 9h start gives
                    the group a useful coordination signal too. */}
                {selectedType && (
                  <View style={styles.fromRow}>
                    <Text style={styles.fromLabel}>{t('transport.departsAt')}</Text>
                    <Pressable style={styles.timeButton} onPress={() => setShowDepartsPicker(true)}>
                      <Clock size={14} color={colors.cta} strokeWidth={2.4} />
                      <Text style={styles.timeButtonText}>
                        {departsAt ? dayjs(departsAt).format('H[h]mm') : t('transport.pickTime')}
                      </Text>
                    </Pressable>
                  </View>
                )}
                {showDepartsPicker && (
                  <DateTimePicker
                    value={departsAt ?? activityStartsAt ?? new Date()}
                    mode="time"
                    is24Hour
                    onChange={(_, d) => {
                      setShowDepartsPicker(Platform.OS === 'ios');
                      if (d) {
                        const base = activityStartsAt ?? new Date();
                        const merged = new Date(base);
                        merged.setHours(d.getHours(), d.getMinutes(), 0, 0);
                        setDepartsAt(merged);
                      }
                    }}
                  />
                )}

                <Pressable
                  style={[styles.saveButton, (!selectedType || isSaving) && { opacity: 0.4 }]}
                  onPress={handleSave}
                  disabled={!selectedType || isSaving}
                >
                  <Text style={styles.saveText}>{t('profil.save')}</Text>
                </Pressable>
              </ScrollView>
            </Pressable>
          </Pressable>
        </KeyboardAvoidingView>
      </Modal>

      {/* Seat request modal — request a seat from a specific driver. */}
      <Modal visible={requestingFromDriver !== null} animationType="fade" transparent onRequestClose={() => setRequestingFromDriver(null)}>
        <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
          <Pressable style={styles.backdrop} onPress={() => setRequestingFromDriver(null)}>
            <Pressable style={styles.sheet} onPress={() => {}}>
              <ScrollView keyboardShouldPersistTaps="handled" showsVerticalScrollIndicator={false}>
                <Text style={styles.sheetTitle}>{t('transport.requestSeatTitle')}</Text>

                <View style={styles.fromRow}>
                  <Text style={styles.fromLabel}>{t('transport.pickupFrom')}</Text>
                  <TextInput
                    style={styles.fromInput}
                    value={requestPickup}
                    onChangeText={setRequestPickup}
                    placeholder={t('transport.fromPlaceholder')}
                    placeholderTextColor={colors.textSecondary}
                    maxLength={100}
                  />
                </View>

                <View style={styles.fromRow}>
                  <Text style={styles.fromLabel}>{t('transport.pickupAt')}</Text>
                  <Pressable style={styles.timeButton} onPress={() => setShowPickupPicker(true)}>
                    <Clock size={14} color={colors.cta} strokeWidth={2.4} />
                    <Text style={styles.timeButtonText}>
                      {requestedPickupAt ? dayjs(requestedPickupAt).format('H[h]mm') : t('transport.pickTime')}
                    </Text>
                  </Pressable>
                </View>
                {showPickupPicker && (
                  <DateTimePicker
                    value={requestedPickupAt ?? activityStartsAt ?? new Date()}
                    mode="time"
                    is24Hour
                    onChange={(_, d) => {
                      setShowPickupPicker(Platform.OS === 'ios');
                      if (d) {
                        const base = activityStartsAt ?? new Date();
                        const merged = new Date(base);
                        merged.setHours(d.getHours(), d.getMinutes(), 0, 0);
                        setRequestedPickupAt(merged);
                      }
                    }}
                  />
                )}

                <View style={styles.fromRow}>
                  <Text style={styles.fromLabel}>{t('transport.messageOptional')}</Text>
                  <TextInput
                    style={[styles.fromInput, { minHeight: 60, textAlignVertical: 'top' }]}
                    value={requestMessage}
                    onChangeText={setRequestMessage}
                    placeholder={t('transport.messagePlaceholder')}
                    placeholderTextColor={colors.textSecondary}
                    maxLength={500}
                    multiline
                  />
                </View>

                <Pressable
                  style={[styles.saveButton, requestSending && { opacity: 0.4 }]}
                  disabled={requestSending}
                  onPress={handleRequestSeat}
                >
                  <Text style={styles.saveText}>{t('transport.requestSeat')}</Text>
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
  sheetTitle: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: 'bold', marginBottom: spacing.md },
  typeGrid: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.xs, marginBottom: spacing.md },
  typeChip: {
    flexDirection: 'row', alignItems: 'center', gap: 6,
    backgroundColor: colors.surface, borderRadius: radius.full,
    paddingHorizontal: spacing.sm, paddingVertical: spacing.xs,
  },
  typeChipActive: { backgroundColor: colors.cta },
  typeChipText: { color: colors.textSecondary, fontSize: fontSizes.xs },
  typeChipTextActive: { color: colors.textPrimary, fontWeight: 'bold' },
  seatsRow: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    backgroundColor: colors.surface, borderRadius: radius.md, padding: spacing.md, marginBottom: spacing.md,
  },
  seatsLabel: { color: colors.textPrimary, fontSize: fontSizes.sm },
  seatsPicker: { flexDirection: 'row', alignItems: 'center', gap: spacing.md },
  seatsBtn: {
    backgroundColor: colors.background, borderRadius: radius.full,
    width: 32, height: 32, alignItems: 'center', justifyContent: 'center',
  },
  seatsBtnText: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: 'bold' },
  seatsValue: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: 'bold', minWidth: 24, textAlign: 'center' },
  fromRow: {
    backgroundColor: colors.surface, borderRadius: radius.md,
    padding: spacing.md, marginBottom: spacing.md,
  },
  fromLabel: { color: colors.textSecondary, fontSize: fontSizes.xs, marginBottom: spacing.xs },
  fromInput: { color: colors.textPrimary, fontSize: fontSizes.md },
  timeButton: {
    flexDirection: 'row', alignItems: 'center', gap: 6,
    alignSelf: 'flex-start',
    backgroundColor: colors.cta + '1F',
    paddingHorizontal: spacing.md, paddingVertical: spacing.sm,
    borderRadius: radius.full,
    marginTop: 4,
  },
  timeButtonText: { color: colors.cta, fontSize: fontSizes.sm, fontWeight: '700', letterSpacing: 0.3 },
  saveButton: {
    backgroundColor: colors.cta, borderRadius: radius.md,
    paddingVertical: spacing.md, alignItems: 'center', marginTop: spacing.sm,
  },
  saveText: { color: '#FFFFFF', fontSize: fontSizes.md, fontWeight: 'bold' },
});
