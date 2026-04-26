import { View, Text, Pressable, Modal, StyleSheet, TextInput, KeyboardAvoidingView, Platform, ScrollView, LayoutAnimation, UIManager } from 'react-native';
import { useState, useMemo, useEffect } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import { Car, Bike, TrainFront, Footprints, HelpCircle, MapPin, ChevronDown, Plus, Clock } from 'lucide-react-native';
import DateTimePicker from '@react-native-community/datetimepicker';
import dayjs from 'dayjs';
import * as Burnt from 'burnt';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { transportService, type ParticipantTransport, type SeatAssignment } from '@/services/transport-service';
import { supabase } from '@/services/supabase';
import { UserAvatar } from './user-avatar';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';

if (Platform.OS === 'android' && UIManager.setLayoutAnimationEnabledExperimental) {
  UIManager.setLayoutAnimationEnabledExperimental(true);
}

interface Props {
  activityId: string;
  currentUserId: string | null;
}

const TRANSPORT_TYPES = ['car', 'carpool', 'public_transport', 'bike', 'on_foot', 'other'] as const;
const CAR_TYPES = ['car', 'carpool'] as const;

const TRANSPORT_ICONS: Record<string, typeof Car> = {
  car: Car,
  carpool: Car,
  public_transport: TrainFront,
  bike: Bike,
  on_foot: Footprints,
  other: HelpCircle,
};


