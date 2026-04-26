import { useMemo, useState } from 'react';
import { View, Text, Pressable, Modal, StyleSheet } from 'react-native';
import { useTranslation } from 'react-i18next';
import { Layers } from 'lucide-react-native';
import { spacing, radius, fontSizes } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { useMapStyleStore, MAP_STYLE_ORDER, type MapStyleKey } from '@/store/map-style-store';

export function MapStyleButton() {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const [open, setOpen] = useState(false);
  const current = useMapStyleStore((s) => s.style);
  const setStyle = useMapStyleStore((s) => s.setStyle);

  return (
    <>
      <Pressable style={styles.button} onPress={() => setOpen(true)} hitSlop={8} accessibilityLabel={t('drawer.mapStyle')}>
        <Layers size={22} color={colors.textPrimary} strokeWidth={2.2} />
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

const createStyles = (colors: AppColors) => StyleSheet.create({
  button: {
    position: 'absolute',
    bottom: 170,
    right: spacing.md,
    backgroundColor: colors.surface,
    borderRadius: radius.full,
    width: 40,
    height: 40,
    alignItems: 'center',
    justifyContent: 'center',
    zIndex: 10,
    borderWidth: 1,
    borderColor: colors.border,
  },
  backdrop: {
    flex: 1,
    backgroundColor: colors.overlay,
    alignItems: 'flex-end',
    justifyContent: 'flex-end',
    paddingRight: spacing.md + 50,
    paddingBottom: 170,
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
