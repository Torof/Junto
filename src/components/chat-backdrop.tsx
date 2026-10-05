import { View, StyleSheet } from 'react-native';
import { Image } from 'expo-image';
import { useColors } from '@/hooks/use-theme';
import { SPORT_UNIVERSE } from '@/constants/sport-universe';
import { sportCategoryColor } from '@/utils/sport-category-color';

// Chat wallpaper (Scott 2026-10-05): a channel with a photo gets it blurred
// under a strong veil of the page background — a per-channel wash, like a
// personalised messenger wallpaper; a channel or activity thread without a
// photo gets a flat tint of its sport universe; DMs and groups pass nothing
// and stay plain. Sits as the first child of the screen container, under the
// list; the bubbles are untouched, so the veil has to stay strong enough for
// the grey `surfaceAlt` bubbles to read on top.
export const CHAT_BACKDROP_BLUR = 40;
export const CHAT_BACKDROP_VEIL = 0.88;
const TINT_ALPHA = '0F';

interface Props {
  photoUrl?: string | null;
  sportKey?: string | null;
  sportCategory?: string | null;
}

export function ChatBackdrop({ photoUrl, sportKey, sportCategory }: Props) {
  const colors = useColors();
  const category = sportCategory ?? (sportKey ? SPORT_UNIVERSE[sportKey] : undefined);
  const tint = category ? sportCategoryColor(category, colors.cta) : null;

  if (!photoUrl && !tint) return null;

  return (
    <View style={StyleSheet.absoluteFill} pointerEvents="none">
      {photoUrl ? (
        <>
          <Image
            source={{ uri: photoUrl }}
            style={StyleSheet.absoluteFill}
            contentFit="cover"
            blurRadius={CHAT_BACKDROP_BLUR}
            cachePolicy="memory-disk"
          />
          <View style={[StyleSheet.absoluteFill, { backgroundColor: colors.background, opacity: CHAT_BACKDROP_VEIL }]} />
        </>
      ) : (
        <View style={[StyleSheet.absoluteFill, { backgroundColor: tint + TINT_ALPHA }]} />
      )}
    </View>
  );
}
