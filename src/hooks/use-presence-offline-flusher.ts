import { useEffect } from 'react';
import { AppState } from 'react-native';
import NetInfo from '@react-native-community/netinfo';
import { flushOfflineGeoQueue } from '@/lib/presence-offline-cache';

export function usePresenceOfflineFlusher() {
  useEffect(() => {
    flushOfflineGeoQueue();

    const appSub = AppState.addEventListener('change', (state) => {
      if (state === 'active') flushOfflineGeoQueue();
    });

    const netUnsub = NetInfo.addEventListener((info) => {
      if (info.isConnected && info.isInternetReachable !== false) flushOfflineGeoQueue();
    });

    return () => {
      appSub.remove();
      netUnsub();
    };
  }, []);
}