export function TransportSection({ activityId, currentUserId }: Props) {
  const { t } = useTranslation();
  const queryClient = useQueryClient();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);

  const [showEditor, setShowEditor] = useState(false);
  const [selectedType, setSelectedType] = useState<string | null>(null);
  const [seats, setSeats] = useState(0);
  const [fromName, setFromName] = useState('');
  const [departsAt, setDepartsAt] = useState<Date | null>(null);
  const [showDepartsPicker, setShowDepartsPicker] = useState(false);
  const [isSaving, setIsSaving] = useState(false);

  const [requestingFromDriver, setRequestingFromDriver] = useState<string | null>(null);
  const [requestPickup, setRequestPickup] = useState('');
  const [requestMessage, setRequestMessage] = useState('');
  const [requestedPickupAt, setRequestedPickupAt] = useState<Date | null>(null);
  const [showPickupPicker, setShowPickupPicker] = useState(false);
  const [requestSending, setRequestSending] = useState(false);

  // Default times anchor on the activity's starts_at (-30min for driver default)
  const { data: activityRow } = useQuery({
    queryKey: ['activity-starts-at', activityId],
    queryFn: async () => {
      const { data } = await supabase.from('activities').select('starts_at').eq('id', activityId).single();
      return data as { starts_at: string } | null;
    },
  });
  const activityStartsAt = activityRow?.starts_at ? new Date(activityRow.starts_at) : null;

  const [expandedCarId, setExpandedCarId] = useState<string | null>(null);
  const [cityFilter, setCityFilter] = useState<string>('all');

  const { data: participants } = useQuery({
    queryKey: ['transport', activityId],
    queryFn: () => transportService.getForActivity(activityId),
  });

  const { data: pendingSeatRequests } = useQuery({
    queryKey: ['seat-requests', activityId],
    queryFn: () => transportService.getPendingSeatRequests(activityId),
  });

  const { data: acceptedSeatRequests } = useQuery({
    queryKey: ['seat-requests-accepted', activityId],
    queryFn: () => transportService.getSeatAssignments(activityId),
  });

  const acceptedCountByDriver = useMemo(() => {
    const map = new Map<string, number>();
    (acceptedSeatRequests ?? []).forEach((r) => {
      map.set(r.driver_id, (map.get(r.driver_id) ?? 0) + 1);
    });
    return map;
  }, [acceptedSeatRequests]);

  const cars = useMemo(
    () => (participants ?? []).filter((p) => {
      if (!p.transport_type || !(CAR_TYPES as readonly string[]).includes(p.transport_type)) return false;
      const free = p.transport_seats ?? 0;
      const accepted = acceptedCountByDriver.get(p.user_id) ?? 0;
      return free + accepted > 0;
    }),
    [participants, acceptedCountByDriver],
  );

  const others = useMemo(
    () => (participants ?? []).filter((p) => {
      if (!p.transport_type) return false;
      if (!(CAR_TYPES as readonly string[]).includes(p.transport_type)) return true;
      const free = p.transport_seats ?? 0;
      const accepted = acceptedCountByDriver.get(p.user_id) ?? 0;
      return free + accepted === 0;
    }),
    [participants, acceptedCountByDriver],
  );

  const uniqueCities = useMemo(() => {
    const set = new Set<string>();
    cars.forEach((c) => { if (c.transport_from_name) set.add(c.transport_from_name); });
    return Array.from(set).sort();
  }, [cars]);

  const filteredCars = useMemo(() => {
    if (cityFilter === 'all') return cars;
    return cars.filter((c) => c.transport_from_name === cityFilter);
  }, [cars, cityFilter]);

  const myTransport = (participants ?? []).find((p) => p.user_id === currentUserId);
  const hasSetTransport = !!myTransport;
  const isDriver = myTransport
    && (CAR_TYPES as readonly string[]).includes(myTransport.transport_type ?? '')
    && (myTransport.transport_seats ?? 0) > 0;
  const myAcceptedSeat = (acceptedSeatRequests ?? []).find((r) => r.requester_id === currentUserId);

  const totalFreeSeats = useMemo(
    () => cars.reduce((sum, c) => sum + (c.transport_seats ?? 0), 0),
    [cars],
  );

  const hasPendingRequest = (driverId: string) =>
    (pendingSeatRequests ?? []).some((r) => r.driver_id === driverId && r.requester_id === currentUserId);

  const getPassengersFor = (driverId: string) =>
    (acceptedSeatRequests ?? []).filter((r) => r.driver_id === driverId);

  const toggleCar = (carId: string) => {
    LayoutAnimation.configureNext(LayoutAnimation.Presets.easeInEaseOut);
    setExpandedCarId(expandedCarId === carId ? null : carId);
  };

  const openEditor = () => {
    if (myTransport) {
      setSelectedType(myTransport.transport_type);
      setSeats(myTransport.transport_seats ?? 0);
      setFromName(myTransport.transport_from_name ?? '');
      setDepartsAt(myTransport.transport_departs_at ? new Date(myTransport.transport_departs_at) : null);
    } else {
      setSelectedType(null);
      setSeats(0);
      setFromName('');
      // Default departs at 30min before activity start
      setDepartsAt(activityStartsAt ? new Date(activityStartsAt.getTime() - 30 * 60 * 1000) : null);
    }
    setShowEditor(true);
  };

  const openRequestSheet = (driverId: string) => {
    setRequestingFromDriver(driverId);
    setRequestPickup('');
    setRequestMessage('');
    setRequestedPickupAt(activityStartsAt ? new Date(activityStartsAt.getTime() - 30 * 60 * 1000) : null);
  };

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
        isCar && departsAt ? departsAt.toISOString() : null,
      );
      await queryClient.invalidateQueries({ queryKey: ['transport', activityId] });
      setShowEditor(false);
      Burnt.toast({ title: t('transport.saved'), preset: 'done' });
    } catch {
      Burnt.toast({ title: t('auth.unknownError') });
    } finally {
      setIsSaving(false);
    }
  };

  const handleRequestSeat = async () => {
    if (!requestingFromDriver) return;
    setRequestSending(true);
    try {
      await transportService.requestSeat(
        activityId,
        requestingFromDriver,
        requestPickup.trim() || undefined,
        requestMessage.trim() || undefined,
        requestedPickupAt ? requestedPickupAt.toISOString() : null,
      );
      await queryClient.invalidateQueries({ queryKey: ['seat-requests', activityId] });
      setRequestingFromDriver(null);
      Burnt.toast({ title: t('transport.seatRequested'), preset: 'done' });
    } catch {
      Burnt.toast({ title: t('auth.unknownError') });
    } finally {
      setRequestSending(false);
    }
  };

  const handleCancelSeat = async () => {
    if (!myAcceptedSeat) return;
    try {
      await transportService.cancelAcceptedSeat(myAcceptedSeat.id);
      await queryClient.invalidateQueries({ queryKey: ['seat-requests-accepted', activityId] });
      await queryClient.invalidateQueries({ queryKey: ['transport', activityId] });
      Burnt.toast({ title: t('transport.seatCancelled'), preset: 'done' });
    } catch {
      Burnt.toast({ title: t('auth.unknownError') });
    }
  };

  // Collapse any expanded car that disappears from the filtered view
  useEffect(() => {
    if (expandedCarId && !filteredCars.some((c) => c.user_id === expandedCarId)) {
      setExpandedCarId(null);
    }
  }, [expandedCarId, filteredCars]);

  return (
    <View style={styles.section}>
      <View style={styles.headerRow}>
        <Text style={styles.freeSeatsLabel}>
          {totalFreeSeats === 0 ? t('transport.noFreeSeats') : t('transport.freeSeatsTotal', { count: totalFreeSeats })}
        </Text>
        <Pressable onPress={openEditor} hitSlop={8} style={styles.headerCta}>
          {!hasSetTransport && <Plus size={12} color={colors.cta} strokeWidth={2.5} />}
          <Text style={styles.headerCtaText}>
            {hasSetTransport ? t('transport.edit') : t('transport.propose')}
          </Text>
        </Pressable>
      </View>

      {uniqueCities.length >= 2 && (
        <View style={styles.filterRow}>
          <FilterPill
            label={t('transport.filterAll')}
            isActive={cityFilter === 'all'}
            onPress={() => setCityFilter('all')}
            styles={styles}
          />
          {uniqueCities.map((city) => (
            <FilterPill
              key={city}
              label={city}
              isActive={cityFilter === city}
              onPress={() => setCityFilter(city)}
              styles={styles}
            />
          ))}
        </View>
      )}

      {cars.length === 0 ? (
        <View style={styles.emptyBox}>
          <Text style={styles.emptyText}>{t('transport.noCars')}</Text>
        </View>
      ) : filteredCars.length === 0 ? (
        <View style={styles.emptyBox}>
          <Text style={styles.emptyText}>—</Text>
        </View>
      ) : (
        filteredCars.map((car) => {
          const passengers = getPassengersFor(car.user_id);
          const used = passengers.length;
          const free = car.transport_seats ?? 0;
          const offered = used + free;
          const isMyCar = car.user_id === currentUserId;
          const hasMySeatHere = myAcceptedSeat?.driver_id === car.user_id;
          const hasPendingHere = hasPendingRequest(car.user_id);
          return (
            <CarRow
              key={car.user_id}
              car={car}
              capacity={offered}
              used={used}
              free={free}
              passengers={passengers}
              isExpanded={expandedCarId === car.user_id}
              onToggle={() => toggleCar(car.user_id)}
              isMyCar={isMyCar}
              hasMySeatHere={hasMySeatHere}
              hasPendingHere={hasPendingHere}
              hasAnyReservation={!!myAcceptedSeat}
              canRequest={!isDriver && !myAcceptedSeat && !hasPendingHere && !isMyCar && free > 0}
              onRequestPress={() => {
                openRequestSheet(car.user_id);
                setRequestPickup(myTransport?.transport_from_name ?? '');
              }}
              onCancelSeatPress={handleCancelSeat}
              onEditMyCar={openEditor}
              t={t}
              styles={styles}
              colors={colors}
            />
          );
        })
      )}

      {others.length > 0 && (
        <View style={styles.othersSection}>
          <Text style={styles.othersTitle}>{t('transport.otherTransports')}</Text>
          {others.map((p) => {
            const Icon = TRANSPORT_ICONS[p.transport_type ?? 'other'] ?? HelpCircle;
            return (
              <View key={p.user_id} style={styles.otherRow}>
                <Icon size={14} color={colors.textMuted} strokeWidth={2} />
                <UserAvatar name={p.display_name} avatarUrl={p.avatar_url} size={20} />
                <Text style={styles.otherName} numberOfLines={1}>{p.display_name}</Text>
                <Text style={styles.otherType}>{t(`transport.type.${p.transport_type}`)}</Text>
                {p.transport_from_name && (
                  <Text style={styles.otherFrom} numberOfLines={1}>· {p.transport_from_name}</Text>
                )}
              </View>
            );
          })}
        </View>
      )}

      {/* Transport editor modal */}
      <Modal visible={showEditor} animationType="slide" transparent>
        <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : 'height'}>
          <Pressable style={styles.backdrop} onPress={() => setShowEditor(false)}>
            <ScrollView contentContainerStyle={{ flexGrow: 1, justifyContent: 'flex-end' }} keyboardShouldPersistTaps="handled">
              <Pressable style={styles.sheet} onPress={() => {}}>
                <View style={styles.handle} />
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

                {selectedType && (CAR_TYPES as readonly string[]).includes(selectedType) && (
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
              </Pressable>
            </ScrollView>
          </Pressable>
        </KeyboardAvoidingView>
      </Modal>

      {/* Seat request modal */}
      <Modal visible={requestingFromDriver !== null} animationType="slide" transparent onRequestClose={() => setRequestingFromDriver(null)}>
        <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : 'height'}>
          <Pressable style={styles.backdrop} onPress={() => setRequestingFromDriver(null)}>
            <ScrollView contentContainerStyle={{ flexGrow: 1, justifyContent: 'flex-end' }} keyboardShouldPersistTaps="handled">
              <Pressable style={styles.sheet} onPress={() => {}}>
                <View style={styles.handle} />
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
              </Pressable>
            </ScrollView>
          </Pressable>
        </KeyboardAvoidingView>
      </Modal>
    </View>
  );
}

