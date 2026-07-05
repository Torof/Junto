import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { View, StyleSheet, Dimensions, type LayoutChangeEvent } from 'react-native';
import { BottomSheetModal } from '@gorhom/bottom-sheet';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useBottomTabBarHeight } from '@react-navigation/bottom-tabs';
import { useColors } from '@/hooks/use-theme';
import { type AppColors } from '@/constants/colors';
import { radius, shadows } from '@/constants/theme';
import { type ProOffering } from '@/services/pro-offering-service';
import { OfferingDetail } from './offering-detail';

// RA (pro offering) as a Google-style expandable drawer over the map — the same
// BottomSheetModal shell as the PP ProSheet (present/dismiss, frozen
// measurements, divider snap + 100% top, bottomInset above the tab bar), but it
// hosts the single-scroll OfferingDetail (its own experience-listing identity).
const SCREEN_H = Dimensions.get('window').height;
// Peek stops a touch below the measured hero so a sliver of the content shows.
const PEEK_REVEAL = 40;

interface Props {
  // The selected offering, or null when nothing is selected. Always mounted;
  // present()/dismiss() follow this value so the modal shell never unmounts.
  offering: ProOffering | null;
  onClose: () => void;
  // Tapping the host ("Proposé par") switches to the PP drawer (map cross-nav).
  onOpenPro?: (userId: string, coordinate: [number, number]) => void;
}

export function OfferingSheet({ offering, onClose, onOpenPro }: Props) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const modalRef = useRef<BottomSheetModal>(null);
  const insets = useSafeAreaInsets();
  const tabBarHeight = useBottomTabBarHeight();
  const [headerH, setHeaderH] = useState(0);
  const [handleH, setHandleH] = useState(0);

  useEffect(() => {
    if (offering) modalRef.current?.present();
    else modalRef.current?.dismiss();
  }, [offering]);

  // Freeze both measurements at their first non-zero value (one-shot) so
  // snapPoints don't churn and wedge the gesture — mirrors ProSheet.
  const onHandleLayout = useCallback((e: LayoutChangeEvent) => {
    const h = Math.round(e.nativeEvent.layout.height);
    setHandleH((prev) => prev || h);
  }, []);
  const onHeaderMeasured = useCallback((h: number) => {
    setHeaderH((prev) => prev || Math.round(h));
  }, []);

  const snapPoints = useMemo<(string | number)[]>(() => {
    const first = headerH > 0 && handleH > 0
      ? headerH + handleH + PEEK_REVEAL
      : Math.round(SCREEN_H * 0.42);
    return [first, '100%'];
  }, [headerH, handleH]);

  const renderHandle = useCallback(() => (
    <View style={styles.handle} onLayout={onHandleLayout}>
      <View style={styles.grabber} />
    </View>
  ), [styles, onHandleLayout]);
  const handleClose = useCallback(() => modalRef.current?.dismiss(), []);

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
      {offering ? (
        <OfferingDetail offering={offering} inSheet onClose={handleClose} onHeaderMeasured={onHeaderMeasured} onOpenPro={onOpenPro} />
      ) : null}
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
      // Same thin lip border as the PP drawer.
      borderTopWidth: 1,
      borderLeftWidth: 1,
      borderRightWidth: 1,
      borderColor: colors.borderMuted,
    },
    grabber: { height: 4, width: 40, borderRadius: 2, backgroundColor: colors.textMuted },
  });
