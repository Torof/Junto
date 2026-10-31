import { useState } from 'react';
import { Alert } from 'react-native';
import { useRouter } from 'expo-router';
import { useQueryClient } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import * as Burnt from 'burnt';
import { proService } from '@/services/pro-service';
import { getFriendlyError } from '@/utils/friendly-error';

// Delete the whole pro page (cascades offerings + photos + reviews, tier → free),
// behind a destructive confirm. Shared by « Modifier ma page » and the Espace pro.
// The RPC refuses while future pending/accepted bookings exist
// (junto.offering_has_bookings → friendly message).
export function useDeleteProPage() {
  const { t } = useTranslation();
  const router = useRouter();
  const queryClient = useQueryClient();
  const [deleting, setDeleting] = useState(false);

  const confirmDelete = () => {
    Alert.alert(
      t('pro.deleteTitle', { defaultValue: 'Supprimer ta page pro ?' }),
      t('pro.deleteBody', {
        defaultValue:
          'Ta page pro, ses offres et ses avis seront définitivement supprimés, et ton compte repasse en gratuit. Cette action est irréversible.',
      }),
      [
        { text: t('common.cancel', { defaultValue: 'Annuler' }), style: 'cancel' },
        {
          text: t('pro.deleteConfirm', { defaultValue: 'Supprimer' }),
          style: 'destructive',
          onPress: async () => {
            setDeleting(true);
            try {
              await proService.unregister();
              await queryClient.invalidateQueries({ queryKey: ['pro-profile-mine'] });
              await queryClient.invalidateQueries({ queryKey: ['pro-profile'] });
              await queryClient.invalidateQueries({ queryKey: ['currentUser'] });
              await queryClient.invalidateQueries({ queryKey: ['pros'] });
              Burnt.toast({ title: t('pro.deleted', { defaultValue: 'Page pro supprimée' }), preset: 'done' });
              router.back();
            } catch (err) {
              Alert.alert(t('auth.error'), getFriendlyError(err, 'generic'));
            } finally {
              setDeleting(false);
            }
          },
        },
      ],
    );
  };

  return { confirmDelete, deleting };
}
