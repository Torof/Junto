import { useMemo } from 'react';
import { View, StyleSheet } from 'react-native';
import { AppText } from '@/components/app-text';
import Svg from 'react-native-svg';
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
  PIN_DROP_TIP_Y, PIN_HEAD_CX, PIN_HEAD_CY, PIN_PAD_X, PIN_PAD_Y,
} from '@/constants/pin-style';
import { PinBody } from '@/components/pin-body';

interface ActivityPinProps {
  activity: NearbyActivity;
}

// Pin restyle 2026-10-16 (see constants/pin-style.ts): soft shadow drawn in
// the SVG, rounded tip, universe-colour body, white glyph; 2026-10-23: white
// outline + two-layer shadow (components/pin-body.tsx).
// The design space stays the historical 54-wide drop so the on-map size is
// unchanged (40 px wide).
const DESIGN_W = 54;
const VIEWBOX_W = DESIGN_W + 2 * PIN_PAD_X;
const VIEWBOX_H = 54 + 2 * PIN_PAD_Y;
const DROP_PX = 40;
const SCALE = DROP_PX / DESIGN_W;
const PIN_WIDTH = Math.round(VIEWBOX_W * SCALE);
const PIN_HEIGHT = Math.round(VIEWBOX_H * SCALE);
// Glyph box centred on the head, projected to screen px.
const PLATE_R = 17;
const PLATE_D = 2 * PLATE_R * SCALE;
const PLATE_LEFT = (PIN_HEAD_CX + PIN_PAD_X) * SCALE - PLATE_D / 2;
const PLATE_TOP = (PIN_HEAD_CY + PIN_PAD_Y) * SCALE - PLATE_D / 2;
const GLYPH_SIZE = 24;

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
  // The body is the universe colour; the status takes it over when it matters.
  const bodyColor = statusColor ?? universeColor;
  const isPrivate = activity.visibility === 'private_link' || activity.visibility === 'private_link_approval';

  return (
    <View style={styles.wrapper}>
      <Svg width={PIN_WIDTH} height={PIN_HEIGHT} viewBox={`${-PIN_PAD_X} ${-PIN_PAD_Y} ${VIEWBOX_W} ${VIEWBOX_H}`}>
        <PinBody fill={bodyColor} />
      </Svg>
      <View style={styles.plateClip}>
        {hasSportIcon(activity.sport_key) ? (
          <SportIcon sportKey={activity.sport_key} size={GLYPH_SIZE} color={colors.onCta} />
        ) : (
          <AppText style={styles.icon}>{getSportIcon(activity.sport_key)}</AppText>
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
