import { useMemo, useRef } from 'react';
import { View, StyleSheet } from 'react-native';
import BottomSheet from '@gorhom/bottom-sheet';
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
  const router = useRouter();
  const { session } = useAuth();

  const { data: pro } = useQuery({
    queryKey: ['pro-profile', userId],
    queryFn: () => proService.getById(userId),
  });

  const isOwner = !!pro && session?.user?.id === pro.user_id;

  return (
    <BottomSheet
      ref={sheetRef}
      index={0}
      animateOnMount
      snapPoints={['45%', '92%']}
      enablePanDownToClose
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
          onClose={() => sheetRef.current?.close()}
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
