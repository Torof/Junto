import { View, Text, StyleSheet } from 'react-native';
import { colors, fontSizes, radius } from '@/constants/theme';

interface ClusterPinProps {
  count: number;
}

export function ClusterPin({ count }: ClusterPinProps) {
  return (
    <View style={styles.cluster}>
      <Text style={styles.count}>{count}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  cluster: {
    width: 48,
    height: 48,
    borderRadius: radius.full,
    backgroundColor: '#1B2838',
    borderWidth: 3,
    borderColor: '#3A506B',
    alignItems: 'center',
    justifyContent: 'center',
  },
  count: {
    color: '#FFFFFF',
    fontSize: fontSizes.md,
    fontWeight: 'bold',
  },
});
