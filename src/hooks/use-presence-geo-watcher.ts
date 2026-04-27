import { useEffect, useRef } from 'react';
import * as Location from 'expo-location';
import * as Notifications from 'expo-notifications';
import { useTranslation } from 'react-i18next';
import { supabase } from '@/services/supabase';
import { haptic } from '@/lib/haptics';

interface ActiveActivity {
  activity_id: string;
  title: string;
  starts_at: string;
  duration: string;
  start_lng: number | null;
  start_lat: number | null;
  meeting_lng: number | null;
  meeting_lat: number | null;
  end_lng: number | null;
  end_lat: number | null;
}

const POLL_MS = 30_000;
const RADIUS_M = 150;
const PRE_WINDOW_MS = 15 * 60 * 1000;       // T-15min (matches confirm_presence_via_geo, mig 00132)
const POST_WINDOW_MS = 30 * 60 * 1000;       // T+30min

function distanceMeters(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371000;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLng = ((lng2 - lng1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos((lat1 * Math.PI) / 180) * Math.cos((lat2 * Math.PI) / 180) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

/**
 * Foreground geo watcher. Polls the user's position every 30s and fires a
 * local notification the first time they enter the validation zone of any
 * upcoming activity that requires presence — regardless of which screen
 * they are on. The activity-detail page still has its own check for the
 * in-page UI state, but this hook covers the broader "user with the app
 * open elsewhere" case.
 */
export function usePresenceGeoWatcher(enabled: boolean) {
  const { t } = useTranslation();
  const alertedRef = useRef<Set<string>>(new Set());

  useEffect(() => {
    if (!enabled) return;
    let cancelled = false;
    let interval: ReturnType<typeof setInterval> | null = null;

    const tick = async () => {
      try {
        const { data: candidates } = await supabase
          .rpc('get_my_active_presence_activities' as 'accept_tos') as unknown as {
            data: ActiveActivity[] | null;
          };
        if (cancelled || !candidates || candidates.length === 0) return;

        // Filter: now must be inside the geo window (T-10min → T+30min)
        const now = Date.now();
        const inWindow = candidates.filter((a) => {
          const start = new Date(a.starts_at).getTime();
          return now >= start - PRE_WINDOW_MS && now <= start + POST_WINDOW_MS;
        });
        if (inWindow.length === 0) return;

        // Permission check before reading position
        const { status: existing } = await Location.getForegroundPermissionsAsync();
        if (existing !== 'granted') return; // don't prompt from a background hook
        const pos = await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.Balanced });
        if (cancelled) return;

        for (const a of inWindow) {
          if (alertedRef.current.has(a.activity_id)) continue;
          const points: [number, number][] = [];
          if (a.start_lng != null && a.start_lat != null) points.push([a.start_lat, a.start_lng]);
          if (a.meeting_lng != null && a.meeting_lat != null) points.push([a.meeting_lat, a.meeting_lng]);
          if (a.end_lng != null && a.end_lat != null) points.push([a.end_lat, a.end_lng]);
          if (points.length === 0) continue;

          const minDist = Math.min(
            ...points.map(([lat, lng]) => distanceMeters(pos.coords.latitude, pos.coords.longitude, lat, lng)),
          );
          if (minDist <= RADIUS_M) {
            alertedRef.current.add(a.activity_id);
            haptic.success();
            Notifications.scheduleNotificationAsync({
              content: {
                title: t('presence.arrivedTitle'),
                body: t('presence.arrivedBody', { title: a.title }),
                data: { activity_id: a.activity_id, type: 'presence_geo_arrived' },
                sound: true,
              },
              trigger: null,
            }).catch(() => {});
          }
        }
      } catch {
        // ignore — best-effort polling
      }
    };

    tick();
    interval = setInterval(tick, POLL_MS);
    return () => {
      cancelled = true;
      if (interval) clearInterval(interval);
    };
  }, [enabled, t]);
}
