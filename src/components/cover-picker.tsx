import { useMemo } from 'react';
import { View, Pressable, ScrollView, StyleSheet } from 'react-native';
import { Image } from 'expo-image';
import type { ImagePickerAsset } from 'expo-image-picker';
import { useTranslation } from 'react-i18next';
import { ImagePlus } from 'lucide-react-native';
import { AppText } from '@/components/app-text';
import { PressableScale } from '@/components/pressable-scale';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius, shadows } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { pickCoverAsset } from '@/utils/pro-photo-upload';

// What the pro did with the cover, applied by the screen on save.
export type CoverChange =
  | { kind: 'unchanged' }
  | { kind: 'asset'; asset: ImagePickerAsset }   // new picture from the phone
  | { kind: 'url'; url: string | null };          // a gallery photo, or null = removed

// Cover chosen by the pro (Scott 2026-10-31, mig 00562) — for the pro page and
// for each outing. No cover = no photo (the page shows its tint), never « the
// first photo ». A new picture, one of the pro's own photos, or none.
export function CoverPicker({ savedUrl, gallery, galleryHint, change, onChange }: {
  savedUrl: string | null;
  gallery: { id: string; photo_url: string }[];
  galleryHint: string;
  change: CoverChange;
  onChange: (c: CoverChange) => void;
}) {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);

  const shownUrl = change.kind === 'asset' ? change.asset.uri : change.kind === 'url' ? change.url : savedUrl;

  const pick = async () => {
    const asset = await pickCoverAsset();
    if (asset) onChange({ kind: 'asset', asset });
  };

  return (
    <View>
      <PressableScale style={styles.cover} onPress={pick} accessibilityRole="button"
        accessibilityLabel={t('proOffering.coverPick', { defaultValue: 'Choisir une photo' })}>
        {shownUrl ? (
          <>
            <Image source={{ uri: shownUrl }} style={StyleSheet.absoluteFill} contentFit="cover" />
            <View style={styles.changeChip}>
              <ImagePlus size={14} color={colors.textPrimary} strokeWidth={2.4} />
              <AppText style={styles.changeText}>{t('proOffering.coverChange', { defaultValue: 'Changer' })}</AppText>
            </View>
          </>
        ) : (
          <View style={styles.empty}>
            <ImagePlus size={26} color={colors.textSecondary} strokeWidth={2} />
            <AppText style={styles.emptyText}>{t('proOffering.coverAdd', { defaultValue: 'Ajouter une photo de couverture' })}</AppText>
          </View>
        )}
      </PressableScale>

      {shownUrl ? (
        <Pressable onPress={() => onChange({ kind: 'url', url: null })} hitSlop={6} style={styles.removeRow} accessibilityRole="button">
          <AppText style={styles.remove}>{t('proOffering.coverRemove', { defaultValue: 'Retirer la couverture' })}</AppText>
        </Pressable>
      ) : null}

      {gallery.length > 0 && (
        <>
          <AppText style={styles.helper}>{galleryHint}</AppText>
          <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.thumbs}>
            {gallery.map((p) => {
              const selected = change.kind !== 'asset' && shownUrl === p.photo_url;
              return (
                <Pressable key={p.id} onPress={() => onChange({ kind: 'url', url: p.photo_url })}
                  style={[styles.thumb, selected && styles.thumbOn]} accessibilityState={{ selected }}>
                  <Image source={{ uri: p.photo_url }} style={StyleSheet.absoluteFill} contentFit="cover" />
                </Pressable>
              );
            })}
          </ScrollView>
        </>
      )}
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  cover: {
    height: 170, borderRadius: radius.card, overflow: 'hidden',
    backgroundColor: colors.surfaceAlt, borderWidth: 1, borderColor: colors.lineStrong,
  },
  empty: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: spacing.xs },
  emptyText: { color: colors.textSecondary, fontSize: fontSizes.sm, fontWeight: '700' },
  changeChip: {
    position: 'absolute', right: spacing.sm, bottom: spacing.sm,
    flexDirection: 'row', alignItems: 'center', gap: 6,
    paddingHorizontal: spacing.sm + 2, paddingVertical: 6, borderRadius: radius.full,
    backgroundColor: colors.surface, ...shadows.card,
  },
  changeText: { color: colors.textPrimary, fontSize: fontSizes.xs, fontWeight: '700' },
  removeRow: { alignSelf: 'flex-end', paddingTop: spacing.xs + 2 },
  remove: { color: colors.textSecondary, fontSize: fontSizes.xs, fontWeight: '600' },
  helper: { color: colors.textMuted, fontSize: fontSizes.xs, marginTop: spacing.xs },
  thumbs: { gap: spacing.sm, paddingTop: spacing.xs + 2 },
  thumb: {
    width: 64, height: 64, borderRadius: radius.card - 6, overflow: 'hidden',
    borderWidth: 2, borderColor: 'transparent',
  },
  thumbOn: { borderColor: colors.cta },
});
