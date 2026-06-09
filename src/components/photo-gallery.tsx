import { useMemo, useState } from 'react';
import {
  View,
  Text,
  Image,
  Pressable,
  FlatList,
  Modal,
  StyleSheet,
  Dimensions,
  StatusBar,
} from 'react-native';
import { useTranslation } from 'react-i18next';
import { X } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { fontSizes, spacing, radius } from '@/constants/theme';

interface GalleryPhoto {
  id: string;
  photo_url: string;
}

interface PhotoGalleryProps {
  photos: GalleryPhoto[];
  // Optional empty-state copy override per surface (pro page vs offering).
  emptyText?: string;
}

const THUMB_WIDTH = 220;
const THUMB_ASPECT = 4 / 3;
const SCREEN = Dimensions.get('window');

// Read-only photo gallery — horizontal carousel of curated thumbs, tap
// any thumb to open the full-screen pager. Order honors the photo's
// order_index so the pro's curation reads as intended (first = hero).
export function PhotoGallery({ photos, emptyText }: PhotoGalleryProps) {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const [viewerIndex, setViewerIndex] = useState<number | null>(null);

  if (photos.length === 0) {
    return (
      <View style={styles.empty}>
        <Text style={styles.emptyText}>
          {emptyText ?? t('photoGallery.empty', { defaultValue: 'Aucune photo pour le moment.' })}
        </Text>
      </View>
    );
  }

  return (
    <>
      <FlatList
        data={photos}
        keyExtractor={(p) => p.id}
        horizontal
        showsHorizontalScrollIndicator={false}
        contentContainerStyle={styles.carousel}
        renderItem={({ item, index }) => (
          <Pressable
            style={styles.thumb}
            onPress={() => setViewerIndex(index)}
            accessibilityRole="imagebutton"
            accessibilityLabel={t('photoGallery.openPhoto', {
              defaultValue: 'Ouvrir la photo {{n}}',
              n: index + 1,
            })}
          >
            <Image source={{ uri: item.photo_url }} style={styles.thumbImage} resizeMode="cover" />
          </Pressable>
        )}
      />

      <Modal
        visible={viewerIndex !== null}
        transparent
        animationType="fade"
        onRequestClose={() => setViewerIndex(null)}
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
            initialScrollIndex={viewerIndex ?? 0}
            getItemLayout={(_, index) => ({
              length: SCREEN.width,
              offset: SCREEN.width * index,
              index,
            })}
            onMomentumScrollEnd={(e) => {
              const i = Math.round(e.nativeEvent.contentOffset.x / SCREEN.width);
              setViewerIndex(i);
            }}
            renderItem={({ item }) => (
              <Pressable
                style={styles.viewerPage}
                onPress={() => setViewerIndex(null)}
              >
                <Image
                  source={{ uri: item.photo_url }}
                  style={styles.viewerImage}
                  resizeMode="contain"
                />
              </Pressable>
            )}
          />

          <Pressable
            style={styles.viewerClose}
            onPress={() => setViewerIndex(null)}
            hitSlop={10}
            accessibilityLabel={t('common.close', { defaultValue: 'Fermer' })}
          >
            <X size={24} color="#FFFFFF" strokeWidth={2.6} />
          </Pressable>

          {photos.length > 1 && viewerIndex !== null && (
            <View style={styles.viewerCounter} pointerEvents="none">
              <Text style={styles.viewerCounterText}>
                {viewerIndex + 1} / {photos.length}
              </Text>
            </View>
          )}
        </View>
      </Modal>
    </>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  carousel: {
    paddingHorizontal: spacing.md,
    gap: spacing.sm + 2,
  },
  thumb: {
    width: THUMB_WIDTH,
    aspectRatio: THUMB_ASPECT,
    borderRadius: radius.md,
    overflow: 'hidden',
    borderWidth: 1,
    borderColor: colors.borderMuted,
    backgroundColor: colors.surface,
  },
  thumbImage: { width: '100%', height: '100%' },
  empty: {
    marginHorizontal: spacing.md,
    padding: spacing.md,
    borderWidth: 1,
    borderColor: colors.borderMuted,
    borderRadius: radius.md,
  },
  emptyText: {
    color: colors.textMuted,
    fontSize: fontSizes.sm,
    fontStyle: 'italic',
  },
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
