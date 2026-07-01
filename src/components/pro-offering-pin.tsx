import { useMemo } from 'react';
import { View, Text, StyleSheet } from 'react-native';
import Svg, { Path, Text as SvgText } from 'react-native-svg';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import { getSportIcon } from '@/constants/sport-icons';
import { type ProOffering } from '@/services/pro-offering-service';

interface ProOfferingPinProps {
  offering: ProOffering;
}

// Pin system v4 — shape encodes kind (square = pro offering vs teardrop peer
// sortie vs pushpin pro page), so colour is no longer needed as the "pro"
// signal. The marker is ONE white shape with a fused tail; the sport emoji is
// the hero (big, minimal padding) and a quiet "PRO" label sits in its own
// zone below it (accent blue — the only blue left, just enough to tie the
// pro family together). No price — Junto isn't a payment platform; "PRO"
// just signals a commercial, pro-led activity.

const VIEWBOX_W = 36;
const VIEWBOX_H = 52;
const PIN_WIDTH = 33;
const PIN_HEIGHT = Math.round((PIN_WIDTH * VIEWBOX_H) / VIEWBOX_W);

// "Price tag" (2026-07-01) — a rounded-top strip tapering to a fused point at
// (18,49). Widened a touch from the first pass; the vertical sides run at the
// tail's base width so they stay attached to the taper (no step). Reads as a
// hanging tag, distinct from the peer teardrop.
const BODY_PATH =
  'M 11 3 L 25 3 Q 33 3 33 11 L 33 38 L 18 49 L 3 38 L 3 11 Q 3 3 11 3 Z';

export const PRO_OFFERING_PIN_ANCHOR = { x: 0.5, y: 49 / VIEWBOX_H };

// Emoji zone (viewbox) — the upper part of the tag; PRO lives below it.
const EMOJI_ZONE = { x: 3, y: 2, w: 30, h: 28 };

export function ProOfferingPin({ offering }: ProOfferingPinProps) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);

  return (
    <View style={styles.wrapper}>
      <Svg width={PIN_WIDTH} height={PIN_HEIGHT} viewBox={`0 0 ${VIEWBOX_W} ${VIEWBOX_H}`}>
        <Path
          d={BODY_PATH}
          fill={colors.pinBackground}
          stroke={colors.pinBorder}
          strokeWidth={1.6}
          strokeOpacity={0.85}
          strokeLinejoin="round"
        />
        <SvgText
          x={18}
          y={36}
          fontSize={8.5}
          fontWeight="bold"
          fill={colors.pinProBackground}
          textAnchor="middle"
        >
          PRO
        </SvgText>
      </Svg>
      <View style={styles.iconWrap}>
        <Text style={styles.icon}>{getSportIcon(offering.sport_key)}</Text>
      </View>
    </View>
  );
}

const createStyles = (_colors: AppColors) => StyleSheet.create({
  wrapper: {
    width: PIN_WIDTH,
    height: PIN_HEIGHT,
    overflow: 'visible',
    shadowColor: '#0A0F1A',
    shadowOffset: { width: 0, height: 5 },
    shadowOpacity: 0.6,
    shadowRadius: 6,
    elevation: 10,
  },
  iconWrap: {
    position: 'absolute',
    left: (EMOJI_ZONE.x / VIEWBOX_W) * PIN_WIDTH,
    top: (EMOJI_ZONE.y / VIEWBOX_H) * PIN_HEIGHT,
    width: (EMOJI_ZONE.w / VIEWBOX_W) * PIN_WIDTH,
    height: (EMOJI_ZONE.h / VIEWBOX_H) * PIN_HEIGHT,
    alignItems: 'center',
    justifyContent: 'center',
  },
  icon: {
    fontSize: 16,
  },
});