interface FilterPillProps {
  label: string;
  isActive: boolean;
  onPress: () => void;
  styles: ReturnType<typeof createStyles>;
}

function FilterPill({ label, isActive, onPress, styles }: FilterPillProps) {
  return (
    <Pressable
      onPress={onPress}
      style={[styles.filterPill, isActive && styles.filterPillActive]}
      hitSlop={6}
    >
      <Text style={[styles.filterPillText, isActive && styles.filterPillTextActive]}>{label}</Text>
    </Pressable>
  );
}

interface CarRowProps {
  car: ParticipantTransport;
  capacity: number;
  used: number;
  free: number;
  passengers: SeatAssignment[];
  isExpanded: boolean;
  onToggle: () => void;
  isMyCar: boolean;
  hasMySeatHere: boolean;
  hasPendingHere: boolean;
  hasAnyReservation: boolean;
  canRequest: boolean;
  onRequestPress: () => void;
  onCancelSeatPress: () => void;
  onEditMyCar: () => void;
  t: (k: string, opts?: Record<string, unknown>) => string;
  styles: ReturnType<typeof createStyles>;
  colors: AppColors;
}

function CarRow({
  car, capacity, used, free, passengers,
  isExpanded, onToggle,
  isMyCar, hasMySeatHere, hasPendingHere, canRequest,
  onRequestPress, onCancelSeatPress, onEditMyCar,
  t, styles, colors,
}: CarRowProps) {
  const isHighlighted = isMyCar || hasMySeatHere;

  return (
    <View style={[styles.carRow, isHighlighted && styles.carRowHighlighted]}>
      <Pressable onPress={onToggle} style={styles.carHeader}>
        <View style={styles.carAvatarWrap}>
          <UserAvatar name={car.display_name} avatarUrl={car.avatar_url} size={36} />
          <View style={styles.carBadge}>
            <Car size={8} color={colors.textPrimary} strokeWidth={2.5} />
          </View>
        </View>
        <View style={{ flex: 1, minWidth: 0 }}>
          <View style={styles.carNameRow}>
            <Text style={styles.carName} numberOfLines={1}>{car.display_name}</Text>
            {isMyCar && (
              <View style={styles.myTag}><Text style={styles.myTagText}>{t('transport.myCar')}</Text></View>
            )}
            {!isMyCar && hasMySeatHere && (
              <View style={styles.myTag}><Text style={styles.myTagText}>{t('transport.myReservation')}</Text></View>
            )}
          </View>
          {(car.transport_from_name || car.transport_departs_at) && (
            <View style={styles.carMetaRow}>
              {car.transport_from_name && (
                <>
                  <MapPin size={10} color={colors.textSecondary} strokeWidth={2.2} />
                  <Text style={styles.carFrom} numberOfLines={1}>{car.transport_from_name}</Text>
                </>
              )}
              {car.transport_from_name && car.transport_departs_at && (
                <Text style={styles.carFrom}> · </Text>
              )}
              {car.transport_departs_at && (
                <>
                  <Clock size={10} color={colors.textSecondary} strokeWidth={2.2} />
                  <Text style={styles.carFrom}>{dayjs(car.transport_departs_at).format('H[h]mm')}</Text>
                </>
              )}
            </View>
          )}
        </View>
        <View style={styles.seatsCluster}>
          <View style={styles.pipsRow}>
            {Array.from({ length: capacity }).map((_, i) => (
              <View
                key={i}
                style={[styles.pip, i < used ? styles.pipFilled : styles.pipEmpty]}
              />
            ))}
          </View>
          <Text style={styles.seatsCount}>{used}/{capacity}</Text>
        </View>
        <ChevronDown
          size={16}
          color={colors.textMuted}
          strokeWidth={2}
          style={{ transform: [{ rotate: isExpanded ? '180deg' : '0deg' }] }}
        />
      </Pressable>

      {isExpanded && (
        <View style={styles.carExpand}>
          {passengers.length > 0 && (
            <View style={{ marginBottom: spacing.sm }}>
              {passengers.map((p) => (
                <View key={p.id} style={styles.passengerRow}>
                  <UserAvatar name={p.display_name} avatarUrl={p.avatar_url} size={20} />
                  <View style={{ flex: 1, minWidth: 0 }}>
                    <Text style={styles.passengerName} numberOfLines={1}>{p.display_name}</Text>
                    {(p.pickup_from || p.requested_pickup_at) && (
                      <Text style={styles.passengerSub} numberOfLines={1}>
                        {p.pickup_from ?? ''}
                        {p.pickup_from && p.requested_pickup_at ? ' · ' : ''}
                        {p.requested_pickup_at ? dayjs(p.requested_pickup_at).format('H[h]mm') : ''}
                      </Text>
                    )}
                  </View>
                  <Text style={styles.passengerTag}>{t('transport.passenger')}</Text>
                </View>
              ))}
            </View>
          )}

          {isMyCar ? (
            <Pressable style={styles.actionBtnSecondary} onPress={onEditMyCar}>
              <Text style={styles.actionBtnSecondaryText}>{t('transport.edit')}</Text>
            </Pressable>
          ) : hasMySeatHere ? (
            <Pressable style={styles.actionBtnDanger} onPress={onCancelSeatPress}>
              <Text style={styles.actionBtnDangerText}>{t('transport.cancelMySeat')}</Text>
            </Pressable>
          ) : hasPendingHere ? (
            <View style={[styles.actionBtnSecondary, { opacity: 0.6 }]}>
              <Text style={styles.actionBtnSecondaryText}>{t('transport.requestPending')}</Text>
            </View>
          ) : canRequest ? (
            <Pressable style={styles.actionBtnPrimary} onPress={onRequestPress}>
              <Text style={styles.actionBtnPrimaryText}>{t('transport.reserve', { count: free })}</Text>
            </Pressable>
          ) : free === 0 ? (
            <View style={[styles.actionBtnSecondary, { opacity: 0.5 }]}>
              <Text style={styles.actionBtnSecondaryText}>{t('transport.full')}</Text>
            </View>
          ) : null}
        </View>
      )}
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  section: { marginBottom: spacing.lg },

  headerRow: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    marginBottom: spacing.sm,
  },
  freeSeatsLabel: {
    color: colors.textSecondary, fontSize: fontSizes.xs - 2, fontWeight: 'bold',
    letterSpacing: 1.4, textTransform: 'uppercase',
  },
  headerCta: { flexDirection: 'row', alignItems: 'center', gap: 3 },
  headerCtaText: { color: colors.cta, fontSize: fontSizes.xs + 1, fontWeight: '600' },

  filterRow: { flexDirection: 'row', flexWrap: 'wrap', gap: 6, marginBottom: spacing.sm },
  filterPill: {
    backgroundColor: 'transparent',
    borderWidth: 1, borderColor: colors.line,
    borderRadius: radius.full,
    paddingHorizontal: 10, paddingVertical: 4,
  },
  filterPillActive: { backgroundColor: colors.surfaceAlt, borderColor: colors.surfaceAlt },
  filterPillText: { color: colors.textSecondary, fontSize: 11, fontWeight: '500' },
  filterPillTextActive: { color: colors.textPrimary },

  emptyBox: {
    backgroundColor: colors.surface, borderRadius: radius.md,
    padding: spacing.md, alignItems: 'center',
  },
  emptyText: { color: colors.textSecondary, fontSize: fontSizes.sm, fontStyle: 'italic' },

  carRow: {
    backgroundColor: colors.surface,
    borderRadius: radius.md,
    borderWidth: 1, borderColor: colors.line,
    marginBottom: spacing.sm,
    overflow: 'hidden',
  },
  carRowHighlighted: { borderColor: colors.cta, borderWidth: 1.5 },

  carHeader: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.sm + 2,
    paddingVertical: spacing.sm + 2, paddingHorizontal: spacing.sm + 4,
  },
  carAvatarWrap: { position: 'relative' },
  carBadge: {
    position: 'absolute', bottom: -2, right: -2,
    width: 16, height: 16, borderRadius: 8,
    backgroundColor: colors.cta,
    alignItems: 'center', justifyContent: 'center',
    borderWidth: 2, borderColor: colors.background,
  },
  carNameRow: { flexDirection: 'row', alignItems: 'center', gap: 6 },
  carName: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '700' },
  myTag: {
    backgroundColor: colors.cta,
    paddingHorizontal: 5, paddingVertical: 1,
    borderRadius: 3,
  },
  myTagText: {
    color: '#FFFFFF', fontSize: 9, fontWeight: '700',
    textTransform: 'uppercase', letterSpacing: 0.6,
  },
  carMetaRow: { flexDirection: 'row', alignItems: 'center', gap: 4, marginTop: 1 },
  carFrom: { color: colors.textSecondary, fontSize: 11 },

  seatsCluster: { alignItems: 'flex-end', gap: 3 },
  pipsRow: { flexDirection: 'row', gap: 3 },
  pip: { width: 7, height: 7, borderRadius: 3.5 },
  pipFilled: { backgroundColor: colors.cta },
  pipEmpty: { backgroundColor: colors.line },
  seatsCount: { color: colors.textMuted, fontSize: 10, fontWeight: '700' },

  carExpand: {
    paddingHorizontal: spacing.sm + 4, paddingTop: spacing.sm, paddingBottom: spacing.sm + 4,
    borderTopWidth: 1, borderTopColor: colors.line, borderStyle: 'dashed',
  },
  passengerRow: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.sm,
    paddingVertical: 4, paddingLeft: spacing.sm,
  },
  passengerName: { color: colors.textPrimary, fontSize: fontSizes.xs + 1 },
  passengerSub: { color: colors.textSecondary, fontSize: fontSizes.xs - 1, marginTop: 1 },
  passengerTag: { color: colors.textMuted, fontSize: 10 },

  actionBtnPrimary: {
    backgroundColor: colors.cta, borderRadius: radius.sm,
    height: 36, alignItems: 'center', justifyContent: 'center',
  },
  actionBtnPrimaryText: { color: '#FFFFFF', fontSize: fontSizes.sm, fontWeight: '700' },

  actionBtnDanger: {
    backgroundColor: 'transparent', borderRadius: radius.sm,
    borderWidth: 1, borderColor: colors.error,
    height: 36, alignItems: 'center', justifyContent: 'center',
  },
  actionBtnDangerText: { color: colors.error, fontSize: fontSizes.sm, fontWeight: '600' },

  actionBtnSecondary: {
    backgroundColor: colors.surfaceAlt, borderRadius: radius.sm,
    borderWidth: 1, borderColor: colors.line,
    height: 36, alignItems: 'center', justifyContent: 'center',
  },
  actionBtnSecondaryText: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '600' },

  othersSection: {
    marginTop: spacing.md, paddingTop: spacing.sm,
    borderTopWidth: 1, borderTopColor: colors.line, borderStyle: 'dashed',
  },
  othersTitle: {
    color: colors.textMuted, fontSize: fontSizes.xs - 2, fontWeight: 'bold',
    letterSpacing: 1.4, textTransform: 'uppercase',
    marginBottom: spacing.xs,
  },
  otherRow: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.xs + 2,
    paddingVertical: 5,
  },
  otherName: { color: colors.textPrimary, fontSize: fontSizes.xs + 1 },
  otherType: { color: colors.textSecondary, fontSize: fontSizes.xs },
  otherFrom: { color: colors.textMuted, fontSize: fontSizes.xs, flex: 1 },

  // Modals (unchanged structure)
  backdrop: { flex: 1, backgroundColor: colors.overlay, justifyContent: 'flex-end' },
  sheet: {
    backgroundColor: colors.background, borderTopLeftRadius: radius.lg, borderTopRightRadius: radius.lg,
    padding: spacing.lg, paddingBottom: spacing.xl + 16,
  },
  handle: { width: 40, height: 4, borderRadius: 2, backgroundColor: colors.textSecondary, alignSelf: 'center', marginBottom: spacing.lg, opacity: 0.4 },
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
  saveText: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: 'bold' },
});
