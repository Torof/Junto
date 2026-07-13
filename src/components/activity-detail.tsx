import { View, Text, ScrollView, Pressable, Modal, StyleSheet, Alert, Share, Linking, Platform } from 'react-native';
import Animated from 'react-native-reanimated';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { useFocusEffect, useNavigation, useRouter } from 'expo-router';
import dayjs from 'dayjs';
import { useTranslation } from 'react-i18next';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import * as Burnt from 'burnt';
import * as Location from 'expo-location';
import * as DocumentPicker from 'expo-document-picker';
import { File } from 'expo-file-system';
import { parseGpxToGeoJson, GpxParseError } from '@/utils/parse-gpx';
import { haptic } from '@/lib/haptics';
import { Globe, Hand, Lock, MoreHorizontal, Pencil, Share2, Trash2, MapPinCheck, BarChart3, Calendar, Clock, Users, Route, Mountain, MapPin as MapPinIcon, Flag, X as XIcon, Navigation, Car, Maximize2 } from 'lucide-react-native';
import { getFriendlyError } from '@/utils/friendly-error';
import { reliabilityService } from '@/services/reliability-service';
import { PresenceQrModal } from './presence-qr-modal';
import { PresenceScannerModal } from './presence-scanner-modal';
import { LeaveActivityModal } from './leave-activity-modal';
import { CancelActivityModal } from './cancel-activity-modal';
import { fontSizes, fonts, spacing, radius } from '@/constants/theme';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import { supabase } from '@/services/supabase';
import { activityService, type NearbyActivity } from '@/services/activity-service';
import { sportCategoryColor } from '@/utils/sport-category-color';
import { participationService, type Participation } from '@/services/participation-service';
import { getActivityTimeStatus, getStatusColor, getRemainingPlaces } from '@/utils/activity-status';
import { formatLevelRange } from '@/constants/sport-levels';
import { JuntoMapView, type MapPin } from './map-view';
import { MapLegend } from './map-legend';
import { TraceDrawModal } from './trace-draw-modal';
import { ParticipantList } from './participant-list';
import { OrganizerCard } from './organizer-card';
import { ActivityWall } from './activity-wall';
import { wallService } from '@/services/wall-service';
import { useMessageStore } from '@/store/message-store';
import { ReportModal } from './report-modal';
import { ShareActivitySheet } from './share-activity-sheet';
import Svg, { Defs, LinearGradient as SvgLinearGradient, Stop, Rect } from 'react-native-svg';
import { getSportIcon } from '@/constants/sport-icons';
import { TransportSection, type TransportSectionHandle } from './transport-section';
import { GearSection, type GearSectionHandle } from './gear-section';
import { MyOutingCard, type MyOutingCardHandle } from './my-outing-card';
import { GroupCard } from './group-card';
import { ActivityDescription } from './activity-description';
import { transportService } from '@/services/transport-service';
import { distanceMeters, distanceToPolylineMeters } from '@/utils/geo';
import { useKeyboardDockPadding } from '@/hooks/use-keyboard-dock-padding';

interface ActivityDetailProps {
  activity: NearbyActivity;
  participation: Participation | null;
  isCreator: boolean;
  isAuthenticated: boolean;
  onJoinRedirect?: () => void;
}

