import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import { BottomSheetModal, BottomSheetView, BottomSheetBackdrop, type BottomSheetBackdropProps } from '@gorhom/bottom-sheet';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { useQuery } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import dayjs from 'dayjs';
import { CalendarCheck, Radar, Briefcase, Settings, ChevronRight, LogOut, Route, Users, Bookmark, CalendarDays } from 'lucide-react-native';
import { fontSizes, spacing, radius, shadows } from '@/constants/theme';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import { useAuth } from '@/hooks/use-auth';
import { userService } from '@/services/user-service';
import { proService } from '@/services/pro-service';
import { bookingService } from '@/services/booking-service';
import { authService } from '@/services/auth-service';
import { UserAvatar } from './user-avatar';
import { SettingsDrawer } from './settings-drawer';

// The "Menu" tab's deployable sheet (Scott, 2026-07-06): absorbs the
// low-frequency destinations so the bar stays at 4 tabs — identity row →
// Profil, then Notifications (badged), Mes alertes, Ma page pro (pros only),
// Paramètres (opens the existing SettingsDrawer). Same modal shell as the
// map drawers.
interface Props {
  open: boolean;
  onClose: () => void;
}

export function MenuSheet({ open, onClose }: Props) {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const modalRef = useRef<BottomSheetModal>(null);
  const insets = useSafeAreaInsets();
  const router = useRouter();
  const { session } = useAuth();
  const [settingsOpen, setSettingsOpen] = useState(false);

  const userId = session?.user?.id ?? null;

  useEffect(() => {
    if (open) modalRef.current?.present();
    else modalRef.current?.dismiss();
  }, [open]);

  // Tapping the map / anything behind the sheet closes it (was swipe-only).
  const renderBackdrop = useCallback((props: BottomSheetBackdropProps) => (
    <BottomSheetBackdrop {...props} appearsOnIndex={0} disappearsOnIndex={-1} pressBehavior="close" />
  ), []);

  const { data: profile } = useQuery({
    queryKey: ['public-profile', userId],
    queryFn: () => userService.getPublicProfile(userId as string),
    enabled: !!userId,
  });

  // Non-null pro profile = the user has a pro page.
  const { data: proProfile } = useQuery({
    queryKey: ['pro-profile', userId],
    queryFn: () => proService.getById(userId as string),
    enabled: !!userId,
  });

  // Badge « Espace pro » : demandes de réservation en attente (même clé de
  // cache que le dashboard pro → un seul fetch).
  const agendaFrom = dayjs().format('YYYY-MM-DD');
  const agendaTo = dayjs().add(1, 'month').format('YYYY-MM-DD');
  // The RLS shows a pro their own row at any status, but the agenda RPC and
  // the whole Espace pro are approved-only — a pending pro saw the entry and
  // an empty dashboard that silently failed (audit 2026-10-08).
  const isApprovedPro = proProfile?.status === 'approved';
  const { data: proAgenda } = useQuery({
    queryKey: ['pro-agenda', agendaFrom, agendaTo],
    queryFn: () => bookingService.getAgenda(agendaFrom, agendaTo),
    enabled: isApprovedPro,
  });
  const pendingBookings = (proAgenda ?? []).filter((a) => a.kind === 'booking' && a.status === 'pending').length;

  const go = (path: string) => {
    modalRef.current?.dismiss();
    router.push(path as never);
  };

  // The tab bar is 64 + bottom inset tall (see (tabs)/_layout) — the sheet
  // sits above it like the map drawers do.
  const tabBarHeight = 64 + insets.bottom;

  return (
    <>
      <BottomSheetModal
        ref={modalRef}
        topInset={insets.top}
        bottomInset={tabBarHeight}
        enablePanDownToClose
        enableDynamicSizing
        backdropComponent={renderBackdrop}
        onDismiss={onClose}
        backgroundStyle={styles.bg}
        handleComponent={() => (
          <View style={styles.handle}>
            <View style={styles.grabber} />
          </View>
        )}
      >
        <BottomSheetView style={styles.content}>
          {/* Identity row → full profile */}
          <Pressable style={styles.identityRow} onPress={() => go('/(auth)/(tabs)/profil')}>
            <UserAvatar name={profile?.display_name ?? '?'} avatarUrl={profile?.avatar_url ?? null} size={44} />
            <View style={styles.identityInfo}>
              <Text style={styles.identityName} numberOfLines={1}>{profile?.display_name ?? '…'}</Text>
              <Text style={styles.identityHint}>{t('menu.seeProfile', { defaultValue: 'Voir mon profil' })}</Text>
            </View>
            <ChevronRight size={18} color={colors.textSecondary} strokeWidth={2.2} />
          </Pressable>

          <View style={styles.divider} />

          <MenuItem
            icon={<CalendarDays size={20} color={colors.textPrimary} strokeWidth={2.2} />}
            label={t('menu.mesActivites', { defaultValue: 'Mes sorties' })}
            onPress={() => go('/(auth)/(tabs)/mes-activites')}
            styles={styles}
            colors={colors}
          />
          <MenuItem
            icon={<Radar size={20} color={colors.textPrimary} strokeWidth={2.2} />}
            label={t('menu.alerts', { defaultValue: 'Alertes' })}
            onPress={() => go('/(auth)/create-alert')}
            styles={styles}
            colors={colors}
          />
          <MenuItem
            icon={<Route size={20} color={colors.textPrimary} strokeWidth={2.2} />}
            label={t('menu.gpxTraces', { defaultValue: 'Traces GPX' })}
            onPress={() => go('/(auth)/gpx-traces')}
            styles={styles}
            colors={colors}
          />
          <MenuItem
            icon={<Users size={20} color={colors.textPrimary} strokeWidth={2.2} />}
            label={t('menu.contacts', { defaultValue: 'Contacts' })}
            onPress={() => go('/(auth)/contacts')}
            styles={styles}
            colors={colors}
          />
          <MenuItem
            icon={<CalendarCheck size={20} color={colors.textPrimary} strokeWidth={2.2} />}
            label={t('menu.myBookings', { defaultValue: 'Mes réservations' })}
            onPress={() => go('/(auth)/my-bookings')}
            styles={styles}
            colors={colors}
          />
          <MenuItem
            icon={<Bookmark size={20} color={colors.textPrimary} strokeWidth={2.2} />}
            label={t('menu.favorites', { defaultValue: 'Favoris' })}
            onPress={() => go('/(auth)/favorites')}
            styles={styles}
            colors={colors}
          />
          {/* The pro entry lives HERE at every stage (lot 2 pro, 2026-10-15):
              « Devenir pro » for everyone, the application status while it is
              reviewed, « Espace pro » once approved — same slot before/after,
              no more « Devenir pro » buried in Paramètres › Compte. */}
          {isApprovedPro ? (
            <MenuItem
              icon={<Briefcase size={20} color={colors.pinProBackground} strokeWidth={2.2} />}
              label={t('menu.proSpace', { defaultValue: 'Espace pro' })}
              badge={pendingBookings > 0 ? String(pendingBookings) : null}
              onPress={() => go('/(auth)/pro/espace')}
              styles={styles}
              colors={colors}
            />
          ) : proProfile?.status === 'pending' ? (
            <MenuItem
              icon={<Briefcase size={20} color={colors.pinProBackground} strokeWidth={2.2} />}
              label={t('pro.statusPending', { defaultValue: 'Demande pro en attente' })}
              sub={t('pro.statusPendingSub', { defaultValue: 'On te prévient dès qu’elle est validée' })}
              onPress={() => go('/(auth)/pro/edit')}
              styles={styles}
              colors={colors}
            />
          ) : proProfile?.status === 'rejected' ? (
            <MenuItem
              icon={<Briefcase size={20} color={colors.error} strokeWidth={2.2} />}
              label={t('pro.statusRejected', { defaultValue: 'Demande pro refusée — corriger' })}
              onPress={() => go('/(auth)/pro/edit')}
              styles={styles}
              colors={colors}
            />
          ) : (
            <MenuItem
              icon={<Briefcase size={20} color={colors.pinProBackground} strokeWidth={2.2} />}
              label={t('drawer.becomePro', { defaultValue: 'Devenir pro' })}
              sub={t('menu.becomeProSub', { defaultValue: 'Ta page, tes sorties, tes réservations' })}
              onPress={() => go('/(auth)/pro/edit')}
              styles={styles}
              colors={colors}
            />
          )}
          <MenuItem
            icon={<Settings size={20} color={colors.textPrimary} strokeWidth={2.2} />}
            label={t('menu.settings', { defaultValue: 'Paramètres' })}
            onPress={() => {
              modalRef.current?.dismiss();
              setSettingsOpen(true);
            }}
            styles={styles}
            colors={colors}
          />

          <View style={styles.divider} />

          <Pressable
            style={styles.item}
            onPress={async () => {
              modalRef.current?.dismiss();
              await authService.signOut();
            }}
          >
            <View style={styles.itemIcon}>
              <LogOut size={20} color={colors.error} strokeWidth={2.2} />
            </View>
            <Text style={[styles.itemLabel, { color: colors.error }]}>
              {t('menu.signOut', { defaultValue: 'Se déconnecter' })}
            </Text>
          </Pressable>
        </BottomSheetView>
      </BottomSheetModal>

      <SettingsDrawer visible={settingsOpen} onClose={() => setSettingsOpen(false)} />
    </>
  );
}

