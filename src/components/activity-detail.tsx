import { View, Text, ScrollView, Pressable, Modal, StyleSheet, Alert, Share, Linking } from 'react-native';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';
import { useEffect, useLayoutEffect, useState } from 'react';
import { useNavigation, useRouter } from 'expo-router';
import dayjs from 'dayjs';
import { useTranslation } from 'react-i18next';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import * as Burnt from 'burnt';
import * as Location from 'expo-location';
import { Globe, Hand, Lock, MoreHorizontal, Pencil, Share2, Trash2, MapPinCheck } from 'lucide-react-native';
import { getFriendlyError } from '@/utils/friendly-error';
import { reliabilityService } from '@/services/reliability-service';
import { PresenceQrModal } from './presence-qr-modal';
import { PresenceScannerModal } from './presence-scanner-modal';
import { LeaveActivityModal } from './leave-activity-modal';
import { CancelActivityModal } from './cancel-activity-modal';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';
import { supabase } from '@/services/supabase';
import { activityService, type NearbyActivity } from '@/services/activity-service';
import { participationService, type Participation } from '@/services/participation-service';
import { getActivityTimeStatus, getStatusColor, getRemainingPlaces } from '@/utils/activity-status';
import { getSportIcon } from '@/constants/sport-icons';
import { JuntoMapView, type MapPin } from './map-view';
import { ParticipantList } from './participant-list';
import { ActivityWall } from './activity-wall';
import { ReportModal } from './report-modal';
import { TransportSection } from './transport-section';
import { transportService, type TransportSummary } from '@/services/transport-service';
import { Car, Bike, TrainFront, Footprints } from 'lucide-react-native';

interface ActivityDetailProps {
  activity: NearbyActivity;
  participation: Participation | null;
  isCreator: boolean;
  isAuthenticated: boolean;
  onJoinRedirect?: () => void;
}

