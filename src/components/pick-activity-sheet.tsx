import { useMemo } from 'react';
import { View, Text, Modal, Pressable, FlatList, StyleSheet } from 'react-native';
import { useTranslation } from 'react-i18next';
import { useQuery } from '@tanstack/react-query';
import dayjs from 'dayjs';
import 'dayjs/locale/fr';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { activityService } from '@/services/activity-service';
import { sportCategoryColor } from '@/utils/sport-category-color';
import { getSportIcon } from '@/constants/sport-icons';
import { LogoSpinner } from './logo-spinner';

interface Props {
  visible: boolean;
  onClose: () => void;
  onPick: (activityId: string) => void;
}

// Pick one of MY shareable outings (created ∪ joined, still live) to drop into a
// conversation as a rich card (Brique 4c). Complements ShareActivitySheet, which
// goes the other way (a given activity → pick a conversation).
export function PickActivitySheet({ visible, onClose, onPick }: Props) {
  const { t, i18n } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);

  const { data: created, isLoading: l1 } = useQuery({
    queryKey: ['my-created'], queryFn: () => activityService.getMyCreated(), enabled: visible,
  });
  const { data: joined, isLoading: l2 } = useQuery({
    queryKey: ['my-joined'], queryFn: () => activityService.getMyJoined(), enabled: visible,
  });

  const activities = useMemo(() => {
    const live = [...(created ?? []), ...(joined ?? [])].filter(
      (a) => a.status === 'published' || a.status === 'in_progress',
    );
    const byId = new Map(live.map((a) => [a.id, a]));
    return [...byId.values()].sort((a, b) => +new Date(a.starts_at) - +new Date(b.starts_at));
  }, [created, joined]);

  return (
    <Modal visible={visible} animationType="slide" transparent onRequestClose={onClose}>
      <Pressable style={styles.backdrop} onPress={onClose}>
        <Pressable style={styles.sheet} onPress={() => {}}>
          <View style={styles.handle} />
          <Text style={styles.title}>{t('messagerie.shareOutingTitle', { defaultValue: 'Partager une sortie' })}</Text>

          {l1 || l2 ? (
            <View style={styles.center}><LogoSpinner /></View>
          ) : activities.length === 0 ? (
            <Text style={styles.empty}>{t('messagerie.shareOutingEmpty', { defaultValue: 'Aucune sortie à venir à partager.' })}</Text>
          ) : (
            <FlatList
              data={activities}
              keyExtractor={(item) => item.id}
              style={styles.list}
              renderItem={({ item }) => (
                <Pressable style={styles.row} onPress={() => { onPick(item.id); onClose(); }}>
                  <View style={[styles.square, { backgroundColor: sportCategoryColor(item.sport_category, colors.cta) }]}>
                    <Text style={styles.squareEmoji}>{getSportIcon(item.sport_key)}</Text>
                  </View>
                  <View style={{ flex: 1, minWidth: 0 }}>
                    <Text style={styles.name} numberOfLines={1}>{item.title}</Text>
                    <Text style={styles.sub} numberOfLines={1}>
                      {dayjs(item.starts_at).locale(i18n.language).format('ddd D MMM · H[h]mm')}
                    </Text>
                  </View>
                </Pressable>
              )}
            />
          )}
        </Pressable>
      </Pressable>
    </Modal>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  backdrop: { flex: 1, backgroundColor: colors.overlay, justifyContent: 'flex-end' },
  sheet: {
    backgroundColor: colors.background,
    borderTopLeftRadius: radius.lg, borderTopRightRadius: radius.lg,
    padding: spacing.lg, paddingBottom: spacing.xl + 16, maxHeight: '80%',
  },
  handle: { width: 40, height: 4, borderRadius: 2, backgroundColor: colors.textSecondary, alignSelf: 'center', marginBottom: spacing.lg, opacity: 0.4 },
  title: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: 'bold', marginBottom: spacing.md },
  empty: { color: colors.textSecondary, fontSize: fontSizes.md, textAlign: 'center', paddingVertical: spacing.xl },
  center: { paddingVertical: spacing.xl, alignItems: 'center' },
  list: { maxHeight: 420 },
  row: { flexDirection: 'row', alignItems: 'center', gap: spacing.md, paddingVertical: spacing.sm },
  square: { width: 44, height: 44, borderRadius: radius.md, alignItems: 'center', justifyContent: 'center' },
  squareEmoji: { fontSize: 22 },
  name: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '700' },
  sub: { color: colors.textSecondary, fontSize: fontSizes.xs, marginTop: 2 },
});
