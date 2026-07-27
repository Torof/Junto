import { useLayoutEffect, useMemo } from 'react';
import { View, Text, FlatList, Pressable, StyleSheet, Alert } from 'react-native';
import { useRouter, useNavigation } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { UserMinus } from 'lucide-react-native';
import * as Burnt from 'burnt';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { contactService } from '@/services/contact-service';
import { UserAvatar } from '@/components/user-avatar';
import { LogoSpinner } from '@/components/logo-spinner';
import { getFriendlyError } from '@/utils/friendly-error';

export default function ContactsScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const router = useRouter();
  const navigation = useNavigation();
  const queryClient = useQueryClient();

  useLayoutEffect(() => {
    navigation.setOptions({ title: t('contacts.title', { defaultValue: 'Contacts' }) });
  }, [navigation, t]);

  const { data: contacts, isLoading } = useQuery({
    queryKey: ['contacts'], queryFn: () => contactService.getContacts(),
  });

  const removeMut = useMutation({
    mutationFn: (id: string) => contactService.removeContact(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['contacts'] });
      queryClient.invalidateQueries({ queryKey: ['recent-partners'] });
    },
    onError: (e) => Burnt.toast({ title: getFriendlyError(e, 'generic') }),
  });

  const confirmRemove = (id: string, name: string) => Alert.alert(
    t('contacts.removeTitle', { defaultValue: 'Retirer ce contact ?' }),
    t('contacts.removeBody', { defaultValue: '{{name}} sera retiré de tes contacts.', name }),
    [
      { text: t('common.cancel', { defaultValue: 'Annuler' }), style: 'cancel' },
      { text: t('contacts.remove', { defaultValue: 'Retirer' }), style: 'destructive', onPress: () => removeMut.mutate(id) },
    ],
  );

  if (isLoading) return <View style={styles.center}><LogoSpinner size={48} /></View>;

  return (
    <View style={styles.container}>
      <FlatList
        data={contacts ?? []}
        keyExtractor={(i) => i.id}
        contentContainerStyle={styles.content}
        ListEmptyComponent={
          <Text style={styles.empty}>
            {t('contacts.empty', { defaultValue: 'Aucun contact pour l’instant. Ajoute des partenaires depuis leur profil pour les inviter plus vite sur tes sorties.' })}
          </Text>
        }
        renderItem={({ item }) => (
          <View style={styles.row}>
            <Pressable style={styles.rowMain} onPress={() => router.push(`/(auth)/profile/${item.id}`)}>
              <UserAvatar name={item.display_name} avatarUrl={item.avatar_url} size={44} />
              <Text style={styles.name} numberOfLines={1}>{item.display_name}</Text>
            </Pressable>
            <Pressable style={styles.removeBtn} onPress={() => confirmRemove(item.id, item.display_name)} hitSlop={8}>
              <UserMinus size={18} color={colors.error} strokeWidth={2.2} />
            </Pressable>
          </View>
        )}
      />
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: colors.background },
  content: { padding: spacing.md, gap: spacing.xs },
  empty: { color: colors.textSecondary, fontSize: fontSizes.md, textAlign: 'center', paddingVertical: spacing.xl, paddingHorizontal: spacing.md, lineHeight: 22 },
  row: {
    flexDirection: 'row', alignItems: 'center',
    borderWidth: 1, borderColor: colors.borderMuted, borderRadius: radius.md,
    backgroundColor: colors.surface, paddingRight: spacing.sm,
  },
  rowMain: { flex: 1, flexDirection: 'row', alignItems: 'center', gap: spacing.md, padding: spacing.sm },
  name: { flex: 1, color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '700' },
  removeBtn: {
    width: 40, height: 40, alignItems: 'center', justifyContent: 'center',
    borderRadius: radius.sm,
  },
});
