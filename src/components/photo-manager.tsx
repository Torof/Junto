import { useMemo, useState } from 'react';
import {
  View,
  Text,
  Pressable,
  Alert,
  StyleSheet,
  Dimensions,
} from 'react-native';
import { Image } from 'expo-image';
import { useTranslation } from 'react-i18next';
import { ImagePlus, Trash2, ChevronUp, ChevronDown } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { LogoSpinner } from './logo-spinner';
import { PhotoLightbox } from './photo-lightbox';

interface ManagedPhoto {
  id: string;
  photo_url: string;
}

interface PhotoManagerProps {
  photos: ManagedPhoto[];
  maxCount: number;
  // Parent wires these to the appropriate service. PhotoManager itself
  // is surface-agnostic so the same component drives the pro page and
  // each offering's gallery.
  onAdd: () => Promise<void>;
  onRemove: (photoId: string) => Promise<void>;
  onReorder: (orderedIds: string[]) => Promise<void>;
  // Optional copy override for the empty-state CTA.
  emptyCta?: string;
}

const SCREEN = Dimensions.get('window');
const COLUMN_GAP = spacing.sm;
const SIDE_PADDING = spacing.md;
const TILE_WIDTH = (SCREEN.width - SIDE_PADDING * 2 - COLUMN_GAP) / 2;

