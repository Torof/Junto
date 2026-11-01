import { supabase } from '@/services/supabase';

// Calendar links (mig 00568): the pro's private iCal feed (export) and the
// imported calendar that makes busy half-days unbookable.

export interface CalendarLinks {
  export_token: string;
  hide_names: boolean;
  import_connected: boolean;
  import_synced_at: string | null;
  // 'link_invalid' | 'unreachable' | 'too_large' | 'internal' (edge calendar-import)
  import_error: string | null;
}

// The feed URL is built from the app's own project URL — the token is the secret.
export const calendarFeedUrl = (token: string) =>
  `${process.env.EXPO_PUBLIC_SUPABASE_URL}/functions/v1/calendar-feed?token=${token}`;

export const calendarLinkService = {
  get: async (): Promise<CalendarLinks | null> => {
    const { data, error } = await supabase.rpc('get_calendar_links');
    if (error) throw error;
    return (data?.[0] ?? null) as CalendarLinks | null;
  },

  regenerateExport: async (): Promise<string> => {
    const { data, error } = await supabase.rpc('regenerate_calendar_export');
    if (error) throw error;
    return data as string;
  },

  setHideNames: async (hide: boolean): Promise<void> => {
    const { error } = await supabase.rpc('set_calendar_export_hide_names', { p_hide: hide });
    if (error) throw error;
  },

  // Empty / null unplugs the import (and forgets its busy half-days).
  setImportUrl: async (url: string | null): Promise<void> => {
    const { error } = await supabase.rpc('set_calendar_import_url', { p_url: url ?? '' });
    if (error) throw error;
  },
};
