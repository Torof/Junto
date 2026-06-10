import { View, Text, Pressable, FlatList, Modal, StyleSheet, Dimensions, StatusBar } from 'react-native';
import { Image } from 'expo-image';
import { useTranslation } from 'react-i18next';
import { X } from 'lucide-react-native';
import { fontSizes, spacing } from '@/constants/theme';

interface LightboxPhoto {
  id: string;
  photo_url: string;
}

interface PhotoLightboxProps {
  photos: LightboxPhoto[];
  index: number | null;
  onIndexChange: (i: number | null) => void;
}

const SCREEN = Dimensions.get('window');

// Fullscreen photo viewer used by both PhotoGallery (read-only) and
// PhotoManager (owner). Horizontal pager, tap-anywhere to close,
// '3 / 12' counter at the bottom. Index is owned by the caller so the
// viewer is fully controlled.
export function PhotoLightbox({ photos, index, onIndexChange }: PhotoLightboxProps) {
  const { t } = useTranslation();

  return (
    <Modal
      visible={index !== null}
      transparent
      animationType="fade"
      onRequestClose={() => onIndexChange(null)}
      statusBarTranslucent
    >
      <StatusBar barStyle="light-content" />
      <View style={styles.viewer}>
        <FlatList
          data={photos}
          keyExtractor={(p) => p.id}
          horizontal
          pagingEnabled
          showsHorizontalScrollIndicator={false}
          initialScrollIndex={index ?? 0}
          getItemLayout={(_, i) => ({
            length: SCREEN.width,
            offset: SCREEN.width * i,
            index: i,
          })}
          onMomentumScrollEnd={(e) => {
            const i = Math.round(e.nativeEvent.contentOffset.x / SCREEN.width);
            onIndexChange(i);
          }}
          renderItem={({ item }) => (
            <Pressable style={styles.viewerPage} onPress={() => onIndexChange(null)}>
              <Image source={{ uri: item.photo_url }} style={styles.viewerImage} contentFit="contain" />
            </Pressable>
          )}
        />

        <Pressable
          style={styles.viewerClose}
          onPress={() => onIndexChange(null)}
          hitSlop={10}
          accessibilityLabel={t('common.close', { defaultValue: 'Fermer' })}
        >
          <X size={24} color="#FFFFFF" strokeWidth={2.6} />
        </Pressable>

        {photos.length > 1 && index !== null && (
          <View style={styles.viewerCounter} pointerEvents="none">
            <Text style={styles.viewerCounterText}>
              {index + 1} / {photos.length}
            </Text>
          </View>
        )}
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  viewer: {
    flex: 1,
    backgroundColor: '#000000',
  },
  viewerPage: {
    width: SCREEN.width,
    height: SCREEN.height,
    alignItems: 'center',
    justifyContent: 'center',
  },
  viewerImage: { width: SCREEN.width, height: SCREEN.height },
  viewerClose: {
    position: 'absolute',
    top: spacing.xl,
    right: spacing.md,
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: 'rgba(0,0,0,0.55)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  viewerCounter: {
    position: 'absolute',
    bottom: spacing.xl + 16,
    alignSelf: 'center',
    backgroundColor: 'rgba(0,0,0,0.55)',
    paddingHorizontal: spacing.md,
    paddingVertical: 6,
    borderRadius: 999,
  },
  viewerCounterText: {
    color: '#FFFFFF',
    fontSize: fontSizes.sm,
    fontWeight: '700',
    letterSpacing: 0.4,
  },
});
