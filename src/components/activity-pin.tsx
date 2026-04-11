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
  const pinColor = isFull ? colors.error : colors.success;

  return (
    <View style={[styles.container, { backgroundColor: pinColor }]}>
      <Text style={styles.icon}>{getSportIcon(activity.sport_key)}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    width: 40,
    height: 40,
    borderRadius: radius.full,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 2,
    borderColor: colors.background,
  },
  icon: {
    fontSize: 20,
  },
});
