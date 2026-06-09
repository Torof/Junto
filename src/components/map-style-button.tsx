import { useMemo, useState } from 'react';
import { View, Text, Pressable, Modal, StyleSheet } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTranslation } from 'react-i18next';
import { Layers } from 'lucide-react-native';
import { spacing, radius, fontSizes } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { useMapStyleStore, MAP_STYLE_ORDER, type MapStyleKey } from '@/store/map-style-store';

// Positioned by the parent (carte.tsx) inside the top-left controls
// row. The modal panel still anchors near the button's real screen
// position via safeArea + the row's expected top offset.
export function MapStyleButton() {
  const { t } = useTranslation();
  const colors = useColors();
  const insets = useSafeAreaInsets();
  const styles = useMemo(() => createStyles(colors, insets.top), [colors, insets.top]);
  const [open, setOpen] = useState(false);
  const current = useMapStyleStore((s) => s.style);
  const setStyle = useMapStyleStore((s) => s.setStyle);

  return (
    <>
      <Pressable style={styles.button} onPress={() => setOpen(true)} hitSlop={8} accessibilityLabel={t('drawer.mapStyle')}>
        <Layers size={20} color={colors.textPrimary} strokeWidth={2.2} />
      </Pressable>

      <Modal visible={open} animationType="fade" transparent onRequestClose={() => setOpen(false)}>
        <Pressable style={styles.backdrop} onPress={() => setOpen(false)}>
          <Pressable style={styles.panel} onPress={() => {}}>
            <Text style={styles.panelTitle}>{t('drawer.mapStyle')}</Text>
            {MAP_STYLE_ORDER.map((key: MapStyleKey) => {
              const isActive = current === key;
              return (
                <Pressable
                  key={key}
                  style={[styles.chip, isActive && styles.chipActive]}
                  onPress={() => { setStyle(key); setOpen(false); }}
                >
                  <Text style={[styles.chipText, isActive && styles.chipTextActive]}>
                    {t(`drawer.mapStyleOption.${key}`)}
                  </Text>
                </Pressable>
              );
            })}
          </Pressable>
        </Pressable>
      </Modal>
    </>
  );
}

const createStyles = (colors: AppColors, safeTop: number) => StyleSheet.create({
  button: {
    backgroundColor: colors.surface,
    borderRadius: radius.full,
    width: 40,
    height: 40,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
    borderColor: colors.border,
    elevation: 4,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.15,
    shadowRadius: 4,
  },
  // The button is rendered inside the parent's absolutely-positioned
  // top-left row at top: spacing.md inside the content view (which
  // already sits below the SafeAreaView spacer). Modal coordinates
  // are screen-relative, so drop the panel just under the button:
  //   safeTop + row top offset + button height + small gap.
  backdrop: {
    flex: 1,
    backgroundColor: colors.overlay,
    paddingTop: safeTop + spacing.md + 40 + spacing.xs,
    paddingLeft: spacing.md + 40 + spacing.sm,
    alignItems: 'flex-start',
  },
  panel: {
    backgroundColor: colors.surface,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.line,
    paddingVertical: spacing.xs + 2,
    paddingHorizontal: spacing.xs,
    minWidth: 180,
    elevation: 8,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.3,
    shadowRadius: 8,
  },
  panelTitle: {
    color: colors.textMuted,
    fontSize: 10,
    fontWeight: '700',
    letterSpacing: 1.2,
    textTransform: 'uppercase',
    paddingHorizontal: spacing.sm,
    paddingVertical: spacing.xs,
  },
  chip: {
    paddingHorizontal: spacing.sm,
    paddingVertical: spacing.xs + 2,
    borderRadius: radius.sm,
  },
  chipActive: {
    backgroundColor: colors.cta + '26',
  },
  chipText: {
    color: colors.textPrimary,
    fontSize: fontSizes.sm,
    fontWeight: '500',
  },
  chipTextActive: {
    color: colors.cta,
    fontWeight: '700',
  },
});
