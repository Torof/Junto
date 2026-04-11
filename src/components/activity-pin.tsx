import { View, Text, StyleSheet } from 'react-native';
import { colors, radius } from '@/constants/theme';
import { getRemainingPlaces } from '@/utils/activity-status';
import { getSportIcon } from '@/constants/sport-icons';
import { type NearbyActivity } from '@/services/activity-service';

interface ActivityPinProps {
  activity: NearbyActivity;
}

export function ActivityPin({ activity }: ActivityPinProps) {
  const remaining = getRemainingPlaces(activity.max_participants, activity.participant_count);
  const isFull = remaining === 0;
  const borderColor = isFull ? colors.error : colors.success;

  return (
    <View style={[styles.ring, { borderColor }]}>
      <View style={styles.inner}>
        <Text style={styles.icon}>{getSportIcon(activity.sport_key)}</Text>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  ring: {
    width: 44,
    height: 44,
    borderRadius: radius.full,
    borderWidth: 3,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'transparent',
  },
  inner: {
    width: 36,
    height: 36,
    borderRadius: radius.full,
    backgroundColor: colors.textPrimary,
    alignItems: 'center',
    justifyContent: 'center',
  },
  icon: {
    fontSize: 18,
  },
});
