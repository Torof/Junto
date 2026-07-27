import { useEffect, useMemo, useRef, useState } from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import { BottomSheetModal, BottomSheetView } from '@gorhom/bottom-sheet';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { useQuery } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import { Radar, Briefcase, Settings, ChevronRight, LogOut, Route, Users, Heart } from 'lucide-react-native';
import { fontSizes, spacing, radius, shadows } from '@/constants/theme';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import { useAuth } from '@/hooks/use-auth';
import { userService } from '@/services/user-service';
import { proService } from '@/services/pro-service';
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
            icon={<Radar size={20} color={colors.textPrimary} strokeWidth={2.2} />}
            label={t('menu.alerts', { defaultValue: 'Mes alertes' })}
            onPress={() => go('/(auth)/create-alert')}
            styles={styles}
            colors={colors}
          />
          <MenuItem
            icon={<Route size={20} color={colors.textPrimary} strokeWidth={2.2} />}
            label={t('menu.gpxTraces', { defaultValue: 'Mes traces GPX' })}
            onPress={() => go('/(auth)/gpx-traces')}
            styles={styles}
            colors={colors}
          />
          <MenuItem
            icon={<Users size={20} color={colors.textPrimary} strokeWidth={2.2} />}
            label={t('menu.contacts', { defaultValue: 'Mes contacts' })}
            onPress={() => go('/(auth)/contacts')}
            styles={styles}
            colors={colors}
          />
          <MenuItem
            icon={<Heart size={20} color={colors.textPrimary} strokeWidth={2.2} />}
            label={t('menu.favorites', { defaultValue: 'Mes favoris' })}
            onPress={() => go('/(auth)/favorites')}
            styles={styles}
            colors={colors}
          />
          {proProfile ? (
            <MenuItem
              icon={<Briefcase size={20} color={colors.pinProBackground} strokeWidth={2.2} />}
              label={t('menu.proPage', { defaultValue: 'Ma page pro' })}
              onPress={() => go(`/(auth)/pro/${userId}`)}
              styles={styles}
              colors={colors}
            />
          ) : null}
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
  badge,
  onPress,
  styles,
  colors,
}: {
  icon: React.ReactNode;
  label: string;
  badge?: string | null;
  onPress: () => void;
  styles: ReturnType<typeof createStyles>;
  colors: AppColors;
}) {
  return (
    <Pressable style={styles.item} onPress={onPress}>
      <View style={styles.itemIcon}>{icon}</View>
      <Text style={styles.itemLabel}>{label}</Text>
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
    backgroundColor: colors.surfaceAlt,
    borderTopLeftRadius: radius.xl,
    borderTopRightRadius: radius.xl,
    ...shadows.sheet,
  },
  handle: {
    alignItems: 'center',
    paddingTop: 10,
    paddingBottom: 6,
    backgroundColor: colors.surfaceAlt,
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
  itemLabel: { flex: 1, color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '600' },
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
