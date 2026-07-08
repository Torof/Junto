import { useMemo, useState, useEffect } from 'react';
import { View, Text, Pressable, StyleSheet, Modal, ScrollView, Alert, ActivityIndicator } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useTranslation } from 'react-i18next';
import { useQueryClient } from '@tanstack/react-query';
import { X, ChevronDown } from 'lucide-react-native';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { fontSizes, spacing, radius, shadows } from '@/constants/theme';
import { useSports } from '@/hooks/use-sports';
import { getSportIcon } from '@/constants/sport-icons';
import { LEVELS } from '@/types/activity-form';
import { userService } from '@/services/user-service';
import { getFriendlyError } from '@/utils/friendly-error';

// "Gérer mes sports" — the ONLY declaration surface. Adding a new sport sets a
// free initial level (via set_sport_level). Already-declared sports are
// READ-ONLY here (their level evolves in the sport tooltip, peer-gated) — no
// re-pick and no removal, so a level can't be laundered by yo-yoing here.

const SHORT: Record<string, string> = {
  'débutant': 'Déb.',
  'intermédiaire': 'Inter.',
  'avancé': 'Avancé',
  'expert': 'Expert',
};
const CAP = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);

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
  const [busy, setBusy] = useState<string | null>(null);
  const [openAdd, setOpenAdd] = useState<string | null>(null);

  useEffect(() => {
    if (visible) setLevels({ ...(initialLevels ?? {}) });
  }, [visible, initialLevels]);

  const declared = (sports ?? []).filter((s) => levels[s.key]);
  const undeclared = (sports ?? []).filter((s) => !levels[s.key]);

  const doDeclare = async (sportKey: string, tier: string) => {
    if (busy) return;
    setBusy(sportKey);
    try {
      await userService.setSportLevel(sportKey, tier);
      setLevels((prev) => ({ ...prev, [sportKey]: tier }));
      await queryClient.invalidateQueries({ queryKey: ['currentUser'] });
      await queryClient.invalidateQueries({ queryKey: ['public-profile'] });
    } catch (err) {
      Alert.alert(t('auth.error'), getFriendlyError(err, 'generic'));
    } finally {
      setBusy(null);
    }
  };

  // Honesty warning on the FIRST declaration — anchors the asymmetry (down free,
  // up peer-validated) and the safety framing before committing.
  const askDeclare = (sportKey: string, sportName: string, tier: string) => {
    Alert.alert(
      t('profil.declareTitle', { level: SHORT[tier] ?? tier, sport: sportName, defaultValue: `Te déclarer ${SHORT[tier] ?? tier} en ${sportName} ?` }),
      t('profil.declareWarn', { defaultValue: "Choisis honnêtement ton niveau : tu pourras toujours redescendre, mais pour remonter il faudra que tes partenaires te confirment. C'est une indication de sécurité pour ceux qui partiront avec toi." }),
      [
        { text: t('common.cancel', { defaultValue: 'Annuler' }), style: 'cancel' },
        { text: t('profil.declareConfirm', { defaultValue: 'Me déclarer' }), onPress: () => doDeclare(sportKey, tier) },
      ],
    );
  };

  return (
    <Modal visible={visible} animationType="slide" transparent onRequestClose={onClose}>
      <View style={styles.backdrop}>
        <SafeAreaView style={styles.sheet} edges={['bottom']}>
          <View style={styles.header}>
            <Text style={styles.title}>{t('profil.sportsManageTitle', { defaultValue: 'Gérer mes sports' })}</Text>
            <Pressable onPress={onClose} hitSlop={8}>
              <X size={22} color={colors.textPrimary} strokeWidth={2.2} />
            </Pressable>
          </View>

          <ScrollView style={styles.list} contentContainerStyle={styles.listContent}>
            {declared.length > 0 && (
              <>
                <Text style={styles.groupLabel}>{t('profil.sportsDeclared', { defaultValue: 'Déjà déclarés' })}</Text>
                {declared.map((s) => {
                  const lvl = levels[s.key] ?? '';
                  return (
                    <View key={s.key} style={styles.declaredRow}>
                      <Text style={styles.rowEmoji}>{getSportIcon(s.key)}</Text>
                      <Text style={styles.declaredName} numberOfLines={1}>{t(`sports.${s.key}`, { defaultValue: s.key })}</Text>
                      <Text style={styles.declaredLevel}>{SHORT[lvl] ?? CAP(lvl)}</Text>
                    </View>
                  );
                })}
                <Text style={styles.manageHint}>
                  {t('profil.sportsManageHint', { defaultValue: 'Fais évoluer un niveau depuis la fiche du sport, sur ton profil.' })}
                </Text>
              </>
            )}

            {undeclared.length > 0 && (
              <>
                <Text style={styles.groupLabel}>{t('profil.sportsAdd', { defaultValue: 'Ajouter un sport — choisis ton niveau de départ' })}</Text>
                {undeclared.map((s) => {
                  const sportName = t(`sports.${s.key}`, { defaultValue: s.key });
                  const open = openAdd === s.key;
                  return (
                    <View key={s.key} style={styles.addRow}>
                      <Pressable
                        style={styles.addHead}
                        onPress={() => setOpenAdd(open ? null : s.key)}
                        disabled={!!busy}
                      >
                        <Text style={styles.rowEmoji}>{getSportIcon(s.key)}</Text>
                        <Text style={styles.addName} numberOfLines={1}>{sportName}</Text>
                        {busy === s.key ? (
                          <ActivityIndicator color={colors.cta} />
                        ) : (
                          <ChevronDown
                            size={18}
                            color={colors.textSecondary}
                            strokeWidth={2}
                            style={{ transform: [{ rotate: open ? '180deg' : '0deg' }] }}
                          />
                        )}
                      </Pressable>
                      {open && busy !== s.key && (
                        <View style={styles.tierChips}>
                          {LEVELS.map((tier) => (
                            <Pressable
                              key={tier}
                              onPress={() => askDeclare(s.key, sportName, tier)}
                              style={styles.tierChip}
                              disabled={!!busy}
                            >
                              <Text style={styles.tierChipText}>{SHORT[tier] ?? tier}</Text>
                            </Pressable>
                          ))}
                        </View>
                      )}
                    </View>
                  );
                })}
              </>
            )}
          </ScrollView>
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
    paddingBottom: spacing.sm,
  },
  title: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: '900', letterSpacing: -0.02 },
  list: { flexGrow: 0 },
  listContent: { paddingHorizontal: spacing.lg, paddingBottom: spacing.xl },
  groupLabel: {
    color: colors.textSecondary, fontSize: fontSizes.xs, fontWeight: '800',
    letterSpacing: 0.6, textTransform: 'uppercase', marginTop: spacing.lg, marginBottom: spacing.sm,
  },
  rowEmoji: { fontSize: 18 },
  declaredRow: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.sm,
    paddingVertical: spacing.sm, borderBottomWidth: 1, borderBottomColor: colors.borderMuted,
  },
  declaredName: { flex: 1, color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '700' },
  declaredLevel: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '800' },
  manageHint: { color: colors.textSecondary, fontSize: fontSizes.xs, marginTop: spacing.sm, lineHeight: fontSizes.xs * 1.4 },
  addRow: {
    paddingVertical: spacing.sm, borderBottomWidth: 1, borderBottomColor: colors.borderMuted,
  },
  addHead: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
  addName: { flex: 1, color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '600' },
  tierChips: { flexDirection: 'row', flexWrap: 'wrap', gap: 6, marginTop: spacing.sm, paddingLeft: 26 },
  tierChip: {
    borderWidth: 1, borderColor: colors.borderMuted, borderRadius: radius.sm,
    paddingHorizontal: spacing.sm, paddingVertical: 5, backgroundColor: colors.surface,
  },
  tierChipText: { color: colors.textSecondary, fontSize: fontSizes.xs, fontWeight: '700' },
});
