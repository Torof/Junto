import { View, Text, Pressable, Modal, StyleSheet, TextInput, KeyboardAvoidingView, Platform, ScrollView } from 'react-native';
import { useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import { Car, Bike, TrainFront, Footprints, HelpCircle, MapPin } from 'lucide-react-native';
import * as Burnt from 'burnt';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';
import { transportService, type ParticipantTransport } from '@/services/transport-service';
import { UserAvatar } from './user-avatar';

interface Props {
  activityId: string;
  currentUserId: string | null;
}

const TRANSPORT_TYPES = ['car', 'carpool', 'public_transport', 'bike', 'on_foot', 'other'] as const;

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
  const [showEditor, setShowEditor] = useState(false);
  const [selectedType, setSelectedType] = useState<string | null>(null);
  const [seats, setSeats] = useState(0);
  const [fromName, setFromName] = useState('');
  const [isSaving, setIsSaving] = useState(false);

  const { data: participants } = useQuery({
    queryKey: ['transport', activityId],
    queryFn: () => transportService.getForActivity(activityId),
  });

  const { data: pendingSeatRequests } = useQuery({
    queryKey: ['seat-requests', activityId],
    queryFn: () => transportService.getPendingSeatRequests(activityId),
  });

  const hasPendingRequest = (driverId: string) =>
    (pendingSeatRequests ?? []).some((r) => r.driver_id === driverId && r.requester_id === currentUserId);

  const myTransport = (participants ?? []).find((p) => p.user_id === currentUserId);
  const hasSetTransport = !!myTransport;

  const handleSave = async () => {
    if (!selectedType) return;
    setIsSaving(true);
    try {
      await transportService.setTransport(
        activityId,
        selectedType,
        ['car', 'carpool'].includes(selectedType) ? seats : null,
        fromName.trim() || null,
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

  const openEditor = () => {
    if (myTransport) {
      setSelectedType(myTransport.transport_type);
      setSeats(myTransport.transport_seats ?? 0);
      setFromName(myTransport.transport_from_name ?? '');
    } else {
      setSelectedType(null);
      setSeats(0);
      setFromName('');
    }
    setShowEditor(true);
  };

  const grouped = TRANSPORT_TYPES.reduce((acc, type) => {
    const items = (participants ?? []).filter((p) => p.transport_type === type);
    if (items.length > 0) acc.push({ type, items });
    return acc;
  }, [] as { type: string; items: ParticipantTransport[] }[]);

  return (
    <View style={styles.section}>
      <View style={styles.headerRow}>
        <Text style={styles.sectionTitle}>{t('activity.transport')}</Text>
        <Pressable onPress={openEditor}>
          <Text style={styles.editLink}>
            {hasSetTransport ? t('transport.edit') : t('transport.add')}
          </Text>
        </Pressable>
      </View>

      {grouped.length === 0 ? (
        <Pressable onPress={openEditor}>
          <Text style={styles.emptyText}>{t('transport.empty')}</Text>
        </Pressable>
      ) : (
        grouped.map(({ type, items }) => {
          const IconComp = TRANSPORT_ICONS[type] ?? HelpCircle;
          return (
            <View key={type} style={styles.group}>
              <View style={styles.groupHeader}>
                <IconComp size={16} color={colors.textSecondary} strokeWidth={2} />
                <Text style={styles.groupLabel}>{t(`transport.type.${type}`)}</Text>
                <Text style={styles.groupCount}>{items.length}</Text>
              </View>
              {items.map((p) => (
                <View key={p.user_id} style={styles.participantRow}>
                  <UserAvatar name={p.display_name} avatarUrl={p.avatar_url} size={28} />
                  <Text style={styles.participantName} numberOfLines={1}>{p.display_name}</Text>
                  {p.transport_from_name && (
                    <View style={{ flexDirection: 'row', alignItems: 'center', gap: 2 }}>
                      <MapPin size={12} color={colors.textSecondary} strokeWidth={2} />
                      <Text style={styles.fromCity} numberOfLines={1}>{p.transport_from_name}</Text>
                    </View>
                  )}
                  {p.transport_seats != null && p.transport_seats > 0 && (
                    <Text style={styles.seatsBadge}>{p.transport_seats} {t('transport.seats')}</Text>
                  )}
                  {p.transport_type != null && ['car', 'carpool'].includes(p.transport_type) && p.transport_seats != null && p.transport_seats > 0 && p.user_id !== currentUserId && !hasPendingRequest(p.user_id) && (
                    <Pressable
                      style={styles.requestSeatBtn}
                      onPress={async () => {
                        try {
                          await transportService.requestSeat(activityId, p.user_id);
                          await queryClient.invalidateQueries({ queryKey: ['seat-requests', activityId] });
                          Burnt.toast({ title: t('transport.seatRequested'), preset: 'done' });
                        } catch {
                          Burnt.toast({ title: t('auth.unknownError') });
                        }
                      }}
                    >
                      <Text style={styles.requestSeatText}>{t('transport.requestSeat')}</Text>
                    </Pressable>
                  )}
                  {p.transport_type != null && ['car', 'carpool'].includes(p.transport_type) && p.user_id !== currentUserId && hasPendingRequest(p.user_id) && (
                    <Text style={styles.requestSentLabel}>{t('transport.seatRequested')}</Text>
                  )}
                </View>
              ))}
            </View>
          );
        })
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

            {selectedType && ['car', 'carpool'].includes(selectedType) && (
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
    </View>
  );
}

const styles = StyleSheet.create({
  section: { marginBottom: spacing.lg },
  headerRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: spacing.sm },
  sectionTitle: {
    color: colors.textSecondary, fontSize: fontSizes.xs, fontWeight: 'bold',
    letterSpacing: 0.8, textTransform: 'uppercase',
  },
  editLink: { color: colors.cta, fontSize: fontSizes.xs, fontWeight: '600' },
  emptyText: { color: colors.textSecondary, fontSize: fontSizes.sm, fontStyle: 'italic' },
  group: { marginBottom: spacing.sm },
  groupHeader: { flexDirection: 'row', alignItems: 'center', gap: spacing.xs, marginBottom: spacing.xs },
  groupLabel: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '600', flex: 1 },
  groupCount: { color: colors.textSecondary, fontSize: fontSizes.xs },
  participantRow: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.sm,
    paddingVertical: spacing.xs, paddingLeft: spacing.lg,
  },
  participantName: { color: colors.textPrimary, fontSize: fontSizes.sm, flex: 1 },
  fromCity: { color: colors.textSecondary, fontSize: fontSizes.xs },
  seatsBadge: {
    color: colors.cta, fontSize: fontSizes.xs, fontWeight: 'bold',
    backgroundColor: colors.cta + '20', borderRadius: radius.full,
    paddingHorizontal: spacing.xs, paddingVertical: 2,
  },
  requestSeatBtn: {
    backgroundColor: colors.cta, borderRadius: radius.full,
    paddingHorizontal: spacing.sm, paddingVertical: 4,
  },
  requestSeatText: { color: colors.textPrimary, fontSize: fontSizes.xs - 1, fontWeight: 'bold' },
  requestSentLabel: { color: colors.textSecondary, fontSize: fontSizes.xs - 1, fontStyle: 'italic' },
  backdrop: { flex: 1, backgroundColor: 'rgba(0,0,0,0.5)', justifyContent: 'flex-end' },
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
  saveButton: {
    backgroundColor: colors.cta, borderRadius: radius.md,
    paddingVertical: spacing.md, alignItems: 'center', marginTop: spacing.sm,
  },
  saveText: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: 'bold' },
});
