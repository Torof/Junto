import { View, Text, StyleSheet } from 'react-native';
import { colors, fontSizes, radius } from '@/constants/theme';
import { getRemainingPlaces } from '@/utils/activity-status';
import { getSportIcon } from '@/constants/sport-icons';
import { type NearbyActivity } from '@/services/activity-service';

interface ActivityPinProps {
  activity: NearbyActivity;
}

const PIN_SIZE = 44;
const DOT_SIZE = 16;

export function ActivityPin({ activity }: ActivityPinProps) {
  const remaining = getRemainingPlaces(activity.max_participants, activity.participant_count);
  const isFull = remaining === 0;
  const dotColor = isFull ? colors.error : colors.success;

  return (
    <View style={styles.wrapper}>
      <View style={styles.circle}>
        <Text style={styles.icon}>{getSportIcon(activity.sport_key)}</Text>
      </View>
      <View style={[styles.dot, { backgroundColor: dotColor }]}>
        <Text style={styles.dotText}>{remaining}</Text>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  wrapper: {
    width: PIN_SIZE,
    height: PIN_SIZE,
    overflow: 'visible',
  },
  circle: {
    width: PIN_SIZE,
    height: PIN_SIZE,
    borderRadius: radius.full,
    backgroundColor: colors.textPrimary,
    borderWidth: 1.5,
    borderColor: '#000000',
    alignItems: 'center',
    justifyContent: 'center',
  },
  icon: {
    fontSize: 18,
  },
  dot: {
    width: DOT_SIZE,
    height: DOT_SIZE,
    borderRadius: DOT_SIZE / 2,
    position: 'absolute',
    top: -(DOT_SIZE / 2) + 6,
    right: -(DOT_SIZE / 2) + 6,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 2,
    borderColor: colors.background,
  },
  dotText: {
    color: '#fff',
    fontSize: fontSizes.xs - 3,
    fontWeight: 'bold',
  },
});
