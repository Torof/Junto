import { useMemo, useState, useEffect } from 'react';
import { View, Text, Pressable, StyleSheet, Modal, ScrollView, Alert, ActivityIndicator } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useTranslation } from 'react-i18next';
import { useQueryClient } from '@tanstack/react-query';
import { X } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { fontSizes, spacing, radius, shadows } from '@/constants/theme';
import { useSports } from '@/hooks/use-sports';
import { getSportIcon } from '@/constants/sport-icons';
import { LEVELS } from '@/types/activity-form';
import { userService } from '@/services/user-service';
import { getFriendlyError } from '@/utils/friendly-error';

// Own-profile editor for declared sports + levels (users.sports /
// levels_per_sport). One row per active sport with a 4-tier level selector;
// picking a level declares the sport, tapping the active tier again clears it.
// Save writes both columns in one update (whitelist trigger allows them).

const SHORT: Record<string, string> = {
  'débutant': 'Déb.',
  'intermédiaire': 'Inter.',
  'avancé': 'Avancé',
  'expert': 'Expert',
};

interface Props {
  visible: boolean;
  onClose: () => void;
  initialLevels: Record<string, string> | null;
}

export function SportLevelsEditor({ visible, onClose, initialLevels }: Props) {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { data: sports } = useSports();
  const queryClient = useQueryClient();
  const [levels, setLevels] = useState<Record<string, string>>({});
  const [saving, setSaving] = useState(false);

  // Re-seed from the current declared levels each time the sheet opens.
  useEffect(() => {
    if (visible) setLevels({ ...(initialLevels ?? {}) });
  }, [visible, initialLevels]);

  const pick = (key: string, level: string) => {
    setLevels((prev) => {
      const next = { ...prev };
      if (next[key] === level) delete next[key];
      else next[key] = level;
      return next;
    });
  };

  const handleSave = async () => {
    if (saving) return;
    setSaving(true);
    try {
      const sportsArr = Object.keys(levels);
      await userService.updateProfile({ sports: sportsArr, levels_per_sport: levels });
      await queryClient.invalidateQueries({ queryKey: ['currentUser'] });
      await queryClient.invalidateQueries({ queryKey: ['public-profile'] });
      onClose();
    } catch (err) {
      Alert.alert(t('auth.error'), getFriendlyError(err, 'generic'));
    } finally {
      setSaving(false);
    }
  };

  return (
    <Modal visible={visible} animationType="slide" transparent onRequestClose={onClose}>
      <View style={styles.backdrop}>
        <SafeAreaView style={styles.sheet} edges={['bottom']}>
          <View style={styles.header}>
            <Text style={styles.title}>{t('profil.sportsEditorTitle', { defaultValue: 'Mes sports' })}</Text>
            <Pressable onPress={onClose} hitSlop={8}>
              <X size={22} color={colors.textPrimary} strokeWidth={2.2} />
            </Pressable>
          </View>
          <Text style={styles.helper}>
            {t('profil.sportsEditorHelper', { defaultValue: 'Choisis ton niveau pour chaque sport que tu pratiques. Touche à nouveau pour retirer.' })}
          </Text>

          <ScrollView style={styles.list} contentContainerStyle={styles.listContent}>
            {(sports ?? []).map((s) => {
              const active = levels[s.key];
              return (
                <View key={s.key} style={styles.row}>
                  <View style={styles.rowHead}>
                    <Text style={styles.rowEmoji}>{getSportIcon(s.key)}</Text>
                    <Text style={[styles.rowName, active && styles.rowNameActive]} numberOfLines={1}>
                      {t(`sports.${s.key}`, { defaultValue: s.key })}
                    </Text>
                  </View>
                  <View style={styles.levelsRow}>
                    {LEVELS.map((lvl) => {
                      const on = active === lvl;
                      return (
                        <Pressable
                          key={lvl}
                          onPress={() => pick(s.key, lvl)}
                          style={[styles.levelChip, on && styles.levelChipOn]}
                        >
                          <Text style={[styles.levelChipText, on && styles.levelChipTextOn]}>{SHORT[lvl] ?? lvl}</Text>
                        </Pressable>
                      );
                    })}
                  </View>
                </View>
              );
            })}
          </ScrollView>

          <Pressable style={[styles.save, saving && styles.saveDisabled]} onPress={handleSave} disabled={saving}>
            {saving ? (
              <ActivityIndicator color="#FFFFFF" />
            ) : (
              <Text style={styles.saveText}>{t('common.save', { defaultValue: 'Enregistrer' })}</Text>
            )}
          </Pressable>
        </SafeAreaView>
      </View>
    </Modal>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  backdrop: { flex: 1, backgroundColor: 'rgba(0,0,0,0.35)', justifyContent: 'flex-end' },
  sheet: {
    backgroundColor: colors.surfaceAlt,
    borderTopLeftRadius: radius.xl,
    borderTopRightRadius: radius.xl,
    maxHeight: '86%',
    ...shadows.sheet,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.lg,
    paddingBottom: spacing.xs,
  },
  title: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: '900', letterSpacing: -0.02 },
  helper: { color: colors.textSecondary, fontSize: fontSizes.sm, paddingHorizontal: spacing.lg, marginBottom: spacing.sm },
  list: { flexGrow: 0 },
  listContent: { paddingHorizontal: spacing.lg, paddingBottom: spacing.md },
  row: { paddingVertical: spacing.sm, borderBottomWidth: 1, borderBottomColor: colors.borderMuted },
  rowHead: { flexDirection: 'row', alignItems: 'center', gap: 8, marginBottom: 8 },
  rowEmoji: { fontSize: 18 },
  rowName: { color: colors.textSecondary, fontSize: fontSizes.md, fontWeight: '600', flex: 1 },
  rowNameActive: { color: colors.textPrimary, fontWeight: '800' },
  levelsRow: { flexDirection: 'row', gap: 6 },
  levelChip: {
    flex: 1,
    alignItems: 'center',
    paddingVertical: 7,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.borderMuted,
    backgroundColor: colors.surface,
  },
  levelChipOn: { borderColor: colors.cta, backgroundColor: colors.cta + '18' },
  levelChipText: { color: colors.textSecondary, fontSize: fontSizes.xs, fontWeight: '700' },
  levelChipTextOn: { color: colors.cta },
  save: {
    margin: spacing.lg,
    marginTop: spacing.sm,
    backgroundColor: colors.cta,
    borderRadius: radius.lg,
    paddingVertical: spacing.md,
    alignItems: 'center',
  },
  saveDisabled: { opacity: 0.6 },
  saveText: { color: '#FFFFFF', fontSize: fontSizes.md, fontWeight: '800' },
});
