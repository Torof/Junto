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
// Scroll recipe (copied from ActivitiesBottomSheet, the one that works):
// enableContentPanningGesture={false} + enableDynamicSizing={false} + a
// fixed-height content container. With content-panning ON, gorhom eats the
// drag to move the sheet and the inner ScrollView never scrolls.
const SCREEN_H = Dimensions.get('window').height;
const SNAP_RATIOS = [0.45, 0.98];
const GRABBER_H = 28;

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
  const [snapIndex, setSnapIndex] = useState(0);

  const { data: pro } = useQuery({
    queryKey: ['pro-profile', userId],
    queryFn: () => proService.getById(userId),
  });

  const isOwner = !!pro && session?.user?.id === pro.user_id;

  // Content container height = the CURRENT snap's height in px, so the inner
  // ScrollView's viewport matches what's visible (its scroll math is right).
  const innerHeight = (SCREEN_H - insets.top) * (SNAP_RATIOS[snapIndex] ?? 0.98) - GRABBER_H;

  return (
    <BottomSheet
      ref={sheetRef}
      index={0}
      animateOnMount
      snapPoints={['45%', '98%']}
      topInset={insets.top}
      enablePanDownToClose
      enableDynamicSizing={false}
      enableContentPanningGesture={false}
      onChange={(i) => { if (i >= 0) setSnapIndex(i); }}
      onClose={onClose}
      backgroundStyle={styles.bg}
      handleIndicatorStyle={styles.grabber}
    >
      {pro ? (
        <ProDetail
          pro={pro}
          isOwner={isOwner}
          onEdit={isOwner ? () => router.push('/(auth)/pro/edit') : undefined}
          inSheet
          sheetHeight={innerHeight}
          onClose={() => sheetRef.current?.close()}
          onExpand={() => sheetRef.current?.snapToIndex(1)}
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
    grabber: { backgroundColor: colors.textMuted, width: 40 },
    loading: { paddingVertical: 80, alignItems: 'center' },
  });
