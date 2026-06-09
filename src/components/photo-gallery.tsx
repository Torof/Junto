import { useMemo, useState } from 'react';
import {
  View,
  Text,
  Image,
  Pressable,
  StyleSheet,
  Dimensions,
} from 'react-native';
import { useTranslation } from 'react-i18next';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { PhotoLightbox } from './photo-lightbox';

interface GalleryPhoto {
  id: string;
  photo_url: string;
}

interface PhotoGalleryProps {
  photos: GalleryPhoto[];
  emptyText?: string;
}

const SCREEN = Dimensions.get('window');
const COLUMN_GAP = spacing.sm;
const SIDE_PADDING = spacing.md;
const TILE_SIZE = (SCREEN.width - SIDE_PADDING * 2 - COLUMN_GAP) / 2;

// Read-only gallery — 2-column square grid (Instagram-ish). Tap any
// tile to open the fullscreen pager (PhotoLightbox).
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
      <View style={styles.grid}>
        {photos.map((photo, i) => (
          <Pressable
            key={photo.id}
            style={styles.tile}
            onPress={() => setViewerIndex(i)}
            accessibilityRole="imagebutton"
            accessibilityLabel={t('photoGallery.openPhoto', {
              defaultValue: 'Ouvrir la photo {{n}}',
              n: i + 1,
            })}
          >
            <Image source={{ uri: photo.photo_url }} style={styles.tileImage} resizeMode="cover" />
          </Pressable>
        ))}
      </View>

      <PhotoLightbox photos={photos} index={viewerIndex} onIndexChange={setViewerIndex} />
    </>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  grid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: COLUMN_GAP,
    paddingHorizontal: SIDE_PADDING,
  },
  tile: {
    width: TILE_SIZE,
    height: TILE_SIZE,
    borderRadius: radius.md,
    overflow: 'hidden',
    borderWidth: 1,
    borderColor: colors.borderMuted,
    backgroundColor: colors.surface,
  },
  tileImage: { width: '100%', height: '100%' },
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
});
