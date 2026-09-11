import { useMemo } from 'react';
import { useQuery } from '@tanstack/react-query';
import { useTranslation } from 'react-i18next';
import { supabase } from '@/services/supabase';

export interface SportRow {
  id: string;
  key: string;
  category: string;
  display_order: number;
  is_active: boolean;
}

/**
 * Canonical sports query — the single source of truth for the `['sports']`
 * cache. Every consumer (create flow, edit, dropdown, picker sheet, pro
 * offering) MUST use this hook rather than its own inline query.
 *
 * Why this exists:
 *  - Two different inline queries previously shared the `['sports']` key with
 *    *different* selects/orders (one `id,key,display_order` by display_order,
 *    one `key,category` by key). TanStack dedupes by key, so whichever ran
 *    first won the cache — and a reconnect refetch could flip the shape. When
 *    the `key,category` shape (no `id`, ordered by key — where `badminton` is
 *    first) landed in the cache, the create/edit flows read `id`-less,
 *    badminton-first rows → broken sport selection. Unifying the shape removes
 *    that class of bug.
 *  - Sports are static reference data (they only change via migration), so
 *    `staleTime: Infinity` keeps the list loaded once and stable — no refetch
 *    on reconnect/focus that could swap the array mid-interaction.
 */
export function useSports() {
  const { t, i18n } = useTranslation();
  const query = useQuery({
    queryKey: ['sports'],
    queryFn: async (): Promise<SportRow[]> => {
      const { data, error } = await supabase
        .from('sports')
        .select('id, key, category, display_order, is_active')
        .eq('is_active', true)
        .order('display_order');
      if (error) throw error;
      return data ?? [];
    },
    staleTime: Infinity,
    gcTime: Infinity,
  });

  // Alphabetical by TRANSLATED name in the active locale (Scott 2026-09-11) —
  // sorting here means every selector (dropdown, picker, filters, levels
  // editor, create/edit flows) inherits the order for free, in any language.
  // Map-building consumers don't care about order. display_order remains in
  // the row for any future curated use.
  const sorted = useMemo(() => {
    if (!query.data) return query.data;
    return [...query.data].sort((a, b) =>
      t(`sports.${a.key}`, { defaultValue: a.key }).localeCompare(
        t(`sports.${b.key}`, { defaultValue: b.key }),
        i18n.language,
      ));
  }, [query.data, t, i18n.language]);

  return { ...query, data: sorted } as typeof query;
}
