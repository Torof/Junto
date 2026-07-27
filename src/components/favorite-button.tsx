import { Pressable, StyleSheet, type ViewStyle } from 'react-native';
import { Heart } from 'lucide-react-native';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import * as Burnt from 'burnt';
import { useColors } from '@/hooks/use-theme';
import { favoriteService, type FavoriteKind } from '@/services/favorite-service';
import { getFriendlyError } from '@/utils/friendly-error';

interface Props {
  kind: FavoriteKind;
  id: string;
  size?: number;
  style?: ViewStyle;
}

// Heart toggle shared by activities, offerings and pro pages. Reads the single
// ['favorites'] refs query so every heart across the app stays in sync.
export function FavoriteButton({ kind, id, size = 22, style }: Props) {
  const colors = useColors();
  const queryClient = useQueryClient();

  const { data: favorites } = useQuery({ queryKey: ['favorites'], queryFn: () => favoriteService.getFavorites() });
  const isFav = (favorites ?? []).some((f) => f.kind === kind && f.ref_id === id);

  const mut = useMutation({
    mutationFn: () => (isFav ? favoriteService.remove(kind, id) : favoriteService.add(kind, id)),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['favorites'] });
      queryClient.invalidateQueries({ queryKey: ['favorites-detailed'] });
    },
    onError: (e) => Burnt.toast({ title: getFriendlyError(e, 'generic') }),
  });

  return (
    <Pressable onPress={() => mut.mutate()} disabled={mut.isPending} hitSlop={8} style={[styles.btn, style]}>
      <Heart
        size={size}
        color={isFav ? colors.cta : colors.textSecondary}
        fill={isFav ? colors.cta : 'transparent'}
        strokeWidth={2.2}
      />
    </Pressable>
  );
}

const styles = StyleSheet.create({
  btn: { alignItems: 'center', justifyContent: 'center' },
});
