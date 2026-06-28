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

const VIEWBOX_W = 44;
const VIEWBOX_H = 52;
const PIN_WIDTH = 48;
const PIN_HEIGHT = Math.round((PIN_WIDTH * VIEWBOX_H) / VIEWBOX_W);

// Rounded square tapering to a fused point at (22,49).
const BODY_PATH =
  'M 13 3 L 31 3 Q 40 3 40 12 L 40 34 Q 40 39 35 40 L 22 49 L 9 40 Q 4 39 4 34 L 4 12 Q 4 3 13 3 Z';

export const PRO_OFFERING_PIN_ANCHOR = { x: 0.5, y: 49 / VIEWBOX_H };

// Emoji zone (viewbox) — the upper part of the square; PRO lives below it.
const EMOJI_ZONE = { x: 8, y: 3, w: 28, h: 28 };

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
          x={22}
          y={38}
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
    fontSize: 23,
  },
});
