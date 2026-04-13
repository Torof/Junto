import { View, Text, ScrollView, Pressable, Modal, StyleSheet, Alert, Share, Linking } from 'react-native';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';
import { useState } from 'react';
import { useRouter } from 'expo-router';
import dayjs from 'dayjs';
import { useTranslation } from 'react-i18next';
import { useQueryClient } from '@tanstack/react-query';
import * as Burnt from 'burnt';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';
import { activityService, type NearbyActivity } from '@/services/activity-service';
import { participationService, type Participation } from '@/services/participation-service';
import { getActivityTimeStatus, getStatusColor, getRemainingPlaces } from '@/utils/activity-status';
import { getSportIcon } from '@/constants/sport-icons';
import { JuntoMapView, type MapPin } from './map-view';
import { ParticipantList } from './participant-list';
import { ActivityWall } from './activity-wall';
import { ReportModal } from './report-modal';

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
  const { t } = useTranslation();
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const queryClient = useQueryClient();
  const [isLoading, setIsLoading] = useState(false);
  const [showMenu, setShowMenu] = useState(false);
  const [showReport, setShowReport] = useState(false);
  const [showFullMap, setShowFullMap] = useState(false);

  const timeStatus = getActivityTimeStatus(activity.starts_at, activity.status);
  const statusColor = getStatusColor(timeStatus);
  const remaining = getRemainingPlaces(activity.max_participants, activity.participant_count);

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
      Alert.alert(t('auth.error'), err instanceof Error ? err.message : t('auth.unknownError'));
    } finally {
      setIsLoading(false);
    }
  };

  const handleLeave = async () => {
    setIsLoading(true);
    try {
      await participationService.leave(activity.id);
      await queryClient.invalidateQueries({ queryKey: ['participation', activity.id] });
      await queryClient.invalidateQueries({ queryKey: ['activity', activity.id] });
      await queryClient.invalidateQueries({ queryKey: ['activities'] });
      Burnt.toast({ title: t('toast.leftActivity') });
    } catch (err) {
      Alert.alert(t('auth.error'), err instanceof Error ? err.message : t('auth.unknownError'));
    } finally {
      setIsLoading(false);
    }
  };

  const handleCancel = async () => {
    Alert.alert(t('activity.cancelConfirmTitle'), t('activity.cancelConfirmMessage'), [
      { text: t('activity.no'), style: 'cancel' },
      {
        text: t('activity.yes'),
        style: 'destructive',
        onPress: async () => {
          setIsLoading(true);
          try {
            await participationService.cancel(activity.id);
            await queryClient.invalidateQueries({ queryKey: ['activities'] });
            Burnt.toast({ title: t('toast.activityCancelled') });
          } catch (err) {
            Alert.alert(t('auth.error'), err instanceof Error ? err.message : t('auth.unknownError'));
          } finally {
            setIsLoading(false);
          }
        },
      },
    ]);
  };

  const handleShare = async () => {
    try {
      const token = await activityService.getInviteToken(activity.id);
      if (!token) return;
      const link = `junto://invite/${token}`;
      await Share.share({
        message: `${activity.title} — ${link}`,
      });
    } catch {
      // User cancelled share — do nothing
    }
  };

  const canRejoin = participation && ['withdrawn', 'refused'].includes(participation.status);
  const isActive = ['published', 'in_progress'].includes(activity.status);
  const showJoinButton = !isCreator && (!participation || canRejoin) && remaining > 0 && isActive;
  const showLeaveButton = !isCreator && participation && ['accepted', 'pending'].includes(participation.status) && isActive;
  const showCancelButton = isCreator && isActive;
  const isPending = participation?.status === 'pending';
  const isAccepted = participation?.status === 'accepted';

  const joinLabel = activity.visibility === 'approval' || activity.visibility === 'private_link_approval'
    ? t('activity.requestJoin')
    : t('activity.join');

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content}>
      <View style={styles.header}>
        <View style={[styles.statusBadge, { backgroundColor: statusColor }]}>
          <Text style={styles.statusText}>{t(`activity.status.${timeStatus}`)}</Text>
        </View>
        <Text style={styles.sportIcon}>{getSportIcon(activity.sport_key)}</Text>
        <Text style={styles.sport}>{t(`sports.${activity.sport_key}`, activity.sport_key)}</Text>
      </View>

      <View style={styles.titleRow}>
        <Text style={styles.title}>{activity.title}</Text>
        {isCreator && (
          <Pressable style={styles.moreButton} onPress={() => setShowMenu(true)}>
            <Text style={styles.moreText}>⋯</Text>
          </Pressable>
        )}
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
          <Text style={styles.infoLabel}>{dayjs(activity.starts_at).format('ddd D MMM')}</Text>
          <Text style={styles.infoValue}>{dayjs(activity.starts_at).format('HH:mm')}</Text>
        </View>
        <View style={styles.infoRow}>
          <Text style={styles.infoLabel}>{t('activity.duration')}</Text>
          <Text style={styles.infoValue}>{activity.duration}</Text>
        </View>
        <View style={styles.infoRow}>
          <Text style={styles.infoLabel}>{t('activity.places', { remaining, max: activity.max_participants })}</Text>
          <Text style={styles.infoValue}>{activity.participant_count}/{activity.max_participants}</Text>
        </View>
      </View>

      {activity.description ? (
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>{t('activity.description')}</Text>
          <Text style={styles.description}>{activity.description}</Text>
        </View>
      ) : null}

      {(isCreator || isAccepted) && (() => {
        const mapPins: MapPin[] = [
          { id: 'start', coordinate: [activity.lng, activity.lat], color: '#22c55e' },
          ...(activity.meeting_lng && activity.meeting_lat
            ? [{ id: 'meeting', coordinate: [activity.meeting_lng, activity.meeting_lat] as [number, number], color: '#3b82f6' }]
            : []),
          ...(activity.end_lng && activity.end_lat
            ? [{ id: 'end', coordinate: [activity.end_lng, activity.end_lat] as [number, number], color: '#ef4444' }]
            : []),
        ];
        const allLngs = mapPins.map((p) => p.coordinate[0]);
        const allLats = mapPins.map((p) => p.coordinate[1]);
        const centerLng = (Math.min(...allLngs) + Math.max(...allLngs)) / 2;
        const centerLat = (Math.min(...allLats) + Math.max(...allLats)) / 2;
        const spread = Math.max(Math.max(...allLngs) - Math.min(...allLngs), Math.max(...allLats) - Math.min(...allLats));
        const mapZoom = spread > 0.1 ? 10 : spread > 0.01 ? 12 : 14;
        const mapRouteLine = activity.end_lng && activity.end_lat
          ? [[activity.lng, activity.lat], [activity.end_lng, activity.end_lat]] as [number, number][]
          : undefined;

        return (
          <View style={styles.section}>
            <Text style={styles.sectionTitle}>{t('activity.location')}</Text>
            <Pressable style={styles.mapContainer} onPress={() => setShowFullMap(true)}>
              <JuntoMapView center={[centerLng, centerLat]} zoom={mapZoom} pins={mapPins} routeLine={mapRouteLine} />
              <View style={styles.mapTapOverlay} pointerEvents="box-only" />
            </Pressable>

            <Modal visible={showFullMap} animationType="slide">
              <SafeAreaView style={styles.fullMapContainer} edges={['top']}>
                <JuntoMapView center={[centerLng, centerLat]} zoom={mapZoom} pins={mapPins} routeLine={mapRouteLine} />
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
          </View>
        );
      })()}

      <ParticipantList
        activityId={activity.id}
        isCreator={isCreator}
        creatorId={activity.creator_id}
        creatorName={activity.creator_name}
        creatorAvatar={activity.creator_avatar}
        onProfilePress={!isAuthenticated ? () => onJoinRedirect?.() : undefined}
      />

      {(isCreator || isAccepted) && (
        <ActivityWall
          activityId={activity.id}
          isActive={['published', 'in_progress'].includes(activity.status)}
        />
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
          onPress={handleLeave}
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

      <ReportModal
        visible={showReport}
        targetType="activity"
        targetId={activity.id}
        onClose={() => setShowReport(false)}
      />

      {/* Creator actions tooltip */}
      {showMenu && (
        <Modal visible animationType="none" transparent>
          <Pressable style={styles.tooltipBackdrop} onPress={() => setShowMenu(false)}>
            <View style={styles.tooltip}>
              {isActive && (
                <Pressable style={styles.tooltipItem} onPress={() => { setShowMenu(false); router.push(`/(auth)/edit/${activity.id}`); }}>
                  <Text style={styles.tooltipIcon}>✏️</Text>
                </Pressable>
              )}
              <Pressable style={styles.tooltipItem} onPress={() => { setShowMenu(false); handleShare(); }}>
                <Text style={styles.tooltipIcon}>🔗</Text>
              </Pressable>
              {showCancelButton && (
                <Pressable style={styles.tooltipItem} onPress={() => { setShowMenu(false); handleCancel(); }}>
                  <Text style={styles.tooltipIconDanger}>✕</Text>
                </Pressable>
              )}
            </View>
          </Pressable>
        </Modal>
      )}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  content: { padding: spacing.lg, paddingBottom: spacing.xl + 32 },
  header: { flexDirection: 'row', alignItems: 'center', marginBottom: spacing.sm, gap: spacing.sm },
  statusBadge: { paddingHorizontal: spacing.sm, paddingVertical: spacing.xs, borderRadius: radius.full },
  statusText: { color: colors.textPrimary, fontSize: fontSizes.xs, fontWeight: 'bold' },
  sportIcon: { fontSize: 20 },
  sport: { color: colors.textSecondary, fontSize: fontSizes.sm, textTransform: 'capitalize' },
  titleRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginBottom: spacing.md },
  title: { color: colors.textPrimary, fontSize: fontSizes.xl, fontWeight: 'bold', flex: 1 },
  moreButton: { width: 36, height: 36, borderRadius: 18, backgroundColor: colors.surface, alignItems: 'center', justifyContent: 'center' },
  moreText: { fontSize: 20, color: colors.textSecondary, fontWeight: 'bold' },
  inactiveBanner: { backgroundColor: colors.textSecondary + '20', borderRadius: radius.md, padding: spacing.md, marginBottom: spacing.md },
  inactiveText: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: 'bold', textAlign: 'center' },
  pendingBanner: { backgroundColor: colors.warning + '20', borderRadius: radius.md, padding: spacing.md, marginBottom: spacing.md },
  pendingText: { color: colors.warning, fontSize: fontSizes.sm, fontWeight: 'bold', textAlign: 'center' },
  acceptedBanner: { backgroundColor: colors.success + '20', borderRadius: radius.md, padding: spacing.md, marginBottom: spacing.md },
  acceptedText: { color: colors.success, fontSize: fontSizes.sm, fontWeight: 'bold', textAlign: 'center' },
  infoGrid: { backgroundColor: colors.surface, borderRadius: radius.md, padding: spacing.md, marginBottom: spacing.lg, gap: spacing.sm },
  infoRow: { flexDirection: 'row', justifyContent: 'space-between' },
  infoLabel: { color: colors.textSecondary, fontSize: fontSizes.sm },
  infoValue: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: 'bold' },
  section: { marginBottom: spacing.lg },
  sectionTitle: { color: colors.textSecondary, fontSize: fontSizes.xs, marginBottom: spacing.sm, textTransform: 'uppercase' },
  description: { color: colors.textPrimary, fontSize: fontSizes.md, lineHeight: 22 },
  mapContainer: { height: 200, borderRadius: radius.md, overflow: 'hidden' },
  mapTapOverlay: { ...StyleSheet.absoluteFillObject },
  fullMapContainer: { flex: 1, backgroundColor: colors.background },
  closeMapButton: { position: 'absolute', top: 35, left: 20, width: 40, height: 40, borderRadius: 20, backgroundColor: colors.background, alignItems: 'center', justifyContent: 'center', zIndex: 10 },
  closeMapText: { color: colors.textPrimary, fontSize: 18, fontWeight: 'bold' },
  navigateButton: { position: 'absolute', alignSelf: 'center', backgroundColor: colors.cta, borderRadius: radius.full, paddingHorizontal: spacing.xl, paddingVertical: spacing.md, zIndex: 10 },
  navigateText: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: 'bold' },
  joinButton: { backgroundColor: colors.cta, borderRadius: radius.md, paddingVertical: spacing.md, alignItems: 'center', marginTop: spacing.md },
  leaveButton: { backgroundColor: colors.surface, borderRadius: radius.md, paddingVertical: spacing.md, alignItems: 'center', marginTop: spacing.md, borderWidth: 1, borderColor: colors.textSecondary },
  buttonDisabled: { opacity: 0.4 },
  buttonText: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: 'bold' },
  reportLink: { paddingVertical: spacing.sm, alignItems: 'center', marginTop: spacing.md },
  reportLinkText: { color: colors.textSecondary, fontSize: fontSizes.xs },
  tooltipBackdrop: { flex: 1 },
  tooltip: {
    position: 'absolute', top: 90, right: spacing.lg,
    flexDirection: 'row', gap: spacing.sm,
    backgroundColor: '#ffffff', borderRadius: radius.md,
    paddingHorizontal: spacing.sm, paddingVertical: spacing.xs,
    elevation: 5, shadowColor: '#000', shadowOffset: { width: 0, height: 2 }, shadowOpacity: 0.3, shadowRadius: 4,
  },
  tooltipItem: { width: 36, height: 36, borderRadius: 18, alignItems: 'center', justifyContent: 'center' },
  tooltipIcon: { fontSize: 18 },
  tooltipIconDanger: { fontSize: 18, color: colors.error, fontWeight: 'bold' },
});