// Per-session memory of activities whose creator QR has already been
// auto-opened. Prevents re-opening the modal when the user dismisses
// it, navigates away, and returns to the same activity later in the
// session. Resets on app restart — a fresh launch gets a fresh shot
// at the auto-show.
const autoShownQrFor = new Set<string>();

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
  const chatDockPadding = useKeyboardDockPadding(Math.max(spacing.lg, insets.bottom + spacing.xs));
  const queryClient = useQueryClient();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { data: transportSummary } = useQuery({
    queryKey: ['transport-summary', activity.id],
    queryFn: () => transportService.getSummary(activity.id),
  });
  // Org-tab transport list and wall messages are only consumed by
  // participants/creator (the org tab is gated, the unread badge sits
  // on the chat tab which non-participants can't reach). Skip the
  // fetch + 30s wall poll for non-participant viewers.
  const isAccepted = participation?.status === 'accepted';
  const { data: orgTransportParticipants } = useQuery({
    queryKey: ['transport', activity.id],
    queryFn: () => transportService.getForActivity(activity.id),
    enabled: isAuthenticated && (isCreator || isAccepted),
  });
  const { data: wallMessages } = useQuery({
    queryKey: ['wall', activity.id],
    queryFn: () => wallService.getMessages(activity.id),
    refetchInterval: 30000,
    enabled: isAuthenticated && (isCreator || isAccepted),
  });
  const wallReadAt = useMessageStore((s) => s.getWallReadAt(activity.id));

  const { data: currentUserId } = useQuery({
    queryKey: ['auth-user-id'],
    queryFn: async () => (await supabase.auth.getUser()).data.user?.id ?? null,
  });

  const wallUnreadCount = useMemo(() => {
    if (!wallMessages || !currentUserId) return 0;
    return wallMessages.filter((m) =>
      m.user_id !== currentUserId
      && (!wallReadAt || m.created_at > wallReadAt),
    ).length;
  }, [wallMessages, wallReadAt, currentUserId]);

  // Realtime invalidation for the activity's coordination tables. One
  // channel per activity (`activity:<id>`).
  //
  // - participations / seat_requests come in via Supabase broadcast,
  //   fired by the AFTER triggers added in migration 00182. Their
  //   table-level SELECT RLS is too restrictive for postgres_changes
  //   (only the row's user_id can see participations; only the
  //   requester/driver can see seat_requests under one of two
  //   policies), so we route around RLS by broadcasting a no-payload
  //   "stale" ping. Clients invalidate and refetch through the
  //   already-RLS-protected views/RPCs.
  //
  // - activity_gear stays on postgres_changes — its RLS already lets
  //   any accepted activity member see all rows for the activity.
  //
  // - wall_messages keeps its own subscription inside activity-wall.tsx.
  useEffect(() => {
    const channel = supabase
      .channel(`activity:${activity.id}`, { config: { private: true } })
      .on(
        'broadcast',
        { event: 'change' },
        (msg) => {
          const table = (msg.payload as { table?: string } | undefined)?.table;
          if (table === 'participations') {
            queryClient.invalidateQueries({ queryKey: ['transport', activity.id] });
            queryClient.invalidateQueries({ queryKey: ['transport-summary', activity.id] });
            queryClient.invalidateQueries({ queryKey: ['participants', activity.id] });
            queryClient.invalidateQueries({ queryKey: ['participants-pending', activity.id] });
            queryClient.invalidateQueries({ queryKey: ['participants-late-leavers', activity.id] });
            // Caller's own participation row — driven by external changes
            // (creator removes them, lazy transition flips status,
            // accept_seat_request nulls transport_*, peer_validate flips
            // confirmed_present). Without this, the screen-level query in
            // app/(auth)/activity/[id].tsx stays stale until manual refresh.
            queryClient.invalidateQueries({ queryKey: ['participation', activity.id] });
          } else if (table === 'seat_requests') {
            queryClient.invalidateQueries({ queryKey: ['seat-requests', activity.id] });
            queryClient.invalidateQueries({ queryKey: ['seat-requests-accepted', activity.id] });
            queryClient.invalidateQueries({ queryKey: ['transport-summary', activity.id] });
          }
        },
      )
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'activity_gear', filter: `activity_id=eq.${activity.id}` },
        () => {
          queryClient.invalidateQueries({ queryKey: ['activity-gear', activity.id] });
          // The shared-gear trigger (00303) may have auto-cleared a missing tile.
          queryClient.invalidateQueries({ queryKey: ['gear-missing', activity.id] });
        },
      )
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'activity_gear_missing', filter: `activity_id=eq.${activity.id}` },
        () => {
          queryClient.invalidateQueries({ queryKey: ['gear-missing', activity.id] });
        },
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [activity.id, queryClient]);

  // Reconcile shared caches whenever the screen regains focus — covers
  // the gap where the realtime channel was disconnected (background,
  // network blip) and a broadcast was missed while the user was away.
  useFocusEffect(
    useCallback(() => {
      queryClient.invalidateQueries({ queryKey: ['participants', activity.id] });
      queryClient.invalidateQueries({ queryKey: ['transport', activity.id] });
      queryClient.invalidateQueries({ queryKey: ['transport-summary', activity.id] });
      queryClient.invalidateQueries({ queryKey: ['participation', activity.id] });
    }, [activity.id, queryClient]),
  );
  const [isLoading, setIsLoading] = useState(false);
  const [showMenu, setShowMenu] = useState(false);
  const [showReport, setShowReport] = useState(false);
  const [showFullMap, setShowFullMap] = useState(false);
  const [drawTraceOpen, setDrawTraceOpen] = useState(false);
  const [fullMapFly, setFullMapFly] = useState<{ coordinate: [number, number]; key: number; zoom?: number } | null>(null);
  const [isAtActivity, setIsAtActivity] = useState(false);
  // Foreground distance to the nearest meeting point. null until the
  // first position fix lands; surfaced in the presence widget so a
  // user fails-loud at 160m rather than wondering why nothing
  // confirms automatically.
  const [distanceToActivityM, setDistanceToActivityM] = useState<number | null>(null);
  const [isConfirming, setIsConfirming] = useState(false);
  const [showQrModal, setShowQrModal] = useState(false);
  const [showScanner, setShowScanner] = useState(false);
  const [showLeaveModal, setShowLeaveModal] = useState(false);
  const [showCancelModal, setShowCancelModal] = useState(false);
  const [showShareSheet, setShowShareSheet] = useState(false);

  const startsAtMs2 = new Date(activity.starts_at).getTime();
  const isLateLeave = activity.requires_presence !== false
    && Date.now() > startsAtMs2 - 12 * 3600 * 1000;

  const isPrivateLink = activity.visibility === 'private_link' || activity.visibility === 'private_link_approval';
  const canShare = !isPrivateLink || isCreator;

  const timeStatus = getActivityTimeStatus(activity.starts_at, activity.status);
  const statusColor = getStatusColor(timeStatus);

  const handleShare = useCallback(async () => {
    try {
      // Canonical share host (Scott 2026-07-06): getjunto.app — the only host
      // wired into the Android intentFilters / iOS associatedDomains.
      const webHost = process.env.EXPO_PUBLIC_JUNTO_WEB_HOST ?? 'getjunto.app';
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
      const when = dayjs(activity.starts_at).format('ddd D MMM H[h]mm');
      const message = `${activity.title}\n${sportLabel} · ${when}\n\n${t('activity.shareJoin')}\n${link}`;
      await Share.share({ message });
    } catch (err) {
      Alert.alert(t('auth.error'), getFriendlyError(err, 'generic'));
    }
  }, [isPrivateLink, activity.id, activity.sport_key, activity.starts_at, activity.title, t]);

  useLayoutEffect(() => {
    navigation.setOptions({
      // Info first (twin pills: status + visibility), a real gap, then the
      // actions at the edge with matching sizes.
      headerRight: () => (
        <View style={{ flexDirection: 'row', alignItems: 'center', gap: spacing.xs + 3 }}>
          <View style={[styles.headerStatus, { backgroundColor: statusColor }]}>
            <Text style={styles.headerStatusText}>{t(`activity.status.${timeStatus}`)}</Text>
          </View>
          <View style={styles.headerVisPill}>
            {activity.visibility === 'public' ? (
              <Globe size={14} color={colors.textSecondary} strokeWidth={2.2} />
            ) : activity.visibility === 'approval' ? (
              <Hand size={14} color={colors.textSecondary} strokeWidth={2.2} />
            ) : (
              <Lock size={14} color={colors.textSecondary} strokeWidth={2.2} />
            )}
            <Text style={styles.headerVisText} numberOfLines={1}>
              {t(`create.visibility.${activity.visibility}`)}
            </Text>
          </View>
          <View style={{ width: spacing.lg }} />
          {canShare && (
            <Pressable
              onPress={() => isPrivateLink ? handleShare() : setShowShareSheet(true)}
              hitSlop={10}
              style={{ paddingHorizontal: spacing.sm - 2 }}
              accessibilityLabel={t('activity.shareCta', { defaultValue: 'Share activity' })}
            >
              <Share2 size={21} color={colors.textPrimary} strokeWidth={2.2} />
            </Pressable>
          )}
          {isCreator && (
            <Pressable
              onPress={() => setShowMenu(true)}
              hitSlop={10}
              style={{ paddingHorizontal: spacing.sm - 2 }}
              accessibilityLabel={t('activity.openMenu', { defaultValue: 'Open menu' })}
            >
              <MoreHorizontal size={22} color={colors.textPrimary} strokeWidth={2.2} />
            </Pressable>
          )}
        </View>
      ),
    });
  }, [navigation, isCreator, canShare, isPrivateLink, timeStatus, statusColor, activity.visibility, t, handleShare, colors, styles]);

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
  // Server-aligned windows (migration 00292, unchanged by 00306):
  //   geo: anchor must be in T-15min → T+15min
  //   QR:  T-15min → T+duration+3h (token creation and scan share the gate)
  const isInGeoWindow = requiresPresence && nowMs >= startsAtMs - 15 * 60 * 1000 && nowMs <= startsAtMs + 15 * 60 * 1000;
  const isInQrWindow = requiresPresence && nowMs >= startsAtMs - 15 * 60 * 1000 && nowMs <= startsAtMs + durationMs + 3 * 60 * 60 * 1000;
  const isQrAvailable = isInQrWindow; // creator's QR generation uses the same gate

  const remaining = getRemainingPlaces(activity.max_participants, activity.participant_count);

  const alreadyConfirmed = !!participation?.confirmed_present;
  // Creator can always geo-self-validate; the server records it but
  // recalculate_reliability_score ignores the row until another accepted
  // participant exists (see migration 00128).
  // The creator never self-confirms — their presence comes from others (the
  // auto-flip when a participant confirms) or peer testimony at 3+. Matches the
  // server guard in confirm_presence_via_geo.
  const canConfirmGeo = !isCreator && participation?.status === 'accepted' && !alreadyConfirmed && isInGeoWindow;
  const canScanQr = !isCreator && participation?.status === 'accepted' && !alreadyConfirmed && isInQrWindow;
  const canCheckIn = canConfirmGeo || canScanQr;

  // Presence fallback visibility (prod audit 2026-06-11). Two silent
  // gaps the audit found: (1) once the geo/QR windows close, an
  // unvalidated attendee gets no UI and never learns peer review can
  // still save them — so they may eat an unfair no-show penalty unaware
  // the backstop exists; (2) if background location is denied,
  // auto-validation silently never runs with no explanation.
  const endMs = startsAtMs + durationMs;
  const inPeerReviewWindow = nowMs >= endMs + 15 * 60 * 1000 && nowMs <= endMs + 24 * 60 * 60 * 1000;
  const hasPeers = (activity.participant_count ?? 0) >= 2; // solo activities can't be peer-validated (mig 00229) — no banner
  const notValidated = participation?.status === 'accepted' && participation?.confirmed_present == null;
  const showPeerBackstop = requiresPresence && notValidated && hasPeers && !canCheckIn && inPeerReviewWindow;

  const [bgLocationDenied, setBgLocationDenied] = useState(false);
  useEffect(() => {
    if (!requiresPresence || !isAccepted || alreadyConfirmed || !isInQrWindow) return;
    let cancelled = false;
    Location.getBackgroundPermissionsAsync()
      .then((p) => { if (!cancelled) setBgLocationDenied(p.status !== 'granted'); })
      .catch(() => {});
    return () => { cancelled = true; };
  }, [requiresPresence, isAccepted, alreadyConfirmed, isInQrWindow]);
  const showBgLocationHint = canScanQr && bgLocationDenied;

  // Passive geo detection: periodically check if the user is at the activity location.
  // Fires a local notification + haptic on the transition from "not at" to "at" so the
  // user doesn't have to remember to open the app and validate.
  useEffect(() => {
    if (!canCheckIn) return;
    let cancelled = false;
    let alertedAt = false;

    const checkPosition = async () => {
      try {
        const { status } = await Location.getForegroundPermissionsAsync();
        if (status !== 'granted') {
          const req = await Location.requestForegroundPermissionsAsync();
          if (req.status !== 'granted') return;
        }
        const pos = await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.Balanced });
        if (cancelled) return;
        // Mirror the server's LEAST(meeting, end, trace) exactly — checking
        // a point the server ignores (the objective) shows "in the zone"
        // for a check-in that would be rejected; skipping one it accepts
        // (the trace) blocks valid mid-route check-ins.
        const candidates: number[] = [];
        if (activity.meeting_lat != null && activity.meeting_lng != null) {
          candidates.push(distanceMeters(pos.coords.latitude, pos.coords.longitude, activity.meeting_lat, activity.meeting_lng));
        }
        if (activity.end_lat != null && activity.end_lng != null) {
          candidates.push(distanceMeters(pos.coords.latitude, pos.coords.longitude, activity.end_lat, activity.end_lng));
        }
        if (activity.trace_geojson) {
          candidates.push(distanceToPolylineMeters(pos.coords.latitude, pos.coords.longitude, activity.trace_geojson.coordinates));
        }
        if (candidates.length === 0) return;
        const minDist = Math.min(...candidates);
        const nowAt = minDist <= 150;
        if (cancelled) return;
        setIsAtActivity(nowAt);
        setDistanceToActivityM(Math.round(minDist));

        // Fire once when the user enters the zone (transition false → true)
        if (nowAt && !alertedAt) {
          alertedAt = true;
          // No local OS notif here — user is foreground on this very page,
          // the in-app toast + state change already signal the confirmation.
          // The two visible OS notifs ("détectée" → "confirmée") are owned
          // by the background geofence task only.

          // Auto-confirm: app open + within 150m + inside geo window already
          // proves enough. Saves the user a tap. The manual button stays as
          // a fallback if this call fails (network, etc.). The success
          // haptic only fires once the server has actually confirmed —
          // celebrating on zone entry reads as "validated" when it isn't.
          if (canConfirmGeo) {
            try {
              await reliabilityService.confirmPresenceViaGeo(activity.id, pos.coords.longitude, pos.coords.latitude);
              if (cancelled) return;
              haptic.success();
              await queryClient.invalidateQueries({ queryKey: ['participation', activity.id] });
              await queryClient.invalidateQueries({ queryKey: ['user-public-stats'] });
              await queryClient.invalidateQueries({ queryKey: ['user-stats'] });
              await queryClient.invalidateQueries({ queryKey: ['public-profile'] });
              await queryClient.invalidateQueries({ queryKey: ['currentUser'] });
              await queryClient.invalidateQueries({ queryKey: ['participants', activity.id] });
              Burnt.toast({ title: t('presence.confirmed'), preset: 'done' });
            } catch {
              // Silent: the manual button still works as a fallback.
            }
          } else {
            // QR-only path: no RPC to wait on — the haptic is just the
            // "you're at the spot" cue prompting the scan.
            haptic.success();
          }
        }
      } catch {
        // ignore
      }
    };

    checkPosition();
    const interval = setInterval(checkPosition, 30000);

    return () => {
      cancelled = true;
      clearInterval(interval);
    };
  }, [canCheckIn, canConfirmGeo, activity.id, activity.meeting_lat, activity.meeting_lng, activity.end_lat, activity.end_lng, activity.trace_geojson, queryClient, t]);

  // Auto-show the creator's QR modal once the QR window opens
  // (T-15min). Reduces dependency on the reminder push + the manual
  // "Show QR" tap — if the creator is on the screen when T-15min
  // arrives, the modal opens itself. autoShownQrFor scopes the
  // "shown" memory to the session, so the modal doesn't reopen after
  // the creator closes it and navigates away + back.
  useEffect(() => {
    if (!isCreator || !requiresPresence) return;
    if (autoShownQrFor.has(activity.id)) return;

    const openAtMs = startsAtMs - 15 * 60 * 1000;
    const closeAtMs = startsAtMs + durationMs + 3 * 60 * 60 * 1000;
    const now = Date.now();

    if (now >= closeAtMs) return; // window already past

    if (now >= openAtMs) {
      autoShownQrFor.add(activity.id);
      setShowQrModal(true);
      return;
    }

    // Window opens in the future — schedule the auto-show.
    const timer = setTimeout(() => {
      if (autoShownQrFor.has(activity.id)) return;
      autoShownQrFor.add(activity.id);
      setShowQrModal(true);
    }, openAtMs - now);

    return () => clearTimeout(timer);
  }, [isCreator, requiresPresence, activity.id, startsAtMs, durationMs]);

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
      // Quick client-side guard: if our last-known distance says we're outside
      // the 150m zone, don't even hit the server. Saves a generic-error round-trip.
      if (!isAtActivity) {
        Alert.alert(t('auth.error'), t('errors.confirmPresence'));
        return;
      }
      await reliabilityService.confirmPresenceViaGeo(activity.id, pos.coords.longitude, pos.coords.latitude);
      await queryClient.invalidateQueries({ queryKey: ['participation', activity.id] });
      await queryClient.invalidateQueries({ queryKey: ['user-public-stats'] });
      await queryClient.invalidateQueries({ queryKey: ['user-stats'] });
      await queryClient.invalidateQueries({ queryKey: ['public-profile'] });
      await queryClient.invalidateQueries({ queryKey: ['currentUser'] });
      await queryClient.invalidateQueries({ queryKey: ['participants', activity.id] });
      Burnt.toast({ title: t('presence.confirmed'), preset: 'done' });
    } catch (err) {
      Alert.alert(t('auth.error'), getFriendlyError(err, 'confirmPresence'));
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
      // Self-heal the shared participant/transport caches in case the
      // realtime broadcast is delayed or dropped.
      await queryClient.invalidateQueries({ queryKey: ['participants', activity.id] });
      await queryClient.invalidateQueries({ queryKey: ['transport', activity.id] });
      await queryClient.invalidateQueries({ queryKey: ['transport-summary', activity.id] });
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
      await queryClient.invalidateQueries({ queryKey: ['participants', activity.id] });
      await queryClient.invalidateQueries({ queryKey: ['transport', activity.id] });
      await queryClient.invalidateQueries({ queryKey: ['transport-summary', activity.id] });
      await queryClient.invalidateQueries({ queryKey: ['user-public-stats'] });
      await queryClient.invalidateQueries({ queryKey: ['user-stats'] });
      await queryClient.invalidateQueries({ queryKey: ['public-profile'] });
      await queryClient.invalidateQueries({ queryKey: ['currentUser'] });
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
      // Refresh THIS activity too, else the creator keeps seeing the cancelled
      // outing rendered as live (join/share/QR) until a manual refresh.
      await queryClient.invalidateQueries({ queryKey: ['activity', activity.id] });
      Burnt.toast({ title: t('toast.activityCancelled') });
      setShowCancelModal(false);
    } catch (err) {
      Alert.alert(t('auth.error'), getFriendlyError(err, 'cancelActivity'));
    } finally {
      setIsLoading(false);
    }
  };

  const handlePickTrace = async () => {
    try {
      const result = await DocumentPicker.getDocumentAsync({ type: '*/*', copyToCacheDirectory: true });
      if (result.canceled) return;
      const file = result.assets[0];
      if (!file) return;
      if (file.size != null && file.size > 5 * 1024 * 1024) {
        Alert.alert(t('create.traceTooLarge'));
        return;
      }
      const xml = await new File(file.uri).text();
      const geojson = parseGpxToGeoJson(xml);
      await activityService.updateTrace(activity.id, geojson);
      await queryClient.invalidateQueries({ queryKey: ['activity', activity.id] });
      Burnt.toast({ title: t('activity.traceImported'), preset: 'done' });
    } catch (err) {
      if (err instanceof GpxParseError) {
        // GpxParseError carries diagnostic text from our own parser
        // ("No track points found", "Too many points") — helps the
        // user fix the file. Safe to surface as-is.
        Alert.alert(t('create.traceParseError'), err.message);
      } else {
        Alert.alert(t('auth.error'), getFriendlyError(err, 'generic'));
      }
    }
  };

  const handleClearTrace = () => {
    Alert.alert(t('activity.traceClearTitle'), t('activity.traceClearMessage'), [
      { text: t('activity.no'), style: 'cancel' },
      {
        text: t('activity.traceClearConfirm'),
        style: 'destructive',
        onPress: async () => {
          try {
            await activityService.updateTrace(activity.id, null);
            await queryClient.invalidateQueries({ queryKey: ['activity', activity.id] });
            Burnt.toast({ title: t('activity.traceCleared'), preset: 'done' });
          } catch (err) {
            Alert.alert(t('auth.error'), getFriendlyError(err, 'generic'));
          }
        },
      },
    ]);
  };

  const handleDrawTraceSave = async (geojson: import('@/services/activity-service').GeoJsonLineString) => {
    // Close only on success — if updateTrace fails (offline), keep the draw
    // modal open so the just-drawn trace isn't lost (audit 2026-07-13).
    try {
      await activityService.updateTrace(activity.id, geojson);
      await queryClient.invalidateQueries({ queryKey: ['activity', activity.id] });
      setDrawTraceOpen(false);
      Burnt.toast({ title: t('activity.traceImported'), preset: 'done' });
    } catch (err) {
      Alert.alert(t('auth.error'), getFriendlyError(err, 'generic'));
    }
  };

  const [activeTab, setActiveTab] = useState<'info' | 'transport' | 'gear' | 'chat'>('info');
  const [showMapMenu, setShowMapMenu] = useState(false);
  const transportSectionRef = useRef<TransportSectionHandle>(null);
  const gearSectionRef = useRef<GearSectionHandle>(null);
  const myOutingCardRef = useRef<MyOutingCardHandle>(null);
  const [showParticipantsModal, setShowParticipantsModal] = useState(false);
  const canRejoin = participation && ['withdrawn', 'refused'].includes(participation.status);
  const isActive = ['published', 'in_progress'].includes(activity.status);
  const sportAccent = sportCategoryColor(activity.sport_category, colors.cta);
  // Drawer-chip tint (accent ~10% over white) as a SOLID color so it stays
  // legible over the map while looking identical to the UA drawer chip.
  const sportChipBg = (() => {
    const h = sportAccent.replace('#', '');
    const mix = (c: number) => Math.round(c * 0.1 + 255 * 0.9).toString(16).padStart(2, '0');
    return `#${mix(parseInt(h.slice(0, 2), 16))}${mix(parseInt(h.slice(2, 4), 16))}${mix(parseInt(h.slice(4, 6), 16))}`;
  })();
  // Logistics (transport / gear / seat requests) are sealed once the
  // activity starts — DB-side too, via 00233's `starts_at > NOW()` gate.
  // Hide the corresponding edit affordances so users don't tap into a
  // generic "Operation not permitted".
  const canEditLogistics = isActive && new Date(activity.starts_at).getTime() > Date.now();
  const isFull = remaining <= 0;
  const showJoinButton = !isCreator && (!participation || canRejoin) && remaining > 0 && activity.status === 'published';
  const showFullButton = !isCreator && (!participation || canRejoin) && isFull && activity.status === 'published';
  const showLeaveButton = !isCreator && participation && ['accepted', 'pending'].includes(participation.status) && isActive;
  const showCancelButton = isCreator && isActive;
  const isPending = participation?.status === 'pending';

  const joinLabel = activity.visibility === 'approval' || activity.visibility === 'private_link_approval'
    ? t('activity.requestJoin')
    : t('activity.join');

  const showTabs = isCreator || isAccepted;

  const mapPins: MapPin[] = [
    ...(activity.meeting_lng != null && activity.meeting_lat != null
      ? [{ id: 'meeting', coordinate: [activity.meeting_lng, activity.meeting_lat] as [number, number], color: colors.pinMeeting, label: t('activity.pinRdv') }]
      : []),
    ...(activity.end_lng != null && activity.end_lat != null
      ? [{ id: 'end', coordinate: [activity.end_lng, activity.end_lat] as [number, number], color: colors.pinEnd, label: t('activity.pinArrivee') }]
      : []),
    ...(activity.objective_lng != null && activity.objective_lat != null
      ? [{ id: 'objective', coordinate: [activity.objective_lng, activity.objective_lat] as [number, number], color: colors.pinObjective, label: t('activity.pinObjectif') }]
      : []),
  ];
  const allLngs = mapPins.map((p) => p.coordinate[0]);
  const allLats = mapPins.map((p) => p.coordinate[1]);
  // mapPins CAN be empty: an invite-token preview carries no meeting/end/
  // objective projections, and the instant the viewer joins, showTabs flips
  // while the activity object is still that thin shape — Math.min() of an
  // empty array is Infinity and Mapbox chokes on [Infinity, Infinity]
  // (Scott's join-then-error-retry bug, 2026-07-10). Fall back to the
  // always-present approximate point until the full row refetches.
  const hasPins = mapPins.length > 0;
  const mapCenter: [number, number] = hasPins
    ? [(Math.min(...allLngs) + Math.max(...allLngs)) / 2, (Math.min(...allLats) + Math.max(...allLats)) / 2]
    : [activity.lng, activity.lat];
  const mapSpread = hasPins
    ? Math.max(Math.max(...allLngs) - Math.min(...allLngs), Math.max(...allLats) - Math.min(...allLats))
    : 0;
  const mapZoom = mapSpread > 0.1 ? 10 : mapSpread > 0.01 ? 12 : 14;
  // The mini-preview centres on the objective (where you're headed); the
  // fullscreen map keeps the fit-all centroid so the whole route shows.
  const miniMapCenter: [number, number] =
    activity.objective_lng != null && activity.objective_lat != null
      ? [activity.objective_lng, activity.objective_lat]
      : mapCenter;
  const mapRouteLine: [number, number][] | undefined = activity.trace_geojson
    ? activity.trace_geojson.coordinates.map((c) => [c[0]!, c[1]!] as [number, number])
    : activity.end_lng != null && activity.end_lat != null && activity.meeting_lng != null && activity.meeting_lat != null
      ? [[activity.meeting_lng, activity.meeting_lat], [activity.end_lng, activity.end_lat]]
      : undefined;

  // Hero map: everyone sees the (already-public) approximate area; only members
  // get the precise pins, route and fullscreen — the exact rendez-vous/objective
  // stays members-only. A gate-crasher just won't be accepted, so it's fine.
  const heroPins: MapPin[] = showTabs
    ? mapPins
    : [{ id: 'approx', coordinate: [activity.lng, activity.lat] as [number, number], color: sportAccent, label: '' }];
  const heroCenter: [number, number] = showTabs ? miniMapCenter : [activity.lng, activity.lat];
  const heroZoom = showTabs ? mapZoom : 12;
  const heroRoute = showTabs ? mapRouteLine : undefined;

  return (
    <View style={styles.container}>
      {/* Tab bar — only for participants/creator. Four tabs since we
          split Organisation into Transport + Matériel; presence/QR dot
          moves to Info where the widget now lives. Text-only — icons
          were tried and removed (felt visually noisy at this scale). */}
      {showTabs && (
        <View style={styles.tabBar}>
          {(['info', 'transport', 'gear', 'chat'] as const).map((tab) => {
            const isActiveTab = activeTab === tab;
            return (
              <Pressable
                key={tab}
                style={styles.tab}
                onPress={() => setActiveTab(tab)}
                accessibilityRole="tab"
                accessibilityState={{ selected: isActiveTab }}
                accessibilityLabel={t(`activity.tab.${tab}`)}
              >
                <View style={styles.tabInner}>
                  <Text style={[styles.tabText, isActiveTab && styles.tabTextActive]}>
                    {t(`activity.tab.${tab}`)}
                  </Text>
                  {tab === 'info' && (canCheckIn || (isCreator && isQrAvailable)) && (
                    <View style={styles.tabDot} />
                  )}
                  {tab === 'chat' && wallUnreadCount > 0 && !isActiveTab && (
                    <View style={styles.tabBadge}>
                      <Text style={styles.tabBadgeText}>{wallUnreadCount > 99 ? '99+' : wallUnreadCount}</Text>
                    </View>
                  )}
                </View>
                <View style={[styles.tabIndicator, isActiveTab && styles.tabIndicatorActive]} />
              </Pressable>
            );
          })}
        </View>
      )}

      {/* ===== INFO TAB ===== */}
      {(!showTabs || activeTab === 'info') && (
        <View style={{ flex: 1 }}>
          <ScrollView style={{ flex: 1 }} contentContainerStyle={styles.content}>
            {/* === MAP HERO === everyone sees the (already-public) approximate
                area; members get precise pins + fullscreen. Floating info pills
                carry sport / date / places. */}
            <View style={styles.mapHero}>
              {showTabs ? (
                <Pressable style={StyleSheet.absoluteFill} onPress={() => setShowFullMap(true)}>
                  <JuntoMapView center={heroCenter} zoom={heroZoom} pins={heroPins} routeLine={heroRoute} compassEnabled={false} />
                </Pressable>
              ) : (
                <View style={StyleSheet.absoluteFill} pointerEvents="none">
                  <JuntoMapView center={heroCenter} zoom={heroZoom} pins={heroPins} routeLine={heroRoute} compassEnabled={false} />
                </View>
              )}
              {/* Poster grammar: sport flag alone top-left; scrim + meta line +
                  title anchored at the bottom. */}
              <View style={styles.heroPillCluster} pointerEvents="none">
                {/* Same sport-chip grammar as the UA drawer (outline + tint +
                    sport glyph), on a solid base for map legibility. */}
                <View style={[styles.heroSportChip, { borderColor: sportAccent, backgroundColor: sportChipBg }]}>
                  <Text style={styles.heroSportEmoji}>{getSportIcon(activity.sport_key)}</Text>
                  <Text style={[styles.heroSportChipText, { color: sportAccent }]} numberOfLines={1}>
                    {t(`sports.${activity.sport_key}`, activity.sport_key)}
                  </Text>
                </View>
              </View>
              <Svg style={styles.heroScrim} pointerEvents="none" width="100%" height="130">
                <Defs>
                  <SvgLinearGradient id="heroScrim" x1="0" y1="0" x2="0" y2="1">
                    <Stop offset="0" stopColor="#000000" stopOpacity="0" />
                    <Stop offset="1" stopColor="#000000" stopOpacity="0.55" />
                  </SvgLinearGradient>
                </Defs>
                <Rect x="0" y="0" width="100%" height="130" fill="url(#heroScrim)" />
              </Svg>
              <View style={styles.heroTitleWrap} pointerEvents="none">
                {/* Bare meta line — vert vif icons carry the distinction (no
                    pill chrome eating the map), shadowed white text. */}
                <View style={styles.heroMetaLine}>
                  {/* Ghost pills, settled: dark translucent, all-white content —
                      no extra hues on the map. */}
                  <View style={styles.heroMetaPill}>
                    <Calendar size={12} color="#FFFFFF" strokeWidth={2.6} />
                    <Text style={styles.heroMetaText} numberOfLines={1}>
                      {dayjs(activity.starts_at).locale(i18n.language).format('ddd D MMM [à] H[h]mm')}
                    </Text>
                  </View>
                  <View style={styles.heroMetaPill}>
                    <Users size={12} color="#FFFFFF" strokeWidth={2.6} />
                    <Text style={styles.heroMetaText} numberOfLines={1}>
                      {activity.max_participants === null
                        ? `${activity.participant_count}`
                        : t('activity.placesShort', { defaultValue: '{{n}} places', n: `${remaining}/${activity.max_participants}` })}
                    </Text>
                  </View>
                </View>
                <Text style={styles.heroTitleOnMap} numberOfLines={3}>{activity.title}</Text>
              </View>
              {/* Single ⋯ button — the secondary map actions live in a small
                  anchored menu. Tapping the map itself is the fullscreen
                  shortcut, so nothing frequent is buried. */}
              {showTabs && (
                <View style={styles.mapMenuWrap} pointerEvents="box-none">
                  <Pressable
                    style={styles.mapMenuBtn}
                    onPress={() => setShowMapMenu((v) => !v)}
                    accessibilityLabel={t('activity.mapMenu', { defaultValue: 'Options de la carte' })}
                    hitSlop={6}
                  >
                    <MoreHorizontal size={18} color={colors.textPrimary} strokeWidth={2.4} />
                  </Pressable>
                  {showMapMenu && (
                    <View style={styles.mapMenu}>
                      <Pressable
                        style={styles.mapMenuItem}
                        onPress={() => {
                          setShowMapMenu(false);
                          const navLat = activity.meeting_lat ?? activity.lat;
                          const navLng = activity.meeting_lng ?? activity.lng;
                          Linking.openURL(`https://www.google.com/maps/dir/?api=1&destination=${navLat},${navLng}`);
                        }}
                      >
                        <Navigation size={15} color={colors.textPrimary} strokeWidth={2.2} />
                        <Text style={styles.mapMenuItemText}>{t('activity.navigate')}</Text>
                      </Pressable>
                      <Pressable style={styles.mapMenuItem} onPress={() => { setShowMapMenu(false); setShowFullMap(true); }}>
                        <Maximize2 size={15} color={colors.textPrimary} strokeWidth={2.2} />
                        <Text style={styles.mapMenuItemText}>{t('activity.fullscreen', { defaultValue: 'Plein écran' })}</Text>
                      </Pressable>
                      {isCreator && (
                        <Pressable style={styles.mapMenuItem} onPress={() => { setShowMapMenu(false); handlePickTrace(); }}>
                          <Route size={15} color={colors.cta} strokeWidth={2.2} />
                          <Text style={styles.mapMenuItemText}>{activity.trace_geojson ? t('activity.traceReplace') : t('activity.traceImport')}</Text>
                        </Pressable>
                      )}
                      {isCreator && (
                        <Pressable style={styles.mapMenuItem} onPress={() => { setShowMapMenu(false); setDrawTraceOpen(true); }}>
                          <Pencil size={15} color={colors.cta} strokeWidth={2.2} />
                          <Text style={styles.mapMenuItemText}>{t('activity.traceDraw', { defaultValue: 'Dessiner une trace' })}</Text>
                        </Pressable>
                      )}
                      {isCreator && activity.trace_geojson && (
                        <Pressable style={styles.mapMenuItem} onPress={() => { setShowMapMenu(false); handleClearTrace(); }}>
                          <Trash2 size={15} color={colors.error} strokeWidth={2.2} />
                          <Text style={[styles.mapMenuItemText, { color: colors.error }]}>{t('activity.traceRemove')}</Text>
                        </Pressable>
                      )}
                    </View>
                  )}
                </View>
              )}
            </View>

            {/* === FACTS === restrained grid, monochrome icons, short atomic
                values only. Long text (locations) lives in "Le parcours". */}
            {/* Contextual banners — BELOW the hero so the flush-top map
                never overlaps them. Only render when there's a state. */}
            {!isActive && (
              <View style={styles.statusBannerTop}>
                <Text style={styles.statusBannerText}>{t(`activity.statusBanner.${activity.status}`)}</Text>
              </View>
            )}
            {isPending && isActive && (
              <View style={[styles.statusBannerTop, styles.statusBannerPending]}>
                <Text style={styles.statusBannerText}>{t('activity.pendingRequest')}</Text>
              </View>
            )}
            {isAccepted && !isCreator && isActive && (
              <View style={[styles.statusBannerTop, styles.statusBannerAccepted]}>
                <Text style={styles.statusBannerText}>{t('activity.youAreIn')}</Text>
              </View>
            )}
            {alreadyConfirmed && (
              <View style={[styles.statusBannerTop, styles.statusBannerConfirmed]}>
                <MapPinCheck size={14} color={colors.success} strokeWidth={2.4} />
                <Text style={[styles.statusBannerText, { color: colors.success }]}>{t('presence.alreadyConfirmed')}</Text>
              </View>
            )}
            {/* Peer-review backstop — surfaced when the auto/QR windows
                have closed but an unvalidated attendee (with peers) can
                still be saved by peer testimony. Prod audit 2026-06-11:
                without this the backstop is invisible at the moment of
                need. */}
            {showPeerBackstop && (
              <View style={[styles.statusBannerTop, { flexDirection: 'column', alignItems: 'flex-start', gap: spacing.sm, backgroundColor: colors.surface }]}>
                <Text style={[styles.statusBannerText, { textAlign: 'left' }]}>
                  {t('presence.backstopHint')}
                </Text>
                <Pressable
                  style={{ backgroundColor: colors.cta, paddingVertical: spacing.xs + 2, paddingHorizontal: spacing.md, borderRadius: radius.md }}
                  onPress={() => router.push(`/(auth)/peer-review/${activity.id}`)}
                >
                  <Text style={{ color: colors.background, fontWeight: '700', fontSize: fontSizes.sm }}>
                    {t('presence.openPeerReview')}
                  </Text>
                </Pressable>
              </View>
            )}
            {/* Presence widget — moved back to the Info tab so the
                "where do I stand on this outing" answer is co-located
                with the activity context. Replaces the old check-in
                banner that linked to Organization. */}
            {showBgLocationHint && (
              <View style={[styles.statusBannerTop, { backgroundColor: colors.surface }]}>
                <Text style={[styles.statusBannerText, { textAlign: 'left', color: colors.textSecondary }]}>
                  {t('presence.bgLocationHint')}
                </Text>
              </View>
            )}
            {canCheckIn && (
              <View style={[styles.presenceBlock, isAtActivity && styles.presenceBlockActive]}>
                <View style={styles.presenceHeader}>
                  <MapPinCheck size={18} color={isAtActivity ? colors.success : colors.textPrimary} strokeWidth={2.4} />
                  <Text style={styles.presenceTitle}>
                    {isAtActivity ? t('presence.atActivity') : t('presence.confirmMyPresence')}
                  </Text>
                </View>
                <Text style={styles.presenceSubtitle}>
                  {isAtActivity
                    ? t('presence.atActivitySubtitle')
                    : distanceToActivityM != null
                      ? t('presence.distanceAway', {
                          distance: distanceToActivityM < 1000
                            ? `${distanceToActivityM} m`
                            : `${(distanceToActivityM / 1000).toFixed(1)} km`,
                          defaultValue: `À ${distanceToActivityM < 1000 ? `${distanceToActivityM} m` : `${(distanceToActivityM / 1000).toFixed(1)} km`} du point de rendez-vous`,
                        })
                      : t('presence.mustBeAtLocation')}
                </Text>
                <View style={styles.presenceActions}>
                  {canConfirmGeo && (
                    <Pressable
                      style={[styles.presenceButton, isConfirming && styles.buttonDisabled]}
                      onPress={handleCheckIn}
                      disabled={isConfirming}
                    >
                      <Text style={styles.presenceButtonText} numberOfLines={1}>
                        {isConfirming ? '...' : t('presence.confirm')}
                      </Text>
                    </Pressable>
                  )}
                  {canScanQr && (
                    <Pressable style={styles.presenceSecondaryButton} onPress={() => setShowScanner(true)}>
                      <Text style={styles.presenceSecondaryText}>{t('presence.scanQr')}</Text>
                    </Pressable>
                  )}
                </View>
              </View>
            )}
            {isCreator && isQrAvailable && (
              <Pressable style={styles.presenceCreatorButton} onPress={() => setShowQrModal(true)}>
                <Text style={styles.presenceCreatorText}>{t('presence.showQr')}</Text>
              </Pressable>
            )}

            <Text style={styles.secTitle}>{t('activity.factsSection', { defaultValue: 'En bref' })}</Text>
            <View style={styles.factsGrid}>
              <View style={styles.factCell}>
                <BarChart3 size={15} color={colors.cta} strokeWidth={2.4} />
                <Text style={styles.factLabel}>{t('meta.level')} :</Text>
                <Text style={styles.factValue} numberOfLines={1}>{formatLevelRange(activity.level, activity.level_max)}</Text>
              </View>
              <View style={styles.factCell}>
                <Clock size={15} color={colors.cta} strokeWidth={2.4} />
                <Text style={styles.factLabel}>{t('meta.duration')} :</Text>
                <Text style={styles.factValue} numberOfLines={1}>{formatDuration(activity.duration)}</Text>
              </View>
              {activity.distance_km != null && activity.distance_km > 0 && (
                <View style={styles.factCell}>
                  <Route size={15} color={colors.cta} strokeWidth={2.4} />
                  <Text style={styles.factLabel}>{t('meta.distance')} :</Text>
                  <Text style={styles.factValue} numberOfLines={1}>{`${Number(activity.distance_km).toLocaleString(i18n.language === 'fr' ? 'fr-FR' : 'en-US')} km`}</Text>
                </View>
              )}
              {activity.elevation_gain_m != null && activity.elevation_gain_m > 0 && (
                <View style={styles.factCell}>
                  <Mountain size={15} color={colors.cta} strokeWidth={2.4} />
                  <Text style={styles.factLabel}>{t('meta.elevation')} :</Text>
                  <Text style={styles.factValue} numberOfLines={1}>{`${activity.elevation_gain_m.toLocaleString(i18n.language === 'fr' ? 'fr-FR' : 'en-US')} m`}</Text>
                </View>
              )}
              {/* Carpool teaser — a decision fact ("can I get a ride?"), so it
                  lives with the facts (Scott 2026-07-09). Tapping jumps to
                  the Transport tab (Scott 2026-07-10). */}
              {(() => {
                const carSummary = (transportSummary ?? []).filter((s) => s.transport_type === 'car');
                if (carSummary.length === 0) return null;
                const totalSeats = carSummary.reduce((sum, s) => sum + s.total_seats, 0);
                const allCities = [...new Set(carSummary.flatMap((s) => s.cities ?? []).filter(Boolean))];
                const value = [
                  totalSeats > 0 ? `${totalSeats} ${t('transport.seats')}` : t('transport.type.car').toLowerCase(),
                  allCities.length > 0 ? allCities.join(', ') : null,
                ].filter(Boolean).join(' · ');
                // Non-members have no tabs to jump to — plain fact.
                return (
                  <Pressable
                    style={styles.factCell}
                    onPress={showTabs ? () => setActiveTab('transport') : undefined}
                    disabled={!showTabs}
                    hitSlop={6}
                  >
                    <Car size={15} color={colors.cta} strokeWidth={2.4} />
                    <Text style={styles.factLabel}>{t('meta.carpool', { defaultValue: 'Covoit' })} :</Text>
                    <Text style={styles.factValue} numberOfLines={1}>{value}</Text>
                  </Pressable>
                );
              })()}
            </View>

            {/* === LE PARCOURS === precise rendez-vous / objective are
                members-only; the description is visible to everyone. The map
                is now the hero, so no second map here. */}
            {showTabs && (activity.meeting_name || activity.objective_name) && (
              <View style={styles.parcoursSection}>
                <View style={styles.secDivider} />
                <Text style={styles.secTitle}>{t('activity.routeSection', { defaultValue: 'Le parcours' })}</Text>
                {showTabs && activity.meeting_name && (
                  <View style={styles.locRow}>
                    <MapPinIcon size={16} color={colors.textSecondary} strokeWidth={2.2} />
                    <Text style={styles.locLabelInline}>{t('meta.meetingPoint')} :</Text>
                    <Text style={styles.locValue}>{activity.meeting_name}</Text>
                  </View>
                )}
                {showTabs && activity.objective_name && (
                  <View style={styles.locRow}>
                    <Flag size={16} color={colors.textSecondary} strokeWidth={2.2} />
                    <Text style={styles.locLabelInline}>{t('meta.objective')} :</Text>
                    <Text style={styles.locValue}>{activity.objective_name}</Text>
                  </View>
                )}
              </View>
            )}

            {activity.description != null && activity.description !== '' && (
              <View style={styles.parcoursSection}>
                <View style={styles.secDivider} />
                <Text style={styles.secTitle}>{t('activity.description')}</Text>
                <ActivityDescription description={activity.description} />
              </View>
            )}

            {/* === PEOPLE === titled open section like the rest of the page
                (last on purpose: the social-proof recall right above the CTA). */}
            <View style={styles.parcoursSection}>
              <View style={styles.secDivider} />
              <Text style={styles.secTitle}>{t('activity.participantsSection', { defaultValue: 'Participants' })}</Text>
              <OrganizerCard
                activityId={activity.id}
                creatorId={activity.creator_id}
                creatorName={activity.creator_name}
                creatorAvatar={activity.creator_avatar}
                maxParticipants={activity.max_participants}
                onOpenAll={() => setShowParticipantsModal(true)}
              />
            </View>

            {!isCreator && isAuthenticated && (
              <Pressable style={styles.reportLink} onPress={() => setShowReport(true)}>
                <Text style={styles.reportLinkText}>{t('report.reportActivity')}</Text>
              </Pressable>
            )}
          </ScrollView>

          {/* === STICKY FOOTER === The action — never inline, never scrolls
              out of reach. Only renders when there's a CTA to show. */}
          {(showJoinButton || showFullButton || showLeaveButton) && (
            <View style={[styles.stickyFooter, { paddingBottom: Math.max(spacing.md, insets.bottom + spacing.xs) }]}>
              {showJoinButton && (
                <Pressable
                  style={[styles.joinButton, isLoading && styles.buttonDisabled]}
                  onPress={handleJoin}
                  disabled={isLoading}
                >
                  <Text style={styles.joinButtonText}>{isLoading ? '...' : joinLabel}</Text>
                </Pressable>
              )}
              {showFullButton && (
                <View style={styles.fullButton}>
                  <Lock size={16} color={colors.error} strokeWidth={2.5} />
                  <Text style={styles.fullButtonText}>{t('activity.activityFull')}</Text>
                </View>
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
            </View>
          )}
        </View>
      )}

      {/* ===== TRANSPORT TAB ===== Mine + Group showing only the
          transport half. Sub-tab bar inside GroupCard is hidden since
          the top-level tabs already do that job. */}
      {showTabs && activeTab === 'transport' && (
        <ScrollView style={{ flex: 1 }} contentContainerStyle={styles.content}>
          <MyOutingCard
            ref={myOutingCardRef}
            activityId={activity.id}
            startsAt={activity.starts_at}
            status={activity.status}
            currentUserId={currentUserId ?? null}
            isParticipant={isCreator || isAccepted}
            view="transport"
            onEditTransport={() => transportSectionRef.current?.openEditor()}
            onEditGearItem={(name) => gearSectionRef.current?.openItemByName(name)}
            onAddMaterial={() => gearSectionRef.current?.openCustomSheet()}
          />

          <GroupCard
            activityId={activity.id}
            currentUserId={currentUserId ?? null}
            isParticipant={isCreator || isAccepted}
            isActive={canEditLogistics}
            activeSubTab="transport"
            onActiveSubTabChange={() => {/* top-level tabs handle this */}}
            showSubTabBar={false}
            onReserveSeat={(driverId) => {
              if (myOutingCardRef.current?.requestCancelIfNeeded()) return;
              const myFrom = (orgTransportParticipants ?? []).find((p) => p.user_id === currentUserId)?.transport_from_name;
              transportSectionRef.current?.openRequestSheet(driverId, myFrom);
            }}
            onAddGear={() => gearSectionRef.current?.openCustomSheet()}
            onReportMissing={() => gearSectionRef.current?.openMissingSheet()}
            onEditGearItem={(name, isShared) => gearSectionRef.current?.openItemByName(name, isShared)}
          />

          <TransportSection
            ref={transportSectionRef}
            activityId={activity.id}
            currentUserId={currentUserId ?? null}
          />
        </ScrollView>
      )}

      {/* ===== GEAR TAB ===== Mine + Group showing only the gear half. */}
      {showTabs && activeTab === 'gear' && (
        <ScrollView style={{ flex: 1 }} contentContainerStyle={styles.content}>
          <MyOutingCard
            ref={myOutingCardRef}
            activityId={activity.id}
            startsAt={activity.starts_at}
            status={activity.status}
            currentUserId={currentUserId ?? null}
            isParticipant={isCreator || isAccepted}
            view="gear"
            onEditTransport={() => transportSectionRef.current?.openEditor()}
            onEditGearItem={(name) => gearSectionRef.current?.openItemByName(name)}
            onAddMaterial={() => gearSectionRef.current?.openCustomSheet()}
          />

          <GroupCard
            activityId={activity.id}
            currentUserId={currentUserId ?? null}
            isParticipant={isCreator || isAccepted}
            isActive={canEditLogistics}
            activeSubTab="gear"
            onActiveSubTabChange={() => {/* top-level tabs handle this */}}
            showSubTabBar={false}
            onReserveSeat={(driverId) => {
              if (myOutingCardRef.current?.requestCancelIfNeeded()) return;
              const myFrom = (orgTransportParticipants ?? []).find((p) => p.user_id === currentUserId)?.transport_from_name;
              transportSectionRef.current?.openRequestSheet(driverId, myFrom);
            }}
            onAddGear={() => gearSectionRef.current?.openCustomSheet()}
            onReportMissing={() => gearSectionRef.current?.openMissingSheet()}
            onEditGearItem={(name, isShared) => gearSectionRef.current?.openItemByName(name, isShared)}
          />

          <GearSection
            ref={gearSectionRef}
            activityId={activity.id}
            sportKey={activity.sport_key}
            currentUserId={currentUserId ?? null}
            isParticipant={isCreator || isAccepted}
          />
        </ScrollView>
      )}

      {/* ===== CHAT TAB ===== */}
      {showTabs && activeTab === 'chat' && (
        // No KeyboardAvoidingView — the dock's bottom padding animates with
        // the exact IME inset via useKeyboardDockPadding (reanimated).
        <Animated.View
          style={[
            {
              flex: 1,
              paddingHorizontal: spacing.lg,
              paddingTop: spacing.lg,
            },
            chatDockPadding,
          ]}
        >
          <ActivityWall
            activityId={activity.id}
            isActive={['published', 'in_progress'].includes(activity.status)}
            currentUserId={currentUserId ?? null}
          />
        </Animated.View>
      )}

      {/* Modals — shared across all tabs */}
      <TraceDrawModal
        visible={drawTraceOpen}
        askName={false}
        onClose={() => setDrawTraceOpen(false)}
        onSave={(_name, geojson) => handleDrawTraceSave(geojson)}
      />

      <Modal visible={showFullMap} animationType="slide" statusBarTranslucent onRequestClose={() => setShowFullMap(false)}>
        <View style={styles.fullMapContainer}>
          <JuntoMapView
            center={mapCenter}
            zoom={mapZoom}
            pins={mapPins}
            routeLine={mapRouteLine}
            flyTo={fullMapFly}
            onPinPress={(pin) => setFullMapFly({ coordinate: pin.coordinate, key: Date.now(), zoom: 16 })}
          />
          <View style={[styles.fullMapLegendWrapper, { bottom: insets.bottom + 84 }]} pointerEvents="box-none">
            <MapLegend items={mapPins.map((p) => ({ color: p.color, label: p.label ?? '' })).filter((i) => i.label)} />
          </View>
          <Pressable style={[styles.closeMapButton, { top: insets.top + spacing.sm }]} onPress={() => setShowFullMap(false)} hitSlop={8}>
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
        </View>
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
      <ShareActivitySheet
        visible={showShareSheet}
        activityId={activity.id}
        onClose={() => setShowShareSheet(false)}
        onExternalShare={handleShare}
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

      {/* Participants modal (from organizer card tap) */}
      <Modal
        visible={showParticipantsModal}
        animationType="slide"
        transparent
        onRequestClose={() => setShowParticipantsModal(false)}
      >
        <SafeAreaView style={styles.participantsModalRoot}>
          <View style={styles.participantsModalHeader}>
            <Text style={styles.participantsModalTitle}>{t('organizer.modalTitle')}</Text>
            <Pressable onPress={() => setShowParticipantsModal(false)} hitSlop={10}>
              <XIcon size={22} color={colors.textPrimary} strokeWidth={2.2} />
            </Pressable>
          </View>
          <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: spacing.lg }}>
            <ParticipantList
              activityId={activity.id}
              activityTitle={activity.title}
              isCreator={isCreator}
              creatorId={activity.creator_id}
              creatorName={activity.creator_name}
              creatorAvatar={activity.creator_avatar}
              onProfilePress={!isAuthenticated ? () => onJoinRedirect?.() : undefined}
            />
          </ScrollView>
        </SafeAreaView>
      </Modal>
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  content: { padding: spacing.lg, paddingBottom: spacing.xl + 32 },
  // Info-tab v3 (map-hero) — Scott 2026-07-09.
  // Edge-to-edge, taller — breaks out of the content padding to fill the width.
  mapHero: {
    height: 300,
    overflow: 'hidden',
    marginHorizontal: -spacing.lg,
    marginTop: -spacing.lg,
    marginBottom: spacing.md,
    position: 'relative',
    backgroundColor: colors.surface,
    // Soften the seam where the full-bleed map meets the paper below.
    borderBottomLeftRadius: radius.lg,
    borderBottomRightRadius: radius.lg,
  },
  heroScrim: { position: 'absolute', left: 0, right: 0, bottom: 0 },
  heroMetaLine: { flexDirection: 'row', alignItems: 'center', gap: 7, marginBottom: 7, flexWrap: 'wrap' },
  heroMetaPill: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 5,
    backgroundColor: 'rgba(0,0,0,0.38)',
    borderRadius: radius.full,
    paddingHorizontal: 10,
    paddingVertical: 4,
  },
  heroMetaText: { color: '#FFFFFF', fontSize: 12.5, fontWeight: '700' },
  // Pills stacked in a single top-left cluster.
  heroPillCluster: {
    position: 'absolute',
    top: spacing.md,
    left: spacing.md,
    flexDirection: 'column',
    alignItems: 'flex-start',
    gap: 7,
  },
  heroPill: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 5,
    backgroundColor: 'rgba(255,255,255,0.96)',
    borderRadius: 999,
    paddingHorizontal: 11,
    paddingVertical: 5,
    shadowColor: '#000',
    shadowOpacity: 0.18,
    shadowRadius: 6,
    shadowOffset: { width: 0, height: 2 },
    elevation: 3,
  },
  heroPillText: { color: '#1F1A15', fontSize: 12, fontWeight: '700' },
  // UA-drawer sport-chip grammar, solid base for map legibility.
  heroSportChip: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 5,
    backgroundColor: 'rgba(255,255,255,0.96)',
    borderWidth: 1.5,
    borderRadius: radius.full,
    paddingHorizontal: 10,
    paddingVertical: 4,
    shadowColor: '#000',
    shadowOpacity: 0.18,
    shadowRadius: 6,
    shadowOffset: { width: 0, height: 2 },
    elevation: 3,
  },
  heroSportEmoji: { fontSize: 13 },
  heroSportChipText: { fontSize: 11, fontWeight: '800', letterSpacing: 0.6, textTransform: 'uppercase' },
  mapMenuWrap: { position: 'absolute', top: spacing.sm, right: spacing.sm, alignItems: 'flex-end' },
  mapMenuBtn: {
    width: 36,
    height: 36,
    borderRadius: radius.full,
    backgroundColor: colors.background,
    borderWidth: 1,
    borderColor: colors.borderStrong,
    alignItems: 'center',
    justifyContent: 'center',
  },
  mapMenu: {
    marginTop: 6,
    backgroundColor: colors.background,
    borderWidth: 1,
    borderColor: colors.borderStrong,
    borderRadius: radius.md,
    overflow: 'hidden',
    minWidth: 190,
  },
  mapMenuItem: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 9,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm + 2,
  },
  mapMenuItemText: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '600' },
  // Open editorial section — no box; the map is the hero, this is copy.
  parcoursSection: { marginBottom: spacing.md, paddingHorizontal: 2 },
  heroTitleWrap: { position: 'absolute', left: spacing.md, right: spacing.md, bottom: spacing.md },
  heroTitleOnMap: {
    color: '#FFFFFF',
    fontSize: fontSizes.xxl,
    fontFamily: fonts.title,
    letterSpacing: -0.5,
    lineHeight: 30,
    textShadowColor: 'rgba(0,0,0,0.7)',
    textShadowOffset: { width: 0, height: 1 },
    textShadowRadius: 11,
  },
  titleBlock: { marginBottom: spacing.md },
  activityTitle: {
    color: colors.textPrimary,
    fontSize: fontSizes.xxl,
    fontFamily: fonts.title,
    letterSpacing: -0.5,
    lineHeight: 30,
  },
  metaRow: { flexDirection: 'row', alignItems: 'center', gap: 6, marginTop: spacing.sm, flexWrap: 'wrap' },
  metaText: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: '600' },
  // One fact per line — the hero absorbed date/places/sport, so the page
  // can afford the vertical air; icon + value read calmly.
  factsGrid: {
    paddingHorizontal: spacing.xs,
    marginBottom: spacing.md,
  },
  factCell: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 11,
    paddingVertical: spacing.xs + 3,
  },
  factLabel: { color: colors.textMuted, fontSize: fontSizes.sm, fontWeight: '700' },
  factValue: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '700' },
  // Stylised section label — small vert vif bar + spaced small caps.
  // Quietly hierarchical, echoes the site's SectionLabel grammar.
  // Airbnb-style section headers: bold sentence-case titles, soft dividers
  // BETWEEN sections (never glued to the title).
  secTitle: {
    color: colors.textPrimary,
    fontSize: fontSizes.lg,
    fontWeight: '700',
    letterSpacing: -0.3,
    marginBottom: spacing.sm,
  },
  // Option A won the A/B (2026-07-09): soft dividers between sections give
  // the content the structure it needs against the imposing map hero.
  secDivider: { height: 1, backgroundColor: colors.line, marginBottom: spacing.md },
  locRow: { flexDirection: 'row', gap: 8, marginBottom: spacing.sm, alignItems: 'flex-start' },
  locValue: { flex: 1, color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '500', lineHeight: 19, textAlign: 'center' },
  locLabelInline: { color: colors.textMuted, fontSize: fontSizes.sm, fontWeight: '700', lineHeight: 19 },
  tabBar: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: spacing.xs,
    paddingTop: spacing.sm,
    backgroundColor: colors.background,
    borderBottomWidth: 1,
    borderBottomColor: colors.borderMuted,
  },
  // Equal-width tabs; muted inactive labels; rounded indicator pill under
  // the active one (same pill language as the rest of the page).
  tab: { flex: 1, alignItems: 'center' },
  tabInner: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.xs,
    paddingVertical: spacing.sm,
  },
  tabIndicator: { alignSelf: 'stretch', height: 3, borderRadius: 2, marginHorizontal: spacing.md, backgroundColor: 'transparent' },
  tabIndicatorActive: { backgroundColor: colors.cta },
  tabText: { color: colors.textSecondary, fontSize: fontSizes.md, fontWeight: '600' },
  tabTextActive: { color: colors.cta, fontWeight: '800' },
  tabDot: { width: 6, height: 6, borderRadius: radius.xs, backgroundColor: colors.cta },
  tabBadge: {
    backgroundColor: colors.cta, borderRadius: radius.sm,
    minWidth: 16, height: 16, paddingHorizontal: 4,
    alignItems: 'center', justifyContent: 'center',
  },
  tabBadgeText: { color: '#FFFFFF', fontSize: 10, fontWeight: '700' },
  // Unified presence pill — both states (à confirmer / confirmée) share the
  // same shape, slot and spacing on the Info tab so one literally replaces
  // the other when the user confirms.
  presencePill: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    borderRadius: radius.sm,
    padding: spacing.md,
    marginBottom: spacing.md,
  },
  presencePillReminder: { backgroundColor: colors.cta + '15' },
  presencePillConfirmed: { backgroundColor: colors.success + '15' },
  presenceReminderText: { color: colors.cta, fontSize: fontSizes.sm, fontWeight: '600' },
  comingSoon: { color: colors.textSecondary, fontSize: fontSizes.sm, fontStyle: 'italic' },
  transportSummary: {
    flexDirection: 'row', alignItems: 'center', gap: 6,
    paddingTop: spacing.sm,
    marginTop: spacing.sm,
    borderTopWidth: 1,
    borderTopColor: colors.borderMuted,
  },
  transportSummaryText: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '600' },
  transportCities: { color: colors.textSecondary, fontSize: fontSizes.sm, flexShrink: 1 },

  // Info-tab cards — each visible section is its own brutalist outlined
  // box with air between. No shadows, no fills.
  infoCard: {
    backgroundColor: 'transparent',
    borderRadius: radius.lg,
    borderWidth: 1,
    borderColor: colors.borderMuted,
    padding: spacing.md,
    marginBottom: spacing.md,
  },
  // Stats block — borderless. Drops infoCard's inner padding so the
  // chips line up with the bordered cards' OUTER edge.
  statsBlock: {
    marginBottom: spacing.md,
  },
  // Hero — banner-style card. Color block on top carries the brand-
  // moment (sport-category color, decorative sport icon, oversized
  // inverted title). Footer below stays neutral with date + visibility.
  heroCard: {
    borderRadius: radius.lg,
    borderWidth: 1,
    borderColor: colors.borderMuted,
    marginBottom: spacing.md,
    overflow: 'hidden',
  },
  heroBanner: {
    paddingHorizontal: spacing.md,
    paddingTop: spacing.md,
    paddingBottom: spacing.lg,
    position: 'relative',
  },
  // Decorative sport icon at top-right of the banner. Big, low-key
  // so it adds character without competing with the title.
  heroSportDecor: {
    position: 'absolute',
    top: spacing.sm,
    right: spacing.md,
    fontSize: 56,
    opacity: 0.35,
  },
  heroSportLabel: {
    color: '#FFFFFF',
    fontSize: fontSizes.xs,
    fontWeight: '800',
    textTransform: 'uppercase',
    letterSpacing: 1.5,
    opacity: 0.9,
    marginBottom: spacing.xs,
  },
  heroTitleInverse: {
    color: '#FFFFFF',
    fontSize: fontSizes.xxl,
    fontFamily: fonts.title,
    letterSpacing: -0.5,
    lineHeight: 36,
    paddingRight: 64, // leave room for the decorative icon
  },
  heroFooter: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm + 2,
  },
  heroDateText: {
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
    fontWeight: '700',
    flex: 1,
  },
  heroVisibility: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
  },
  heroVisibilityText: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    fontWeight: '600',
  },
  // Status banner — full-width above the hero. Replaces the old
  // inactive/pending/accepted banners + presence pills.
  statusBannerTop: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
    marginBottom: spacing.md,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.borderMuted,
    backgroundColor: colors.surface,
  },
  statusBannerPending: { borderColor: colors.warning, backgroundColor: colors.warning + '12' },
  statusBannerAccepted: { borderColor: colors.success, backgroundColor: colors.success + '12' },
  statusBannerConfirmed: { borderColor: colors.success, backgroundColor: colors.success + '12' },
  statusBannerCheckIn: { borderColor: colors.cta, backgroundColor: colors.cta + '12' },
  statusBannerText: {
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
    fontWeight: '700',
  },

  // Sticky footer — anchors the primary CTA at the bottom of the
  // viewport so the most consequential action never scrolls out of
  // reach. 1px top border keeps it visually attached to the page.
  stickyFooter: {
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.sm,
    backgroundColor: colors.background,
    borderTopWidth: 1,
    borderTopColor: colors.borderMuted,
    gap: spacing.sm,
  },
  header: { flexDirection: 'row', alignItems: 'center', marginBottom: spacing.lg, gap: spacing.sm },
  headerStatus: { paddingHorizontal: spacing.sm, paddingVertical: 4, borderRadius: radius.sm },
  // Visibility twin-pill — same height/radius as the status pill, quiet
  // surface fill so both info chips share one grammar.
  headerVisPill: {
    flexDirection: 'row',
    gap: 4,
    paddingHorizontal: spacing.sm - 2,
    paddingVertical: 4,
    borderRadius: radius.sm,
    backgroundColor: colors.surface,
    alignItems: 'center',
    justifyContent: 'center',
    alignSelf: 'stretch',
  },
  headerVisText: { color: colors.textSecondary, fontSize: fontSizes.xs - 1, fontWeight: '600', maxWidth: 110 },
  headerStatusText: { color: colors.textPrimary, fontSize: fontSizes.xs - 1, fontWeight: 'bold' },
  headerPills: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.xs + 2,
    marginBottom: spacing.sm + 2,
  },
  sportPill: {
    flexDirection: 'row', alignItems: 'center', gap: 5,
    backgroundColor: 'transparent',
    borderWidth: 1, borderColor: colors.borderMuted,
    borderRadius: radius.sm,
    paddingHorizontal: spacing.sm + 2, paddingVertical: 5,
  },
  sportPillIcon: { fontSize: 14 },
  sportPillText: {
    color: colors.textPrimary, fontSize: fontSizes.xs + 1, fontWeight: '700',
    textTransform: 'uppercase',
    letterSpacing: 0.4,
  },
  visibilityPill: {
    flexDirection: 'row', alignItems: 'center', gap: 4,
    backgroundColor: colors.cta + '26',
    borderRadius: radius.sm,
    paddingHorizontal: spacing.sm, paddingVertical: 4,
  },
  visibilityPillText: { color: colors.cta, fontSize: fontSizes.xs, fontWeight: '600' },
  titleLarge: {
    color: colors.textPrimary,
    fontSize: fontSizes.xxl,
    fontFamily: fonts.title,
    letterSpacing: -0.5,
    lineHeight: 36,
  },
  sportIcon: { fontSize: 20 },
  sport: { color: colors.textSecondary, fontSize: fontSizes.sm, textTransform: 'capitalize' },
  visibilityBadge: { flexDirection: 'row', alignItems: 'center', gap: 4, backgroundColor: colors.surface, borderRadius: radius.sm, paddingHorizontal: spacing.sm, paddingVertical: 4, marginLeft: 'auto' },
  visibilityText: { color: colors.textSecondary, fontSize: fontSizes.xs },
  separator: { height: 1, backgroundColor: colors.borderMuted, marginVertical: spacing.md },
  titleRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginBottom: spacing.md },
  title: { color: colors.textPrimary, fontSize: fontSizes.xl, fontWeight: 'bold', flex: 1 },
  participantsModalRoot: { flex: 1, backgroundColor: colors.background },
  participantsModalHeader: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    paddingHorizontal: spacing.lg, paddingVertical: spacing.md,
    borderBottomWidth: 1, borderBottomColor: colors.borderMuted,
  },
  participantsModalTitle: {
    color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: '700',
  },
  inactiveBanner: { backgroundColor: colors.textSecondary + '20', borderRadius: radius.sm, padding: spacing.md, marginBottom: spacing.md },
  inactiveText: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: 'bold', textAlign: 'center' },
  pendingBanner: { backgroundColor: colors.warning + '20', borderRadius: radius.sm, padding: spacing.md, marginBottom: spacing.md },
  pendingText: { color: colors.warning, fontSize: fontSizes.sm, fontWeight: 'bold', textAlign: 'center' },
  acceptedBanner: { backgroundColor: colors.success + '20', borderRadius: radius.sm, padding: spacing.md, marginBottom: spacing.md },
  acceptedText: { color: colors.success, fontSize: fontSizes.sm, fontWeight: 'bold', textAlign: 'center' },
  infoGrid: {
    backgroundColor: colors.surface, borderRadius: radius.sm, padding: spacing.md, marginBottom: spacing.lg, gap: spacing.sm,
    borderWidth: 1, borderColor: colors.borderMuted,
  },
  infoRow: { flexDirection: 'row', justifyContent: 'space-between' },
  infoLabel: { color: colors.textSecondary, fontSize: fontSizes.sm },
  infoValue: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: 'bold' },
  section: { marginBottom: spacing.lg },
  sectionTitle: { color: colors.textPrimary, fontSize: fontSizes.xs, fontWeight: 'bold', letterSpacing: 0.5, marginBottom: spacing.sm, textTransform: 'uppercase' },
  fullMapContainer: { flex: 1, backgroundColor: colors.background },
  fullMapLegendWrapper: { position: 'absolute', right: 12, zIndex: 10 },
  closeMapButton: { position: 'absolute', left: 20, width: 36, height: 36, borderRadius: radius.sm, backgroundColor: colors.background, alignItems: 'center', justifyContent: 'center', zIndex: 10, borderWidth: 1, borderColor: colors.borderStrong },
  closeMapText: { color: colors.textPrimary, fontSize: 18, fontWeight: 'bold' },
  navigateButton: { position: 'absolute', alignSelf: 'center', backgroundColor: colors.cta, borderRadius: radius.sm, paddingHorizontal: spacing.xl, paddingVertical: spacing.sm + 2, zIndex: 10 },
  navigateText: { color: '#FFFFFF', fontSize: fontSizes.md, fontWeight: '700' },
  presenceBlock: {
    backgroundColor: colors.surface, borderRadius: radius.sm, padding: spacing.md,
    marginTop: spacing.md, marginBottom: spacing.md, gap: spacing.sm,
    borderWidth: 1, borderColor: colors.borderMuted,
  },
  presenceBlockActive: {
    borderColor: colors.success, backgroundColor: colors.success + '20',
  },
  presenceHeader: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
  presenceTitle: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: 'bold' },
  presenceSubtitle: { color: colors.textSecondary, fontSize: fontSizes.xs },
  presenceActions: { flexDirection: 'row', gap: spacing.sm, marginTop: spacing.xs },
  presenceButton: {
    flex: 1, backgroundColor: colors.cta, borderRadius: radius.sm,
    paddingVertical: spacing.sm, alignItems: 'center',
  },
  presenceButtonText: { color: '#FFFFFF', fontSize: fontSizes.xs, fontWeight: '700' },
  presenceSecondaryButton: {
    flex: 1, backgroundColor: 'transparent', borderRadius: radius.sm,
    paddingVertical: spacing.sm, alignItems: 'center',
    borderWidth: 1, borderColor: colors.borderStrong,
  },
  presenceSecondaryText: { color: colors.textPrimary, fontSize: fontSizes.xs, fontWeight: '700' },
  presenceCreatorButton: {
    backgroundColor: 'transparent', borderRadius: radius.sm,
    paddingVertical: spacing.sm + 2, alignItems: 'center',
    marginTop: spacing.sm, marginBottom: spacing.sm,
    borderWidth: 1, borderColor: colors.cta,
  },
  presenceCreatorText: { color: colors.cta, fontSize: fontSizes.sm, fontWeight: '700' },
  presenceDone: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'center',
    gap: spacing.xs, marginTop: spacing.sm, marginBottom: spacing.sm,
  },
  presenceDoneText: { color: colors.success, fontSize: fontSizes.sm, fontWeight: 'bold' },
  joinButton: {
    backgroundColor: colors.cta,
    borderRadius: radius.lg,
    paddingVertical: spacing.md + 2,
    alignItems: 'center',
    shadowColor: colors.cta,
    shadowOpacity: 0.35,
    shadowRadius: 12,
    shadowOffset: { width: 0, height: 6 },
    elevation: 6,
  },
  fullButton: { flexDirection: 'row', backgroundColor: 'transparent', borderRadius: radius.sm, paddingVertical: spacing.sm + 2, alignItems: 'center', justifyContent: 'center', gap: spacing.xs, borderWidth: 1, borderColor: colors.error },
  fullButtonText: { color: colors.error, fontSize: fontSizes.md, fontWeight: '700' },
  leaveButton: { backgroundColor: 'transparent', borderRadius: radius.sm, paddingVertical: spacing.sm + 2, alignItems: 'center', borderWidth: 1, borderColor: colors.borderStrong },
  buttonDisabled: { opacity: 0.4 },
  buttonText: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '700' },
  joinButtonText: { color: '#FFFFFF', fontSize: fontSizes.md, fontWeight: '700' },
  reportLink: { paddingVertical: spacing.sm, alignItems: 'center', marginTop: spacing.md },
  reportLinkText: { color: colors.textSecondary, fontSize: fontSizes.xs },
  tooltipBackdrop: { flex: 1 },
  tooltip: {
    position: 'absolute', top: 90, right: spacing.lg,
    flexDirection: 'row', gap: spacing.sm,
    backgroundColor: colors.background, borderRadius: radius.sm,
    paddingHorizontal: spacing.sm, paddingVertical: spacing.xs,
    borderWidth: 1, borderColor: colors.borderStrong,
  },
  tooltipItem: { width: 36, height: 36, borderRadius: radius.sm, alignItems: 'center', justifyContent: 'center' },
  tooltipIcon: { fontSize: 18 },
  tooltipIconDanger: { fontSize: 18, color: colors.error, fontWeight: 'bold' },
});
