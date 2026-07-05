import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { View, StyleSheet, Dimensions, type LayoutChangeEvent } from 'react-native';
import { BottomSheetModal } from '@gorhom/bottom-sheet';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useBottomTabBarHeight } from '@react-navigation/bottom-tabs';
import { useQuery } from '@tanstack/react-query';
import { useRouter } from 'expo-router';
import { useColors } from '@/hooks/use-theme';
import { type AppColors } from '@/constants/colors';
import { radius, shadows } from '@/constants/theme';
import { useAuth } from '@/hooks/use-auth';
import { proService } from '@/services/pro-service';
import { type ProOffering } from '@/services/pro-offering-service';
import { ProDetail } from './pro-detail';
import { LogoSpinner } from './logo-spinner';

// PP (pro page) as a Google-style expandable drawer over the map — hosts the
// full ProDetail (tabs, contact, catalogue, avis) inside a gorhom sheet
// instead of a full-screen route. The /pro/[id] route stays for deep links.
//
// Uses BottomSheetModal (present/dismiss), NOT a conditionally-mounted
// <BottomSheet>. The modal shell stays mounted permanently (via the root
// BottomSheetModalProvider); opening a pro just present()s and closing
// dismiss()es. This is the fix for the "first open works, every reopen has dead
// drag + scroll" bug — conditionally mounting/unmounting the sheet left
// corrupted native gesture state under reanimated 4, which the next mount
// inherited. A persistent modal shell never unmounts, so it never corrupts.
//
// Collapsing place-sheet: content-panning is ON and ProDetail renders a
// BottomSheetScrollView, so gorhom coordinates drag ↔ scroll. The first snap
// sits at the header's divider (measured handle + header height).
const SCREEN_H = Dimensions.get('window').height;
// The collapsed peek stops a bit below the header divider so a sliver of the
// photo carousel shows — a natural "there's more, scroll/drag up" cue.
const PEEK_PHOTO_REVEAL = 48;

interface Props {
  // The selected pro's user id, or null when nothing is selected. Always
  // mounted; present()/dismiss() follow this value.
  userId: string | null;
  onClose: () => void;
  // Tapping a catalogue offering switches to the RA drawer (map cross-nav).
  onOpenOffering?: (offering: ProOffering) => void;
}

export function ProSheet({ userId, onClose, onOpenOffering }: Props) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const modalRef = useRef<BottomSheetModal>(null);
  const insets = useSafeAreaInsets();
  // The modal renders in a root portal (over the tab navigator), so lift its
  // bottom edge above the bottom tab bar to keep the bar visible + tappable.
  const tabBarHeight = useBottomTabBarHeight();
  const router = useRouter();
  const { session } = useAuth();
  const [headerH, setHeaderH] = useState(0);
  const [handleH, setHandleH] = useState(0);

  const { data: pro } = useQuery({
    queryKey: ['pro-profile', userId],
    queryFn: () => proService.getById(userId as string),
    enabled: !!userId,
  });

  const isOwner = !!pro && session?.user?.id === pro.user_id;

  // Present when a pro is selected, dismiss when cleared. The modal shell is
  // always mounted, so this is a stable, race-free open/close.
  useEffect(() => {
    if (userId) modalRef.current?.present();
    else modalRef.current?.dismiss();
  }, [userId]);

  // Freeze both measurements at their first non-zero value. onLayout can fire
  // repeatedly (the header grows as async data — rating row, owner avatar —
  // lands), and every change to snapPoints re-seeds gorhom's gesture math.
  // `prev || …` makes each a one-shot — once set, React bails on the identical
  // value, the sheet subtree stops re-rendering, the gesture stays stable.
  const onHandleLayout = useCallback((e: LayoutChangeEvent) => {
    const h = Math.round(e.nativeEvent.layout.height);
    setHandleH((prev) => prev || h);
  }, []);
  const onHeaderMeasured = useCallback((h: number) => {
    setHeaderH((prev) => prev || Math.round(h));
  }, []);

  // First snap = handle + header (through the divider), in px, so the collapsed
  // peek stops right below the action buttons. Falls back to a close estimate
  // until both are measured once (avoids a visible settle on open).
  // Top snap is '100%' (fills between topInset and the tab bar) rather than
  // '98%' on purpose: at 100% the sheet reaches gorhom's FILL_PARENT state
  // (animatedPosition === 0), the one scroll-unlock check that can't drift on a
  // sub-pixel settle — so inner scroll is reliably enabled when expanded.
  const snapPoints = useMemo<(string | number)[]>(() => {
    const first = headerH > 0 && handleH > 0
      ? headerH + handleH + PEEK_PHOTO_REVEAL
      : Math.round(SCREEN_H * 0.4);
    return [first, '100%'];
  }, [headerH, handleH]);

  // Stable identities so gorhom never remounts the handle (a remount re-fires
  // onLayout and disturbs the pan gesture) and ProDetail doesn't churn.
  const renderHandle = useCallback(() => (
    <View style={styles.handle} onLayout={onHandleLayout}>
      <View style={styles.grabber} />
    </View>
  ), [styles, onHandleLayout]);
  const handleClose = useCallback(() => modalRef.current?.dismiss(), []);
  const handleExpand = useCallback(() => modalRef.current?.snapToIndex(1), []);
  const handleEdit = useMemo(
    () => (isOwner ? () => router.push('/(auth)/pro/edit') : undefined),
    [isOwner, router],
  );

  return (
    <BottomSheetModal
      ref={modalRef}
      index={0}
      snapPoints={snapPoints}
      topInset={insets.top}
      bottomInset={tabBarHeight}
      enablePanDownToClose
      enableDynamicSizing={false}
      onDismiss={onClose}
      backgroundStyle={styles.bg}
      handleComponent={renderHandle}
    >
      {pro ? (
        <ProDetail
          pro={pro}
          isOwner={isOwner}
          onEdit={handleEdit}
          inSheet
          onClose={handleClose}
          onExpand={handleExpand}
          onHeaderMeasured={onHeaderMeasured}
          onOpenOffering={onOpenOffering}
        />
      ) : (
        <View style={styles.loading}>
          <LogoSpinner size={40} />
        </View>
      )}
    </BottomSheetModal>
  );
}

const createStyles = (colors: AppColors) =>
  StyleSheet.create({
    bg: {
      backgroundColor: colors.surfaceAlt,
      borderTopLeftRadius: radius.xl,
      borderTopRightRadius: radius.xl,
      // Depth over the map — heavy sheet dose so the top edge actually reads.
      ...shadows.sheet,
    },
    handle: {
      alignItems: 'center',
      paddingTop: 10,
      paddingBottom: 6,
      backgroundColor: colors.surfaceAlt,
      borderTopLeftRadius: radius.xl,
      borderTopRightRadius: radius.xl,
    },
    grabber: { height: 4, width: 40, borderRadius: 2, backgroundColor: colors.textMuted },
    loading: { paddingVertical: 80, alignItems: 'center' },
  });
