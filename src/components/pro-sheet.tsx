import { useMemo, useRef, useState } from 'react';
import { View, StyleSheet, Dimensions } from 'react-native';
import BottomSheet from '@gorhom/bottom-sheet';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useQuery } from '@tanstack/react-query';
import { useRouter } from 'expo-router';
import { useColors } from '@/hooks/use-theme';
import { type AppColors } from '@/constants/colors';
import { radius } from '@/constants/theme';
import { useAuth } from '@/hooks/use-auth';
import { proService } from '@/services/pro-service';
import { ProDetail } from './pro-detail';
import { LogoSpinner } from './logo-spinner';

// PP (pro page) as a Google-style expandable drawer over the map — hosts the
// full ProDetail (tabs, contact, catalogue, avis) inside a gorhom sheet
// instead of a full-screen route. The /pro/[id] route stays for deep links.
//
// Collapsing place-sheet: content-panning is ON and ProDetail renders a
// BottomSheetScrollView, so gorhom coordinates drag ↔ scroll — at the top of
// the list a pull drags the sheet to full height in one motion; once expanded,
// scrolling slides the header + carousel away and pins the tab bar to the top.
//
// The first snap point sits right at the header's divider (name · actions),
// measured at runtime (handle + header height) so the collapsed peek shows the
// identity + action buttons and nothing more.
const SCREEN_H = Dimensions.get('window').height;

interface Props {
  // Mounted only while a pro is selected, so the sheet reliably opens on mount
  // (animateOnMount) rather than via a race-prone imperative snap.
  userId: string;
  onClose: () => void;
}

export function ProSheet({ userId, onClose }: Props) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const sheetRef = useRef<BottomSheet>(null);
  const insets = useSafeAreaInsets();
  const router = useRouter();
  const { session } = useAuth();
  const [headerH, setHeaderH] = useState(0);
  const [handleH, setHandleH] = useState(0);

  const { data: pro } = useQuery({
    queryKey: ['pro-profile', userId],
    queryFn: () => proService.getById(userId),
  });

  const isOwner = !!pro && session?.user?.id === pro.user_id;

  // First snap = handle + header (through the divider), in px, so the collapsed
  // peek stops right below the action buttons. Falls back to a close estimate
  // until both are measured (avoids a visible settle on open).
  const snapPoints = useMemo<(string | number)[]>(() => {
    const first = headerH > 0 && handleH > 0
      ? Math.round(headerH + handleH)
      : Math.round(SCREEN_H * 0.34);
    return [first, '98%'];
  }, [headerH, handleH]);

  return (
    <BottomSheet
      ref={sheetRef}
      index={0}
      animateOnMount
      snapPoints={snapPoints}
      topInset={insets.top}
      enablePanDownToClose
      enableDynamicSizing={false}
      onClose={onClose}
      backgroundStyle={styles.bg}
      handleComponent={() => (
        <View style={styles.handle} onLayout={(e) => setHandleH(e.nativeEvent.layout.height)}>
          <View style={styles.grabber} />
        </View>
      )}
    >
      {pro ? (
        <ProDetail
          pro={pro}
          isOwner={isOwner}
          onEdit={isOwner ? () => router.push('/(auth)/pro/edit') : undefined}
          inSheet
          onClose={() => sheetRef.current?.close()}
          onExpand={() => sheetRef.current?.snapToIndex(1)}
          onHeaderMeasured={setHeaderH}
        />
      ) : (
        <View style={styles.loading}>
          <LogoSpinner size={40} />
        </View>
      )}
    </BottomSheet>
  );
}

const createStyles = (colors: AppColors) =>
  StyleSheet.create({
    bg: {
      backgroundColor: colors.background,
      borderTopLeftRadius: radius.xl,
      borderTopRightRadius: radius.xl,
    },
    handle: {
      alignItems: 'center',
      paddingTop: 10,
      paddingBottom: 6,
      backgroundColor: colors.background,
      borderTopLeftRadius: radius.xl,
      borderTopRightRadius: radius.xl,
    },
    grabber: { height: 4, width: 40, borderRadius: 2, backgroundColor: colors.textMuted },
    loading: { paddingVertical: 80, alignItems: 'center' },
  });
