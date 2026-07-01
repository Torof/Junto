import { useMemo, useRef, useState } from 'react';
import { View, StyleSheet, Dimensions, type LayoutChangeEvent } from 'react-native';
import BottomSheet from '@gorhom/bottom-sheet';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useQuery } from '@tanstack/react-query';
import { useRouter } from 'expo-router';
import { useColors } from '@/hooks/use-theme';
import { type AppColors } from '@/constants/colors';
import { radius } from '@/constants/theme';
import { useAuth } from '@/hooks/use-auth';
import { proService } from '@/services/pro-service';
import { ProDetail, type ProTab } from './pro-detail';
import { LogoSpinner } from './logo-spinner';

// PP (pro page) as a Google-style expandable drawer over the map — hosts the
// full ProDetail (tabs, contact, catalogue, avis) inside a gorhom sheet
// instead of a full-screen route. The /pro/[id] route stays for deep links.
//
// Drag/scroll split: header + carousel + tab bar are gorhom's custom
// handleComponent (the drag grip), so a pull from anywhere in that block drags
// the sheet — and a continuous pull runs straight to the top snap in one
// motion. The tab content is the sheet body: content-panning is off, so with a
// fixed-height container the inner ScrollView scrolls without dragging the
// sheet. bodyHeight = snap height − measured handle height.
const SCREEN_H = Dimensions.get('window').height;
const SNAP_RATIOS = [0.45, 0.98];

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
  const [handleH, setHandleH] = useState(0);
  // Active tab is lifted here so the handle (tab bar) and the body (tab
  // content) — two ProDetail instances — stay in sync.
  const [activeTab, setActiveTab] = useState<ProTab>('info');

  const { data: pro } = useQuery({
    queryKey: ['pro-profile', userId],
    queryFn: () => proService.getById(userId),
  });

  const isOwner = !!pro && session?.user?.id === pro.user_id;
  const onEdit = isOwner ? () => router.push('/(auth)/pro/edit') : undefined;

  const onHandleLayout = (e: LayoutChangeEvent) => setHandleH(e.nativeEvent.layout.height);

  // Body height = the current snap's px height minus the always-visible handle,
  // so the inner ScrollView's viewport matches the space below the tab bar.
  const snapPx = (SCREEN_H - insets.top) * (SNAP_RATIOS[snapIndex] ?? 0.98);
  const bodyHeight = Math.max(0, snapPx - handleH);

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
      handleComponent={() => (
        <View style={styles.handle} onLayout={onHandleLayout}>
          <View style={styles.grabberWrap}>
            <View style={styles.grabber} />
          </View>
          {pro ? (
            <ProDetail
              pro={pro}
              isOwner={isOwner}
              onEdit={onEdit}
              inSheet
              renderPart="handle"
              activeTab={activeTab}
              onSelectTab={setActiveTab}
              onClose={() => sheetRef.current?.close()}
              onExpand={() => sheetRef.current?.snapToIndex(1)}
            />
          ) : null}
        </View>
      )}
    >
      {pro ? (
        <ProDetail
          pro={pro}
          isOwner={isOwner}
          onEdit={onEdit}
          inSheet
          renderPart="body"
          sheetHeight={bodyHeight}
          activeTab={activeTab}
          onSelectTab={setActiveTab}
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
    handle: {
      backgroundColor: colors.background,
      borderTopLeftRadius: radius.xl,
      borderTopRightRadius: radius.xl,
      overflow: 'hidden',
    },
    grabberWrap: { alignItems: 'center', paddingTop: 10, paddingBottom: 6 },
    grabber: { height: 4, width: 40, borderRadius: 2, backgroundColor: colors.textMuted },
    loading: { paddingVertical: 80, alignItems: 'center' },
  });
