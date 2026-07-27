import { useLayoutEffect, useMemo } from 'react';
import { View, Text, ScrollView, Pressable, StyleSheet } from 'react-native';
import { useRouter, useNavigation } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { useQuery } from '@tanstack/react-query';
import dayjs from 'dayjs';
import { Image } from 'expo-image';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { favoriteService } from '@/services/favorite-service';
import { FavoriteButton } from '@/components/favorite-button';
import { UserAvatar } from '@/components/user-avatar';
import { LogoSpinner } from '@/components/logo-spinner';

export default function FavoritesScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t, i18n } = useTranslation();
  const router = useRouter();
  const navigation = useNavigation();

  useLayoutEffect(() => {
    navigation.setOptions({ title: t('favorites.title', { defaultValue: 'Mes favoris' }) });
  }, [navigation, t]);

  const { data, isLoading } = useQuery({
    queryKey: ['favorites-detailed'],
    queryFn: () => favoriteService.getFavoritesDetailed(),
  });

  if (isLoading) return <View style={styles.center}><LogoSpinner size={48} /></View>;

  const empty = !data || (data.activities.length === 0 && data.offerings.length === 0 && data.pros.length === 0);

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content}>
      {empty && (
        <Text style={styles.empty}>
          {t('favorites.empty', { defaultValue: 'Aucun favori pour l’instant. Touche le cœur sur une sortie, une prestation ou un pro pour l’enregistrer ici.' })}
        </Text>
      )}

      {data && data.activities.length > 0 && (
        <>
          <Text style={styles.section}>{t('favorites.activities', { defaultValue: 'Sorties' })}</Text>
          {data.activities.map((a) => (
            <Pressable key={a.id} style={styles.row} onPress={() => router.push(`/(auth)/activity/${a.id}`)}>
              <View style={styles.thumbFallback}><Text style={styles.thumbEmoji}>🏔️</Text></View>
              <View style={styles.rowText}>
                <Text style={styles.rowTitle} numberOfLines={1}>{a.title}</Text>
                <Text style={styles.rowSub} numberOfLines={1}>
                  {dayjs(a.starts_at).locale(i18n.language).format('ddd D MMM [·] H[h]mm')}
                </Text>
              </View>
              <FavoriteButton kind="activity" id={a.id} size={20} />
            </Pressable>
          ))}
        </>
      )}

      {data && data.offerings.length > 0 && (
        <>
          <Text style={styles.section}>{t('favorites.offerings', { defaultValue: 'Prestations' })}</Text>
          {data.offerings.map((o) => (
            <Pressable key={o.id} style={styles.row} onPress={() => router.push(`/(auth)/pro/offering/${o.id}`)}>
              {o.image_url
                ? <Image source={{ uri: o.image_url }} style={styles.thumb} contentFit="cover" />
                : <View style={styles.thumbFallback}><Text style={styles.thumbEmoji}>🧗</Text></View>}
              <View style={styles.rowText}>
                <Text style={styles.rowTitle} numberOfLines={1}>{o.title}</Text>
                <Text style={styles.rowSub} numberOfLines={1}>
                  {o.pro_name}{o.price_eur != null ? ` · ${o.price_eur} €` : ''}
                </Text>
              </View>
              <FavoriteButton kind="offering" id={o.id} size={20} />
            </Pressable>
          ))}
        </>
      )}

      {data && data.pros.length > 0 && (
        <>
          <Text style={styles.section}>{t('favorites.pros', { defaultValue: 'Pros' })}</Text>
          {data.pros.map((p) => (
            <Pressable key={p.user_id} style={styles.row} onPress={() => router.push(`/(auth)/pro/${p.user_id}`)}>
              <UserAvatar name={p.display_name} avatarUrl={p.pin_image_url} size={44} />
              <View style={styles.rowText}>
                <Text style={styles.rowTitle} numberOfLines={1}>{p.display_name}</Text>
                {p.tagline ? <Text style={styles.rowSub} numberOfLines={1}>{p.tagline}</Text> : null}
              </View>
              <FavoriteButton kind="pro" id={p.user_id} size={20} />
            </Pressable>
          ))}
        </>
      )}
    </ScrollView>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: colors.background },
  content: { padding: spacing.md },
  empty: { color: colors.textSecondary, fontSize: fontSizes.md, textAlign: 'center', paddingVertical: spacing.xl, paddingHorizontal: spacing.md, lineHeight: 22 },
  section: {
    color: colors.textSecondary, fontSize: fontSizes.xs, fontWeight: '800',
    letterSpacing: 0.8, textTransform: 'uppercase',
    marginTop: spacing.md, marginBottom: spacing.xs,
  },
  row: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.md,
    borderWidth: 1, borderColor: colors.borderMuted, borderRadius: radius.md,
    backgroundColor: colors.surface, padding: spacing.sm, marginBottom: spacing.xs,
  },
  rowText: { flex: 1, minWidth: 0 },
  rowTitle: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '700' },
  rowSub: { color: colors.textSecondary, fontSize: fontSizes.xs, marginTop: 1 },
  thumb: { width: 44, height: 44, borderRadius: radius.sm, backgroundColor: colors.surface },
  thumbFallback: { width: 44, height: 44, borderRadius: radius.sm, backgroundColor: colors.background, alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: colors.borderMuted },
  thumbEmoji: { fontSize: 20 },
});
