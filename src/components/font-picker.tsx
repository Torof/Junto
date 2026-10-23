import { useEffect, useMemo, useState } from 'react';
// RNText: the one place a family is set by hand (each row shows its own).
// eslint-disable-next-line no-restricted-imports
import { View, Pressable, StyleSheet, Text as RNText, type StyleProp, type TextStyle } from 'react-native';
import { useTranslation } from 'react-i18next';
import * as Font from 'expo-font';
import * as Burnt from 'burnt';
import { Check } from 'lucide-react-native';
import { spacing, fontSizes } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { useFontStore } from '@/store/font-store';
import { AppText } from '@/components/app-text';
import { DEFAULT_FONT_FAMILY, FONT_FAMILY_IDS, fontFamilyLabel, fontFileMap, fontFileName, type FontFamilyId } from '@/constants/font-families';

// The font list: each name is drawn in its own family (only the 700 file of
// each is loaded for the preview; the full family loads when chosen).
export function FontPicker() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const family = useFontStore((s) => s.family);
  const setFamily = useFontStore((s) => s.setFamily);
  const [previews, setPreviews] = useState(false);
  const [pending, setPending] = useState<FontFamilyId | null>(null);

  useEffect(() => {
    let alive = true;
    const map: Record<string, number> = {};
    for (const id of FONT_FAMILY_IDS) if (id !== 'system') Object.assign(map, fontFileMap(id, ['700']));
    Font.loadAsync(map)
      .then(() => { if (alive) setPreviews(true); })
      .catch(() => {});
    return () => { alive = false; };
  }, []);

  const choose = async (id: FontFamilyId) => {
    if (id === family || pending) return;
    setPending(id);
    const ok = await setFamily(id);
    setPending(null);
    if (!ok) Burnt.toast({ title: t('drawer.fontLoadError'), preset: 'error' });
  };

  return (
    <View style={styles.list}>
      {FONT_FAMILY_IDS.map((id) => {
        const active = id === family;
        const label = id === 'system' ? t('drawer.fontOption.system') : fontFamilyLabel(id);
        const nameStyle = id !== 'system' && previews ? { fontFamily: fontFileName(id, '700') } : { fontWeight: '700' as const };
        return (
          <Pressable
            key={id}
            onPress={() => choose(id)}
            style={styles.row}
            accessibilityRole="button"
            accessibilityState={{ selected: active }}
          >
            <View style={styles.nameCol}>
              <PreviewName style={[styles.name, nameStyle]} label={label} />
              {id === DEFAULT_FONT_FAMILY && <AppText style={styles.hint}>{t('drawer.fontDefault')}</AppText>}
            </View>
            {(active || pending === id) && <Check size={18} color={pending === id ? colors.textMuted : colors.cta} strokeWidth={2.6} />}
          </Pressable>
        );
      })}
    </View>
  );
}

function PreviewName({ style, label }: { style: StyleProp<TextStyle>; label: string }) {
  return <RNText style={style} numberOfLines={1}>{label}</RNText>;
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  list: {
    paddingLeft: spacing.lg,
    paddingBottom: spacing.sm,
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: spacing.sm,
    gap: spacing.sm,
  },
  nameCol: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'baseline',
    gap: spacing.sm,
  },
  name: {
    color: colors.textPrimary,
    fontSize: fontSizes.md + 1,
  },
  hint: {
    color: colors.textSecondary,
    fontSize: fontSizes.xs,
    fontWeight: '500',
  },
});