// Owner-only gallery editor. Two-column grid of square tiles; per-tile
// controls for delete + up/down reorder. Drag-to-reorder is V2 — the
// arrows are simple, accessible, and don't need a gesture system.
export function PhotoManager({
  photos,
  maxCount,
  onAdd,
  onRemove,
  onReorder,
  emptyCta,
}: PhotoManagerProps) {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const [busy, setBusy] = useState(false);
  const [viewerIndex, setViewerIndex] = useState<number | null>(null);

  const remaining = Math.max(0, maxCount - photos.length);
  const canAdd = remaining > 0;

  const handleAdd = async () => {
    if (busy || !canAdd) return;
    setBusy(true);
    try {
      await onAdd();
    } finally {
      setBusy(false);
    }
  };

  const handleRemove = (photoId: string) => {
    if (busy) return;
    Alert.alert(
      t('photoManager.removeTitle', { defaultValue: 'Supprimer la photo ?' }),
      t('photoManager.removeBody', { defaultValue: 'Cette action est définitive.' }),
      [
        { text: t('common.cancel', { defaultValue: 'Annuler' }), style: 'cancel' },
        {
          text: t('common.delete', { defaultValue: 'Supprimer' }),
          style: 'destructive',
          onPress: async () => {
            setBusy(true);
            try {
              await onRemove(photoId);
            } finally {
              setBusy(false);
            }
          },
        },
      ],
    );
  };

  const handleSwap = async (index: number, direction: -1 | 1) => {
    if (busy) return;
    const target = index + direction;
    if (target < 0 || target >= photos.length) return;
    const reordered = [...photos];
    const a = reordered[index]!;
    const b = reordered[target]!;
    reordered[index] = b;
    reordered[target] = a;
    setBusy(true);
    try {
      await onReorder(reordered.map((p) => p.id));
    } finally {
      setBusy(false);
    }
  };

  return (
    <View style={styles.container}>
      {/* Header row — count + add button. Always visible so the user
          always knows how many slots remain. */}
      <View style={styles.header}>
        <Text style={styles.countText}>
          {t('photoManager.count', {
            defaultValue: '{{n}} / {{max}} photos',
            n: photos.length,
            max: maxCount,
          })}
        </Text>
        <Pressable
          style={[styles.addBtn, !canAdd && styles.addBtnDisabled]}
          onPress={handleAdd}
          disabled={!canAdd || busy}
        >
          {busy && photos.length === 0 ? (
            <LogoSpinner size={16} />
          ) : (
            <>
              <ImagePlus size={14} color={colors.cta} strokeWidth={2.4} />
              <Text style={styles.addBtnText}>
                {t('photoManager.add', { defaultValue: 'Ajouter' })}
              </Text>
            </>
          )}
        </Pressable>
      </View>

      {photos.length === 0 ? (
        <Pressable
          style={styles.emptyCard}
          onPress={handleAdd}
          disabled={busy}
        >
          <ImagePlus size={28} color={colors.textSecondary} strokeWidth={2.2} />
          <Text style={styles.emptyText}>
            {emptyCta ?? t('photoManager.emptyCta', { defaultValue: 'Tape pour ajouter tes premières photos.' })}
          </Text>
        </Pressable>
      ) : (
        <View style={styles.grid}>
          {photos.map((photo, index) => (
            <View key={photo.id} style={styles.tile}>
              {/* Tap the photo itself (anywhere except the corner
                  controls) to open the fullscreen viewer. The corner
                  Pressables are absolutely positioned above this one
                  so their own taps don't bubble through. */}
              <Pressable
                style={StyleSheet.absoluteFill}
                onPress={() => setViewerIndex(index)}
                disabled={busy}
                accessibilityRole="imagebutton"
                accessibilityLabel={t('photoGallery.openPhoto', {
                  defaultValue: 'Ouvrir la photo {{n}}',
                  n: index + 1,
                })}
              >
                <Image source={{ uri: photo.photo_url }} style={styles.tileImage} contentFit="cover" />
              </Pressable>

              {/* Position chip — top-left. Makes the order explicit so
                  the user knows what they're rearranging. */}
              <View style={styles.positionChip} pointerEvents="none">
                <Text style={styles.positionText}>{index + 1}</Text>
              </View>

              {/* Delete — top-right, with confirm. */}
              <Pressable
                style={styles.deleteBtn}
                onPress={() => handleRemove(photo.id)}
                disabled={busy}
                hitSlop={6}
              >
                <Trash2 size={14} color="#FFFFFF" strokeWidth={2.6} />
              </Pressable>

              {/* Reorder arrows — bottom-right. Disabled at the edges so
                  the user can see they're at the boundary. */}
              <View style={styles.reorderRow}>
                <Pressable
                  style={[styles.reorderBtn, index === 0 && styles.reorderBtnDisabled]}
                  onPress={() => handleSwap(index, -1)}
                  disabled={busy || index === 0}
                  hitSlop={4}
                >
                  <ChevronUp size={14} color="#FFFFFF" strokeWidth={2.6} />
                </Pressable>
                <Pressable
                  style={[styles.reorderBtn, index === photos.length - 1 && styles.reorderBtnDisabled]}
                  onPress={() => handleSwap(index, 1)}
                  disabled={busy || index === photos.length - 1}
                  hitSlop={4}
                >
                  <ChevronDown size={14} color="#FFFFFF" strokeWidth={2.6} />
                </Pressable>
              </View>

              {busy && (
                <View style={styles.tileOverlay} pointerEvents="none">
                  <LogoSpinner size={20} />
                </View>
              )}
            </View>
          ))}
        </View>
      )}

      <PhotoLightbox photos={photos} index={viewerIndex} onIndexChange={setViewerIndex} />

      <Text style={styles.helper}>
        {t('photoManager.helper', {
          defaultValue: 'La première photo sert d\'image principale.',
        })}
      </Text>
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  // Own its horizontal padding so the tile-width math stays correct
  // regardless of how the parent wraps it.
  container: { gap: spacing.sm, paddingHorizontal: SIDE_PADDING },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: spacing.sm,
  },
  countText: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    fontWeight: '700',
    textTransform: 'uppercase',
    letterSpacing: 0.6,
  },
  addBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    borderWidth: 1,
    borderColor: colors.borderMuted,
    borderRadius: radius.sm,
    paddingHorizontal: spacing.sm + 2,
    paddingVertical: 6,
  },
  addBtnDisabled: { opacity: 0.4 },
  addBtnText: {
    color: colors.cta,
    fontSize: fontSizes.xs,
    fontWeight: '700',
    textTransform: 'uppercase',
    letterSpacing: 0.6,
  },
  emptyCard: {
    aspectRatio: 2,
    borderWidth: 1,
    borderColor: colors.borderMuted,
    borderRadius: radius.md,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
    backgroundColor: colors.surface,
  },
  emptyText: {
    color: colors.textSecondary,
    fontSize: fontSizes.sm,
    fontWeight: '600',
    paddingHorizontal: spacing.md,
    textAlign: 'center',
  },
  grid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: COLUMN_GAP,
  },
  tile: {
    width: TILE_WIDTH,
    height: TILE_WIDTH,
    borderRadius: radius.md,
    overflow: 'hidden',
    borderWidth: 1,
    borderColor: colors.borderMuted,
    backgroundColor: colors.surface,
    position: 'relative',
  },
  tileImage: { width: '100%', height: '100%' },
  positionChip: {
    position: 'absolute',
    top: 6,
    left: 6,
    backgroundColor: 'rgba(0,0,0,0.65)',
    minWidth: 22,
    height: 22,
    paddingHorizontal: 6,
    borderRadius: 11,
    alignItems: 'center',
    justifyContent: 'center',
  },
  positionText: {
    color: '#FFFFFF',
    fontSize: fontSizes.xs,
    fontWeight: '800',
  },
  deleteBtn: {
    position: 'absolute',
    top: 6,
    right: 6,
    width: 26,
    height: 26,
    borderRadius: 13,
    backgroundColor: 'rgba(0,0,0,0.65)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  reorderRow: {
    position: 'absolute',
    bottom: 6,
    right: 6,
    flexDirection: 'row',
    gap: 4,
  },
  reorderBtn: {
    width: 26,
    height: 26,
    borderRadius: 13,
    backgroundColor: 'rgba(0,0,0,0.65)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  reorderBtnDisabled: { opacity: 0.3 },
  tileOverlay: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    backgroundColor: 'rgba(0,0,0,0.45)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  helper: {
    color: colors.textMuted,
    fontSize: fontSizes.xs,
    marginTop: 4,
  },
});
