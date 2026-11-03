import { useEffect, useState } from 'react';
import { Image } from 'expo-image';

// react-native-svg's <Image> keeps no cache: a remote href is downloaded again
// every time the view mounts (a pro pin photo, on every zoom or cluster
// split). This hands it expo-image's disk copy instead — downloaded once,
// then a local file. Resolved paths are kept for the session.
const resolved = new Map<string, string>();

async function localPath(url: string): Promise<string | null> {
  const hit = await Image.getCachePathAsync(url);
  if (hit) return hit;
  if (!(await Image.prefetch(url, 'disk'))) return null;
  return Image.getCachePathAsync(url);
}

const asFileUri = (path: string) => (path.startsWith('/') ? `file://${path}` : path);

// The local file URI for `url` once known; the remote URL if the cache can't
// give one (web, or a failed download); null while resolving.
export function useCachedImageUri(url: string | null | undefined): string | null {
  const [uri, setUri] = useState<string | null>(() => (url ? resolved.get(url) ?? null : null));

  useEffect(() => {
    if (!url) { setUri(null); return; }
    const known = resolved.get(url);
    if (known) { setUri(known); return; }
    setUri(null);
    let alive = true;
    localPath(url)
      .then((path) => {
        const next = path ? asFileUri(path) : url;
        if (path) resolved.set(url, next);
        if (alive) setUri(next);
      })
      .catch(() => { if (alive) setUri(url); });
    return () => { alive = false; };
  }, [url]);

  return uri;
}