export function ActivityDetail({
  activity,
  participation,
  isCreator,
  isAuthenticated,
  onJoinRedirect,
}: ActivityDetailProps) {
  const { t, i18n } = useTranslation();
  const router = useRouter();
  const navigation = useNavigation();
  const insets = useSafeAreaInsets();
  const queryClient = useQueryClient();
  const { data: transportSummary } = useQuery({
    queryKey: ['transport-summary', activity.id],
    queryFn: () => transportService.getSummary(activity.id),
  });

  const { data: currentUserId } = useQuery({
    queryKey: ['auth-user-id'],
    queryFn: async () => (await supabase.auth.getUser()).data.user?.id ?? null,
  });
  const [isLoading, setIsLoading] = useState(false);
  const [showMenu, setShowMenu] = useState(false);
  const [showReport, setShowReport] = useState(false);
  const [showFullMap, setShowFullMap] = useState(false);
  const [fullMapFly, setFullMapFly] = useState<{ coordinate: [number, number]; key: number } | null>(null);
  const [isAtActivity, setIsAtActivity] = useState(false);
  const [isConfirming, setIsConfirming] = useState(false);
  const [showQrModal, setShowQrModal] = useState(false);
  const [showScanner, setShowScanner] = useState(false);
  const [showLeaveModal, setShowLeaveModal] = useState(false);
  const [showCancelModal, setShowCancelModal] = useState(false);

  const startsAtMs2 = new Date(activity.starts_at).getTime();
  const isLateLeave = activity.requires_presence !== false
    && Date.now() > startsAtMs2 - 12 * 3600 * 1000;

  const isPrivateLink = activity.visibility === 'private_link' || activity.visibility === 'private_link_approval';
  const canShare = !isPrivateLink || isCreator;

  const timeStatus = getActivityTimeStatus(activity.starts_at, activity.status);
  const statusColor = getStatusColor(timeStatus);

  useLayoutEffect(() => {
    navigation.setOptions({
      headerRight: () => (
        <View style={{ flexDirection: 'row', alignItems: 'center', gap: spacing.xs }}>
          <View style={[styles.headerStatus, { backgroundColor: statusColor }]}>
            <Text style={styles.headerStatusText}>{t(`activity.status.${timeStatus}`)}</Text>
          </View>
          {canShare && (
            <Pressable onPress={handleShare} hitSlop={10} style={{ paddingHorizontal: spacing.sm }}>
              <Share2 size={22} color={colors.textPrimary} strokeWidth={2.2} />
            </Pressable>
          )}
          {isCreator && (
            <Pressable onPress={() => setShowMenu(true)} hitSlop={10} style={{ paddingHorizontal: spacing.sm }}>
              <MoreHorizontal size={24} color={colors.textPrimary} strokeWidth={2.2} />
            </Pressable>
          )}
        </View>
      ),
    });
  }, [navigation, isCreator, canShare, timeStatus, statusColor, t]);

  // Parse PG interval duration (e.g. "02:00:00" or "2 hours") into milliseconds
  const parseDurationMs = (d: string): number => {
    if (d.includes(':')) {
      const [h, m, s] = d.split(':').map(Number);
      return ((h ?? 0) * 3600 + (m ?? 0) * 60 + (s ?? 0)) * 1000;
    }
    const match = d.match(/(\d+)\s*hour/);
    return match ? parseInt(match[1]!, 10) * 3600 * 1000 : 2 * 3600 * 1000;
  };

  const formatDuration = (d: string): string => {
    const ms = parseDurationMs(d);
    const totalMinutes = Math.round(ms / 60000);
    const hours = Math.floor(totalMinutes / 60);
    const minutes = totalMinutes % 60;
    if (hours === 0) return `${minutes}min`;
    if (minutes === 0) return `${hours}h`;
    return `${hours}h${String(minutes).padStart(2, '0')}`;
  };

  const startsAtMs = new Date(activity.starts_at).getTime();
  const durationMs = parseDurationMs(activity.duration);
  const nowMs = Date.now();
  const requiresPresence = activity.requires_presence !== false;
  const isInPresenceWindow = requiresPresence && nowMs >= startsAtMs - 2 * 3600 * 1000 && nowMs <= startsAtMs + durationMs + 12 * 3600 * 1000;
  const isQrAvailable = requiresPresence && nowMs >= startsAtMs - 2 * 3600 * 1000 && nowMs <= startsAtMs + durationMs + 2 * 3600 * 1000;

  const remaining = getRemainingPlaces(activity.max_participants, activity.participant_count);

  const alreadyConfirmed = !!participation?.confirmed_present;
  const canCheckIn = !isCreator && participation?.status === 'accepted' && !alreadyConfirmed && isInPresenceWindow;

  // Passive geo detection: silently check if the user is at the activity location
  useEffect(() => {
    if (!canCheckIn) return;
    let cancelled = false;
    (async () => {
      const { status } = await Location.getForegroundPermissionsAsync();
      if (status !== 'granted') {
        const req = await Location.requestForegroundPermissionsAsync();
        if (req.status !== 'granted') return;
      }
      try {
        const pos = await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.Balanced });
        if (cancelled) return;
        const R = 6371000;
        const distFromTo = (lat1: number, lng1: number, lat2: number, lng2: number) => {
          const dLat = ((lat2 - lat1) * Math.PI) / 180;
          const dLng = ((lng2 - lng1) * Math.PI) / 180;
          const a =
            Math.sin(dLat / 2) ** 2 +
            Math.cos((lat1 * Math.PI) / 180) * Math.cos((lat2 * Math.PI) / 180) * Math.sin(dLng / 2) ** 2;
          return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        };
        const candidates: number[] = [
          distFromTo(pos.coords.latitude, pos.coords.longitude, activity.lat, activity.lng),
        ];
        if (activity.meeting_lat != null && activity.meeting_lng != null) {
          candidates.push(distFromTo(pos.coords.latitude, pos.coords.longitude, activity.meeting_lat, activity.meeting_lng));
        }
        if (activity.end_lat != null && activity.end_lng != null) {
          candidates.push(distFromTo(pos.coords.latitude, pos.coords.longitude, activity.end_lat, activity.end_lng));
        }
        const minDist = Math.min(...candidates);
        if (!cancelled) setIsAtActivity(minDist <= 150);
      } catch {
        // ignore
      }
    })();
    return () => { cancelled = true; };
  }, [canCheckIn, activity.lat, activity.lng]);

  const handleCheckIn = async () => {
    setIsConfirming(true);
    try {
      const { status } = await Location.getForegroundPermissionsAsync();
      if (status !== 'granted') {
        const req = await Location.requestForegroundPermissionsAsync();
        if (req.status !== 'granted') {
          Alert.alert(t('auth.error'), t('presence.locationPermissionDenied'));
          return;
        }
      }
      const pos = await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.High });
      await reliabilityService.confirmPresenceViaGeo(activity.id, pos.coords.longitude, pos.coords.latitude);
      await queryClient.invalidateQueries({ queryKey: ['participation', activity.id] });
      Burnt.toast({ title: t('presence.confirmed'), preset: 'done' });
    } catch (err) {
      Alert.alert(t('auth.error'), getFriendlyError(err, 'generic'));
    } finally {
      setIsConfirming(false);
    }
  };

  const handleJoin = async () => {
    if (!isAuthenticated) {
      onJoinRedirect?.();
      return;
    }
    setIsLoading(true);
    try {
      await participationService.join(activity.id);
      await queryClient.refetchQueries({ queryKey: ['participation', activity.id] });
      await queryClient.refetchQueries({ queryKey: ['activity', activity.id] });
      await queryClient.invalidateQueries({ queryKey: ['activities'] });
      const isApproval = activity.visibility === 'approval' || activity.visibility === 'private_link_approval';
      Burnt.toast({ title: t(isApproval ? 'toast.requestSent' : 'toast.joinedActivity'), preset: 'done' });
    } catch (err) {
      Alert.alert(t('auth.error'), getFriendlyError(err, 'joinActivity'));
    } finally {
      setIsLoading(false);
    }
  };

  const performLeave = async (reason?: string) => {
    setIsLoading(true);
    try {
      await participationService.leave(activity.id, reason);
      await queryClient.invalidateQueries({ queryKey: ['participation', activity.id] });
      await queryClient.invalidateQueries({ queryKey: ['activity', activity.id] });
      await queryClient.invalidateQueries({ queryKey: ['activities'] });
      Burnt.toast({ title: t('toast.leftActivity') });
      setShowLeaveModal(false);
    } catch (err) {
      Alert.alert(t('auth.error'), getFriendlyError(err, 'leaveActivity'));
    } finally {
      setIsLoading(false);
    }
  };

  const performCancel = async (reason: string) => {
    setIsLoading(true);
    try {
      await participationService.cancel(activity.id, reason);
      await queryClient.invalidateQueries({ queryKey: ['activities'] });
      Burnt.toast({ title: t('toast.activityCancelled') });
      setShowCancelModal(false);
    } catch (err) {
      Alert.alert(t('auth.error'), getFriendlyError(err, 'cancelActivity'));
    } finally {
      setIsLoading(false);
    }
  };

  const handleShare = async () => {
    try {
      const isPrivateLink = activity.visibility === 'private_link' || activity.visibility === 'private_link_approval';
      const webHost = process.env.EXPO_PUBLIC_JUNTO_WEB_HOST ?? 'junto-nine.vercel.app';
      let link: string;
      if (isPrivateLink) {
        // Only the creator can share private-link activities (token gated)
        const token = await activityService.getInviteToken(activity.id);
        if (!token) return;
        link = `https://${webHost}/invite/${token}`;
      } else {
        link = `https://${webHost}/activity/${activity.id}`;
      }
      const sportLabel = t(`sports.${activity.sport_key}`, activity.sport_key);
      const when = dayjs(activity.starts_at).format('ddd D MMM HH:mm');
      const message = `${activity.title}\n${sportLabel} · ${when}\n\n${t('activity.shareJoin')}\n${link}`;
      await Share.share({ message });
    } catch (err) {
      Alert.alert(t('auth.error'), getFriendlyError(err, 'generic'));
    }
  };

  const [activeTab, setActiveTab] = useState<'info' | 'organization' | 'chat'>('info');
  const canRejoin = participation && ['withdrawn', 'refused'].includes(participation.status);
  const isActive = ['published', 'in_progress'].includes(activity.status);
  const showJoinButton = !isCreator && (!participation || canRejoin) && remaining > 0 && activity.status === 'published';
  const showLeaveButton = !isCreator && participation && ['accepted', 'pending'].includes(participation.status) && isActive;
  const showCancelButton = isCreator && isActive;
  const isPending = participation?.status === 'pending';
  const isAccepted = participation?.status === 'accepted';

  const joinLabel = activity.visibility === 'approval' || activity.visibility === 'private_link_approval'
    ? t('activity.requestJoin')
    : t('activity.join');

  const showTabs = isCreator || isAccepted;

  const mapPins: MapPin[] = [
    ...(activity.start_lng && activity.start_lat
      ? [{ id: 'start', coordinate: [activity.start_lng, activity.start_lat] as [number, number], color: '#22c55e', label: t('activity.pinDepart') }]
      : []),
    ...(activity.meeting_lng && activity.meeting_lat
      ? [{ id: 'meeting', coordinate: [activity.meeting_lng, activity.meeting_lat] as [number, number], color: '#3b82f6', label: t('activity.pinRdv') }]
      : []),
    ...(activity.end_lng && activity.end_lat
      ? [{ id: 'end', coordinate: [activity.end_lng, activity.end_lat] as [number, number], color: '#ef4444', label: t('activity.pinArrivee') }]
      : []),
    ...(activity.objective_lng && activity.objective_lat
      ? [{ id: 'objective', coordinate: [activity.objective_lng, activity.objective_lat] as [number, number], color: '#F5A623', label: t('activity.pinObjectif') }]
      : []),
  ];
  const allLngs = mapPins.map((p) => p.coordinate[0]);
  const allLats = mapPins.map((p) => p.coordinate[1]);
  const mapCenter: [number, number] = [(Math.min(...allLngs) + Math.max(...allLngs)) / 2, (Math.min(...allLats) + Math.max(...allLats)) / 2];
  const mapSpread = Math.max(Math.max(...allLngs) - Math.min(...allLngs), Math.max(...allLats) - Math.min(...allLats));
  const mapZoom = mapSpread > 0.1 ? 10 : mapSpread > 0.01 ? 12 : 14;
  const mapRouteLine = activity.end_lng && activity.end_lat && activity.start_lng && activity.start_lat
    ? [[activity.start_lng, activity.start_lat], [activity.end_lng, activity.end_lat]] as [number, number][]
    : undefined;

  return (
    <View style={styles.container}>
      {/* Tab bar — only for participants/creator */}
      {showTabs && (
        <View style={styles.tabBar}>
          {(['info', 'organization', 'chat'] as const).map((tab) => (
            <Pressable
              key={tab}
              style={[styles.tab, activeTab === tab && styles.tabActive]}
              onPress={() => setActiveTab(tab)}
            >
              <Text style={[styles.tabText, activeTab === tab && styles.tabTextActive]}>
                {t(`activity.tab.${tab}`)}
              </Text>
              {tab === 'organization' && (canCheckIn || (isCreator && isQrAvailable)) && (
                <View style={styles.tabDot} />
              )}
            </Pressable>
          ))}
        </View>
      )}

      {/* ===== INFO TAB ===== */}
      {(!showTabs || activeTab === 'info') && (
        <ScrollView style={{ flex: 1 }} contentContainerStyle={styles.content}>
          <View style={styles.header}>
            <Text style={styles.sportIcon}>{getSportIcon(activity.sport_key)}</Text>
            <Text style={styles.sport}>{t(`sports.${activity.sport_key}`, activity.sport_key)}</Text>
            <View style={styles.visibilityBadge}>
              {activity.visibility === 'public' ? (
                <Globe size={12} color={colors.textSecondary} strokeWidth={2} />
              ) : activity.visibility === 'approval' ? (
                <Hand size={12} color={colors.textSecondary} strokeWidth={2} />
              ) : (
                <Lock size={12} color={colors.textSecondary} strokeWidth={2} />
              )}
              <Text style={styles.visibilityText}>{t(`create.visibility.${activity.visibility}`)}</Text>
            </View>
          </View>

          <View style={styles.titleRow}>
            <Text style={styles.title}>{activity.title}</Text>
          </View>

          {!isActive && (
            <View style={styles.inactiveBanner}>
              <Text style={styles.inactiveText}>{t(`activity.statusBanner.${activity.status}`)}</Text>
            </View>
          )}
          {isPending && isActive && (
            <View style={styles.pendingBanner}>
              <Text style={styles.pendingText}>{t('activity.pendingRequest')}</Text>
            </View>
          )}
          {isAccepted && !isCreator && isActive && (
            <View style={styles.acceptedBanner}>
              <Text style={styles.acceptedText}>{t('activity.youAreIn')}</Text>
            </View>
          )}

          <View style={styles.infoGrid}>
            <View style={styles.infoRow}>
              <Text style={styles.infoLabel}>{t('activity.level')}</Text>
              <Text style={styles.infoValue}>{activity.level}</Text>
            </View>
            <View style={styles.infoRow}>
              <Text style={styles.infoLabel}>{t('activity.starts')}</Text>
              <Text style={styles.infoValue}>
                {dayjs(activity.starts_at).locale(i18n.language).format('ddd D MMM')} {t('activity.at')} {dayjs(activity.starts_at).format('HH:mm')}
              </Text>
            </View>
            <View style={styles.infoRow}>
              <Text style={styles.infoLabel}>{t('activity.duration')}</Text>
              <Text style={styles.infoValue}>{formatDuration(activity.duration)}</Text>
            </View>
            <View style={styles.infoRow}>
              <Text style={styles.infoLabel}>{t('activity.places', { remaining, max: activity.max_participants })}</Text>
              <Text style={styles.infoValue}>{activity.participant_count}/{activity.max_participants}</Text>
            </View>
          </View>

          {/* Transport summary — cars only, seats + cities */}
          {(() => {
            const carSummary = (transportSummary ?? []).filter((s) => s.transport_type === 'car' || s.transport_type === 'carpool');
            const totalSeats = carSummary.reduce((sum, s) => sum + s.total_seats, 0);
            const allCities = carSummary.flatMap((s) => s.cities ?? []).filter(Boolean);
            if (carSummary.length === 0) return null;
            return (
              <View style={styles.transportSummary}>
                <Car size={16} color={colors.cta} strokeWidth={2} />
                <Text style={styles.transportSummaryText}>
                  : {totalSeats > 0 ? `${totalSeats} ${t('transport.seats')}` : t('transport.type.car').toLowerCase()}
                </Text>
                {allCities.length > 0 && (
                  <>
                    <Text style={{ color: colors.textSecondary }}> — </Text>
                    <MapPinCheck size={14} color={colors.textSecondary} strokeWidth={2} />
                    <Text style={styles.transportSummaryText}>
                      : {[...new Set(allCities)].join(', ')}
                    </Text>
                  </>
                )}
              </View>
            );
          })()}

          {activity.description ? (
            <View style={styles.section}>
              <Text style={styles.sectionTitle}>{t('activity.description')}</Text>
              <Text style={styles.description}>{activity.description}</Text>
            </View>
          ) : null}

          {showTabs && (
            <View style={styles.section}>
              <Text style={styles.sectionTitle}>{t('activity.location')}</Text>
              <Pressable style={styles.mapContainer} onPress={() => setShowFullMap(true)}>
                <JuntoMapView center={mapCenter} zoom={mapZoom} pins={mapPins} routeLine={mapRouteLine} />
                <View style={styles.mapTapOverlay} pointerEvents="box-only" />
              </Pressable>
            </View>
          )}

          <ParticipantList
            activityId={activity.id}
            activityTitle={activity.title}
            isCreator={isCreator}
            creatorId={activity.creator_id}
            creatorName={activity.creator_name}
            creatorAvatar={activity.creator_avatar}
            onProfilePress={!isAuthenticated ? () => onJoinRedirect?.() : undefined}
          />

          {/* Presence reminder banner on Info tab */}
          {canCheckIn && !alreadyConfirmed && (
            <Pressable style={styles.presenceReminder} onPress={() => setActiveTab('organization')}>
              <MapPinCheck size={16} color={colors.cta} strokeWidth={2.4} />
              <Text style={styles.presenceReminderText}>{t('presence.confirmMyPresence')}</Text>
            </Pressable>
          )}

          {alreadyConfirmed && !isCreator && (
            <View style={styles.presenceDone}>
              <MapPinCheck size={16} color={colors.success} strokeWidth={2.4} />
              <Text style={styles.presenceDoneText}>{t('presence.alreadyConfirmed')}</Text>
            </View>
          )}

          {showJoinButton && (
            <Pressable
              style={[styles.joinButton, isLoading && styles.buttonDisabled]}
              onPress={handleJoin}
              disabled={isLoading}
            >
              <Text style={styles.buttonText}>{isLoading ? '...' : joinLabel}</Text>
            </Pressable>
          )}

          {showLeaveButton && (
            <Pressable
              style={[styles.leaveButton, isLoading && styles.buttonDisabled]}
              onPress={() => setShowLeaveModal(true)}
              disabled={isLoading}
            >
              <Text style={styles.buttonText}>{isLoading ? '...' : t('activity.leave')}</Text>
            </Pressable>
          )}

          {!isCreator && isAuthenticated && (
            <Pressable style={styles.reportLink} onPress={() => setShowReport(true)}>
              <Text style={styles.reportLinkText}>{t('report.reportActivity')}</Text>
            </Pressable>
          )}
        </ScrollView>
      )}

      {/* ===== ORGANIZATION TAB ===== */}
      {showTabs && activeTab === 'organization' && (
        <ScrollView style={{ flex: 1 }} contentContainerStyle={styles.content}>
          {/* Presence verification */}
          {canCheckIn && (
            <View style={[styles.presenceBlock, isAtActivity && styles.presenceBlockActive]}>
              <View style={styles.presenceHeader}>
                <MapPinCheck size={18} color={isAtActivity ? colors.success : colors.textPrimary} strokeWidth={2.4} />
                <Text style={styles.presenceTitle}>
                  {isAtActivity ? t('presence.atActivity') : t('presence.confirmMyPresence')}
                </Text>
              </View>
              <Text style={styles.presenceSubtitle}>
                {isAtActivity ? t('presence.atActivitySubtitle') : t('presence.mustBeAtLocation')}
              </Text>
              <View style={styles.presenceActions}>
                <Pressable
                  style={[styles.presenceButton, isConfirming && styles.buttonDisabled]}
                  onPress={handleCheckIn}
                  disabled={isConfirming}
                >
                  <Text style={styles.presenceButtonText} numberOfLines={1}>
                    {isConfirming ? '...' : t('presence.confirm')}
                  </Text>
                </Pressable>
                <Pressable style={styles.presenceSecondaryButton} onPress={() => setShowScanner(true)}>
                  <Text style={styles.presenceSecondaryText}>{t('presence.scanQr')}</Text>
                </Pressable>
              </View>
            </View>
          )}

          {isCreator && isQrAvailable && (
            <Pressable style={styles.presenceCreatorButton} onPress={() => setShowQrModal(true)}>
              <Text style={styles.presenceCreatorText}>{t('presence.showQr')}</Text>
            </Pressable>
          )}

          {alreadyConfirmed && !isCreator && (
            <View style={styles.presenceDone}>
              <MapPinCheck size={16} color={colors.success} strokeWidth={2.4} />
              <Text style={styles.presenceDoneText}>{t('presence.alreadyConfirmed')}</Text>
            </View>
          )}

          {/* Transport */}
          <TransportSection activityId={activity.id} currentUserId={currentUserId ?? null} />

          {/* Gear placeholder */}
          <View style={styles.section}>
            <Text style={styles.sectionTitle}>{t('activity.gear')}</Text>
            <Text style={styles.comingSoon}>{t('activity.comingSoon')}</Text>
          </View>
        </ScrollView>
      )}

      {/* ===== CHAT TAB ===== */}
      {showTabs && activeTab === 'chat' && (
        <View style={{ flex: 1, padding: spacing.lg }}>
          <ActivityWall
            activityId={activity.id}
            isActive={['published', 'in_progress'].includes(activity.status)}
          />
        </View>
      )}

      {/* Modals — shared across all tabs */}
      <Modal visible={showFullMap} animationType="slide" onRequestClose={() => setShowFullMap(false)}>
        <SafeAreaView style={styles.fullMapContainer} edges={['top']}>
          <JuntoMapView
            center={mapCenter}
            zoom={mapZoom}
            pins={mapPins}
            routeLine={mapRouteLine}
            flyTo={fullMapFly}
            onPinPress={(pin) => setFullMapFly({ coordinate: pin.coordinate, key: Date.now() })}
          />
          <Pressable style={styles.closeMapButton} onPress={() => setShowFullMap(false)}>
            <Text style={styles.closeMapText}>✕</Text>
          </Pressable>
          <Pressable
            style={[styles.navigateButton, { bottom: insets.bottom + 24 }]}
            onPress={() => {
              const navLat = activity.meeting_lat ?? activity.lat;
              const navLng = activity.meeting_lng ?? activity.lng;
              Linking.openURL(`https://www.google.com/maps/dir/?api=1&destination=${navLat},${navLng}`);
            }}
          >
            <Text style={styles.navigateText}>{t('activity.navigate')}</Text>
          </Pressable>
        </SafeAreaView>
      </Modal>

      <PresenceQrModal visible={showQrModal} activityId={activity.id} onClose={() => setShowQrModal(false)} />
      <PresenceScannerModal visible={showScanner} onClose={() => setShowScanner(false)} />
      <LeaveActivityModal
        visible={showLeaveModal}
        isLate={isLateLeave}
        isSubmitting={isLoading}
        onCancel={() => setShowLeaveModal(false)}
        onConfirm={performLeave}
      />
      <CancelActivityModal
        visible={showCancelModal}
        isSubmitting={isLoading}
        onCancel={() => setShowCancelModal(false)}
        onConfirm={performCancel}
      />
      <ReportModal
        visible={showReport}
        targetType="activity"
        targetId={activity.id}
        onClose={() => setShowReport(false)}
      />

      {showMenu && (
        <Modal visible animationType="none" transparent>
          <Pressable style={styles.tooltipBackdrop} onPress={() => setShowMenu(false)}>
            <View style={styles.tooltip}>
              {isActive && (
                <Pressable style={styles.tooltipItem} onPress={() => { setShowMenu(false); router.push(`/(auth)/edit/${activity.id}`); }}>
                  <Pencil size={20} color={colors.textPrimary} strokeWidth={2} />
                </Pressable>
              )}
              {showCancelButton && (
                <Pressable style={styles.tooltipItem} onPress={() => { setShowMenu(false); setShowCancelModal(true); }}>
                  <Trash2 size={20} color={colors.error} strokeWidth={2} />
                </Pressable>
              )}
            </View>
          </Pressable>
        </Modal>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  content: { padding: spacing.lg, paddingBottom: spacing.xl + 32 },
  tabBar: {
    flexDirection: 'row', paddingHorizontal: spacing.md, paddingTop: spacing.sm,
    paddingBottom: spacing.xs, gap: spacing.sm, backgroundColor: colors.background,
  },
  tab: {
    flex: 1, flexDirection: 'row', alignItems: 'center', justifyContent: 'center',
    gap: 4, paddingVertical: spacing.sm, borderRadius: radius.full, backgroundColor: colors.surface,
  },
  tabActive: { backgroundColor: colors.cta, borderWidth: 2, borderColor: colors.cta },
  tabText: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: '600' },
  tabTextActive: { color: colors.textPrimary, fontWeight: 'bold' },
  tabDot: { width: 6, height: 6, borderRadius: 3, backgroundColor: colors.cta },
  presenceReminder: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.sm,
    backgroundColor: colors.cta + '15', borderRadius: radius.md,
    padding: spacing.md, marginTop: spacing.md,
  },
  presenceReminderText: { color: colors.cta, fontSize: fontSizes.sm, fontWeight: '600' },
  comingSoon: { color: colors.textSecondary, fontSize: fontSizes.sm, fontStyle: 'italic' },
  transportSummary: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.sm,
    backgroundColor: colors.cta + '15', borderRadius: radius.md,
    padding: spacing.sm, marginBottom: spacing.md,
  },
  transportSummaryText: { color: colors.textPrimary, fontSize: fontSizes.sm },
  header: { flexDirection: 'row', alignItems: 'center', marginBottom: spacing.lg, gap: spacing.sm },
  headerStatus: { paddingHorizontal: spacing.sm, paddingVertical: 4, borderRadius: radius.full },
  headerStatusText: { color: colors.textPrimary, fontSize: fontSizes.xs - 1, fontWeight: 'bold' },
  sportIcon: { fontSize: 20 },
  sport: { color: colors.textSecondary, fontSize: fontSizes.sm, textTransform: 'capitalize' },
  visibilityBadge: { flexDirection: 'row', alignItems: 'center', gap: 4, backgroundColor: colors.surface, borderRadius: radius.full, paddingHorizontal: spacing.sm, paddingVertical: 4, marginLeft: 'auto' },
  visibilityText: { color: colors.textSecondary, fontSize: fontSizes.xs },
  separator: { height: 1, backgroundColor: colors.surface, marginVertical: spacing.md },
  titleRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginBottom: spacing.md },
  title: { color: colors.textPrimary, fontSize: fontSizes.xl, fontWeight: 'bold', flex: 1 },
  inactiveBanner: { backgroundColor: colors.textSecondary + '20', borderRadius: radius.lg, padding: spacing.md, marginBottom: spacing.md },
  inactiveText: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: 'bold', textAlign: 'center' },
  pendingBanner: { backgroundColor: colors.warning + '20', borderRadius: radius.lg, padding: spacing.md, marginBottom: spacing.md },
  pendingText: { color: colors.warning, fontSize: fontSizes.sm, fontWeight: 'bold', textAlign: 'center' },
  acceptedBanner: { backgroundColor: colors.success + '20', borderRadius: radius.lg, padding: spacing.md, marginBottom: spacing.md },
  acceptedText: { color: colors.success, fontSize: fontSizes.sm, fontWeight: 'bold', textAlign: 'center' },
  infoGrid: {
    backgroundColor: colors.surface, borderRadius: radius.lg, padding: spacing.md, marginBottom: spacing.lg, gap: spacing.sm,
    elevation: 3, shadowColor: '#000', shadowOffset: { width: 0, height: 2 }, shadowOpacity: 0.25, shadowRadius: 4,
  },
  infoRow: { flexDirection: 'row', justifyContent: 'space-between' },
  infoLabel: { color: colors.textSecondary, fontSize: fontSizes.sm },
  infoValue: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: 'bold' },
  section: { marginBottom: spacing.lg },
  sectionTitle: { color: colors.textPrimary, fontSize: fontSizes.xs, fontWeight: 'bold', letterSpacing: 0.5, marginBottom: spacing.sm, textTransform: 'uppercase' },
  description: { color: colors.textPrimary, fontSize: fontSizes.md, lineHeight: 22 },
  mapContainer: {
    height: 200, borderRadius: radius.lg, overflow: 'hidden',
    elevation: 3, shadowColor: '#000', shadowOffset: { width: 0, height: 2 }, shadowOpacity: 0.25, shadowRadius: 4,
  },
  mapTapOverlay: { ...StyleSheet.absoluteFillObject },
  fullMapContainer: { flex: 1, backgroundColor: colors.background },
  closeMapButton: { position: 'absolute', top: 35, left: 20, width: 40, height: 40, borderRadius: 20, backgroundColor: colors.background, alignItems: 'center', justifyContent: 'center', zIndex: 10 },
  closeMapText: { color: colors.textPrimary, fontSize: 18, fontWeight: 'bold' },
  navigateButton: { position: 'absolute', alignSelf: 'center', backgroundColor: colors.cta, borderRadius: radius.full, paddingHorizontal: spacing.xl, paddingVertical: spacing.md, zIndex: 10 },
  navigateText: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: 'bold' },
  presenceBlock: {
    backgroundColor: colors.surface, borderRadius: radius.lg, padding: spacing.md,
    marginTop: spacing.md, marginBottom: spacing.md, gap: spacing.sm,
    borderWidth: 1, borderColor: colors.surface,
  },
  presenceBlockActive: {
    borderColor: colors.success, backgroundColor: colors.success + '20',
  },
  presenceHeader: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
  presenceTitle: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: 'bold' },
  presenceSubtitle: { color: colors.textSecondary, fontSize: fontSizes.xs },
  presenceActions: { flexDirection: 'row', gap: spacing.sm, marginTop: spacing.xs },
  presenceButton: {
    flex: 1, backgroundColor: colors.cta, borderRadius: radius.full,
    paddingVertical: spacing.sm, alignItems: 'center',
  },
  presenceButtonText: { color: colors.textPrimary, fontSize: fontSizes.xs, fontWeight: 'bold' },
  presenceSecondaryButton: {
    flex: 1, backgroundColor: 'transparent', borderRadius: radius.full,
    paddingVertical: spacing.sm, alignItems: 'center',
    borderWidth: 1, borderColor: colors.textPrimary,
  },
  presenceSecondaryText: { color: colors.textPrimary, fontSize: fontSizes.xs, fontWeight: 'bold' },
  presenceCreatorButton: {
    backgroundColor: colors.surface, borderRadius: radius.full,
    paddingVertical: spacing.md, alignItems: 'center',
    marginTop: spacing.sm, marginBottom: spacing.sm,
    borderWidth: 1, borderColor: colors.cta,
  },
  presenceCreatorText: { color: colors.cta, fontSize: fontSizes.sm, fontWeight: 'bold' },
  presenceDone: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'center',
    gap: spacing.xs, marginTop: spacing.sm, marginBottom: spacing.sm,
  },
  presenceDoneText: { color: colors.success, fontSize: fontSizes.sm, fontWeight: 'bold' },
  joinButton: { backgroundColor: colors.cta, borderRadius: radius.full, paddingVertical: spacing.md, alignItems: 'center', marginTop: spacing.md },
  leaveButton: { backgroundColor: colors.surface, borderRadius: radius.full, paddingVertical: spacing.md, alignItems: 'center', marginTop: spacing.md, borderWidth: 1, borderColor: colors.textSecondary },
  buttonDisabled: { opacity: 0.4 },
  buttonText: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: 'bold' },
  reportLink: { paddingVertical: spacing.sm, alignItems: 'center', marginTop: spacing.md },
  reportLinkText: { color: colors.textSecondary, fontSize: fontSizes.xs },
  tooltipBackdrop: { flex: 1 },
  tooltip: {
    position: 'absolute', top: 90, right: spacing.lg,
    flexDirection: 'row', gap: spacing.sm,
    backgroundColor: colors.surface, borderRadius: radius.full,
    paddingHorizontal: spacing.sm, paddingVertical: spacing.xs,
    elevation: 5, shadowColor: '#000', shadowOffset: { width: 0, height: 2 }, shadowOpacity: 0.3, shadowRadius: 4,
  },
  tooltipItem: { width: 36, height: 36, borderRadius: 18, alignItems: 'center', justifyContent: 'center' },
  tooltipIcon: { fontSize: 18 },
  tooltipIconDanger: { fontSize: 18, color: colors.error, fontWeight: 'bold' },
});
