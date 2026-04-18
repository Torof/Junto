import { useState, useEffect } from 'react';
import { View, Text, Pressable, ScrollView, Modal, StyleSheet } from 'react-native';
import { useTranslation } from 'react-i18next';
import { colors, fontSizes, spacing, radius } from '@/constants/theme';
import { SportDropdown } from './sport-dropdown';
import { getSportIcon } from '@/constants/sport-icons';
import { LEVELS } from '@/types/activity-form';

interface Props {
  visible: boolean;
  sports: string[];
  levelsPerSport: Record<string, string>;
  onSave: (sports: string[], levelsPerSport: Record<string, string>) => void;
  onClose: () => void;
  isSaving: boolean;
}

export function SportsLevelEditor({ visible, sports, levelsPerSport, onSave, onClose, isSaving }: Props) {
  const { t } = useTranslation();
  const [selectedSports, setSelectedSports] = useState<string[]>(sports);
  const [levels, setLevels] = useState<Record<string, string>>(levelsPerSport);

  useEffect(() => {
    if (visible) {
      setSelectedSports([...sports]);
      setLevels({ ...levelsPerSport });
    }
  }, [visible]);

  const toggleSport = (key: string) => {
    setSelectedSports((prev) => {
      if (prev.includes(key)) {
        const next = prev.filter((k) => k !== key);
        setLevels((l) => {
          const copy = { ...l };
          delete copy[key];
          return copy;
        });
        return next;
      }
      return [...prev, key];
    });
  };

  const setLevel = (sportKey: string, level: string) => {
    setLevels((prev) => ({ ...prev, [sportKey]: level }));
  };

  return (
    <Modal visible={visible} animationType="slide" transparent>
      <Pressable style={styles.backdrop} onPress={onClose}>
        <Pressable style={styles.sheet} onPress={() => {}}>
          <View style={styles.handle} />
          <Text style={styles.title}>{t('profil.sportsSection')}</Text>

          <SportDropdown
            selected={selectedSports}
            onSelect={toggleSport}
            multiSelect
            label={t('profil.addSport')}
          />

          <ScrollView style={styles.list} showsVerticalScrollIndicator={false}>
            {selectedSports.map((key) => (
              <View key={key} style={styles.sportRow}>
                <View style={styles.sportHeader}>
                  <Text style={styles.sportIcon}>{getSportIcon(key)}</Text>
                  <Text style={styles.sportName}>{t(`sports.${key}`, key)}</Text>
                </View>
                <View style={styles.levelChips}>
                  {LEVELS.map((level) => (
                    <Pressable
                      key={level}
                      style={[styles.chip, levels[key] === level && styles.chipActive]}
                      onPress={() => setLevel(key, level)}
                    >
                      <Text style={[styles.chipText, levels[key] === level && styles.chipTextActive]}>
                        {level}
                      </Text>
                    </Pressable>
                  ))}
                </View>
              </View>
            ))}
          </ScrollView>

          <Pressable
            style={[styles.saveButton, isSaving && styles.saveDisabled]}
            onPress={() => onSave(selectedSports, levels)}
            disabled={isSaving}
          >
            <Text style={styles.saveText}>{isSaving ? '...' : t('profil.save')}</Text>
          </Pressable>
        </Pressable>
      </Pressable>
    </Modal>
  );
}

const styles = StyleSheet.create({
  backdrop: { flex: 1, backgroundColor: colors.overlay, justifyContent: 'flex-end' },
  sheet: {
    backgroundColor: colors.background,
    borderTopLeftRadius: radius.lg,
    borderTopRightRadius: radius.lg,
    padding: spacing.lg,
    paddingBottom: spacing.xl + 16,
    maxHeight: '85%',
  },
  handle: { width: 40, height: 4, borderRadius: 2, backgroundColor: colors.textSecondary, alignSelf: 'center', marginBottom: spacing.lg, opacity: 0.4 },
  title: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: 'bold', marginBottom: spacing.md },
  list: { marginTop: spacing.md, maxHeight: 400 },
  sportRow: { marginBottom: spacing.md },
  sportHeader: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, marginBottom: spacing.xs },
  sportIcon: { fontSize: 20 },
  sportName: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '600', textTransform: 'capitalize' },
  levelChips: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.xs },
  chip: {
    backgroundColor: colors.surface,
    borderRadius: radius.full,
    paddingHorizontal: spacing.sm,
    paddingVertical: 6,
  },
  chipActive: { backgroundColor: colors.cta },
  chipText: { color: colors.textSecondary, fontSize: fontSizes.xs, textTransform: 'capitalize' },
  chipTextActive: { color: colors.textPrimary, fontWeight: 'bold' },
  saveButton: {
    backgroundColor: colors.cta,
    borderRadius: radius.md,
    paddingVertical: spacing.md,
    alignItems: 'center',
    marginTop: spacing.md,
  },
  saveDisabled: { opacity: 0.4 },
  saveText: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: 'bold' },
});