function MenuItem({
  icon,
  label,
  sub,
  badge,
  onPress,
  styles,
  colors,
}: {
  icon: React.ReactNode;
  label: string;
  sub?: string;
  badge?: string | null;
  onPress: () => void;
  styles: ReturnType<typeof createStyles>;
  colors: AppColors;
}) {
  return (
    <Pressable style={styles.item} onPress={onPress}>
      <View style={styles.itemIcon}>{icon}</View>
      <View style={{ flex: 1, minWidth: 0 }}>
        <Text style={styles.itemLabel}>{label}</Text>
        {sub ? <Text style={styles.itemSub} numberOfLines={1}>{sub}</Text> : null}
      </View>
      {badge ? (
        <View style={styles.itemBadge}>
          <Text style={styles.itemBadgeText}>{badge}</Text>
        </View>
      ) : null}
      <ChevronRight size={16} color={colors.textSecondary} strokeWidth={2.2} />
    </Pressable>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  bg: {
    backgroundColor: colors.surface,
    borderTopLeftRadius: radius.xl,
    borderTopRightRadius: radius.xl,
    ...shadows.sheet,
  },
  handle: {
    alignItems: 'center',
    paddingTop: 10,
    paddingBottom: 6,
    backgroundColor: colors.surface,
    borderTopLeftRadius: radius.xl,
    borderTopRightRadius: radius.xl,
    borderTopWidth: 1,
    borderLeftWidth: 1,
    borderRightWidth: 1,
    borderColor: colors.borderMuted,
  },
  grabber: { height: 4, width: 40, borderRadius: 2, backgroundColor: colors.textMuted },
  content: { paddingHorizontal: spacing.lg, paddingBottom: spacing.lg, gap: 2 },
  identityRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
    paddingVertical: spacing.sm,
  },
  identityInfo: { flex: 1, minWidth: 0 },
  identityName: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: '800' },
  identityHint: { color: colors.cta, fontSize: fontSizes.sm, fontWeight: '700', marginTop: 2 },
  divider: { height: 1, backgroundColor: colors.line, marginVertical: spacing.xs },
  item: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
    paddingVertical: spacing.sm + 2,
  },
  itemIcon: { width: 26, alignItems: 'center' },
  itemLabel: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '600' },
  itemSub: { color: colors.textSecondary, fontSize: fontSizes.xs + 1, marginTop: 1 },
  itemBadge: {
    minWidth: 20,
    height: 20,
    borderRadius: 10,
    paddingHorizontal: 6,
    backgroundColor: colors.cta,
    alignItems: 'center',
    justifyContent: 'center',
  },
  itemBadgeText: { color: colors.background, fontSize: fontSizes.xs, fontWeight: '800' },
});
