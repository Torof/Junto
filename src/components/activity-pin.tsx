import { useMemo } from 'react';
import { View, Text, StyleSheet } from 'react-native';
import Svg, { Path, Circle, Defs, Filter, FeGaussianBlur } from 'react-native-svg';
import { Lock } from 'lucide-react-native';
import { type AppColors } from '@/constants/colors';
import { useColors } from '@/hooks/use-theme';
import { getActivityTimeStatus } from '@/utils/activity-status';
import { getSportIcon } from '@/constants/sport-icons';
import { SportIcon } from '@/components/sport-icon';
import { hasSportIcon } from '@/constants/sport-icon-svgs';
import { sportCategoryColor } from '@/utils/sport-category-color';
import { type NearbyActivity } from '@/services/activity-service';
import {
  PIN_STYLE, PIN_DROP_PATH, PIN_DROP_TIP_Y, PIN_HEAD_CX, PIN_HEAD_CY, PIN_PAD_X, PIN_PAD_Y, PIN_SHADOW,
} from '@/constants/pin-style';

interface ActivityPinProps {
  activity: NearbyActivity;
}

// Pin restyle 2026-10-16 (see constants/pin-style.ts): no ink outline, soft
// shadow drawn in the SVG, rounded tip. The design space stays the historical
// 54-wide drop so the on-map size is unchanged (40 px wide).
const DESIGN_W = 54;
const VIEWBOX_W = DESIGN_W + 2 * PIN_PAD_X;
const VIEWBOX_H = 54 + 2 * PIN_PAD_Y;
const DROP_PX = 40;
const SCALE = DROP_PX / DESIGN_W;
const PIN_WIDTH = Math.round(VIEWBOX_W * SCALE);
const PIN_HEIGHT = Math.round(VIEWBOX_H * SCALE);
// Ivory plate (style A) and glyph centre, projected to screen px.
const PLATE_R = 17;
const PLATE_D = 2 * PLATE_R * SCALE;
const PLATE_LEFT = (PIN_HEAD_CX + PIN_PAD_X) * SCALE - PLATE_D / 2;
const PLATE_TOP = (PIN_HEAD_CY + PIN_PAD_Y) * SCALE - PLATE_D / 2;
const GLYPH_A = 22;
const GLYPH_B = 24;

// The tip sits on the geographic point.
export const ACTIVITY_PIN_ANCHOR = { x: 0.5, y: (PIN_DROP_TIP_Y + PIN_PAD_Y) / VIEWBOX_H };

export function ActivityPin({ activity }: ActivityPinProps) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const timeStatus = getActivityTimeStatus(activity.starts_at, activity.status);
  const statusColor =
    timeStatus === 'in_progress'
      ? colors.success
      : timeStatus === 'soon'
        ? '#F97316' // orange franc (Scott 2026-09-28)
        : null;
  const universeColor = sportCategoryColor(activity.sport_category, colors.cta);
  // A: the body carries the status, lemon by default. B: the body is the
  // universe colour, and the status takes it over when it matters.
  const bodyColor = PIN_STYLE === 'B'
    ? (statusColor ?? universeColor)
    : (statusColor ?? colors.pinFrame);
  const isPrivate = activity.visibility === 'private_link' || activity.visibility === 'private_link_approval';

  return (
    <View style={styles.wrapper}>
      <Svg width={PIN_WIDTH} height={PIN_HEIGHT} viewBox={`${-PIN_PAD_X} ${-PIN_PAD_Y} ${VIEWBOX_W} ${VIEWBOX_H}`}>
        <Defs>
          {/* Only FeGaussianBlur is implemented natively (react-native-svg 15):
              the shadow is a blurred dark copy of the shape, offset downward. */}
          <Filter id="pinBlur" x="-30%" y="-30%" width="160%" height="170%">
            <FeGaussianBlur stdDeviation={PIN_SHADOW.blur} />
          </Filter>
        </Defs>
        <Path
          d={PIN_DROP_PATH}
          fill={PIN_SHADOW.color}
          opacity={PIN_SHADOW.opacity}
          transform={`translate(${PIN_SHADOW.dx} ${PIN_SHADOW.dy})`}
          filter="url(#pinBlur)"
        />
        <Path d={PIN_DROP_PATH} fill={bodyColor} />
        {PIN_STYLE === 'A' && (
          <Circle cx={PIN_HEAD_CX} cy={PIN_HEAD_CY} r={PLATE_R} fill={colors.pinBackground} />
        )}
      </Svg>
      <View style={styles.plateClip}>
        {hasSportIcon(activity.sport_key) ? (
          <SportIcon
            sportKey={activity.sport_key}
            size={PIN_STYLE === 'B' ? GLYPH_B : GLYPH_A}
            color={PIN_STYLE === 'B' ? colors.onCta : undefined}
          />
        ) : (
          <Text style={styles.icon}>{getSportIcon(activity.sport_key)}</Text>
        )}
      </View>
      {/* Private outing — only its members ever see this pin (view 00315). */}
      {isPrivate && (
        <View style={styles.lockBadge}>
          <Lock size={9} color="#57534E" strokeWidth={2.8} />
        </View>
      )}
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  lockBadge: {
    position: 'absolute',
    top: PIN_PAD_Y * SCALE - 2,
    left: PIN_PAD_X * SCALE - 2,
    width: 16,
    height: 16,
    borderRadius: 8,
    backgroundColor: '#FBBF24',
    borderWidth: 1.5,
    borderColor: colors.pinBackground,
    alignItems: 'center',
    justifyContent: 'center',
  },
  wrapper: {
    width: PIN_WIDTH,
    height: PIN_HEIGHT,
    overflow: 'visible',
  },
  plateClip: {
    position: 'absolute',
    left: PLATE_LEFT,
    top: PLATE_TOP,
    width: PLATE_D,
    height: PLATE_D,
    borderRadius: PLATE_D / 2,
    overflow: 'hidden',
    alignItems: 'center',
    justifyContent: 'center',
  },
  icon: {
    fontSize: 17,
  },
});
