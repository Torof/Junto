import { useMemo } from 'react';
import { View, Text, StyleSheet, Pressable } from 'react-native';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';

interface Props {
  text: string;
  position: 'top' | 'bottom';
  anchor: { top?: number; bottom?: number; left?: number; right?: number };
  arrowAlign?: 'left' | 'center' | 'right';
  onDismiss?: () => void;
}

export function TutorialTooltip({ text, position, anchor, arrowAlign = 'center', onDismiss }: Props) {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);

  const arrowAlignStyle =
    arrowAlign === 'left' ? styles.arrowLeft : arrowAlign === 'right' ? styles.arrowRight : styles.arrowCenter;

  return (
    <View style={[styles.container, anchor]} pointerEvents="box-none">
      <Pressable style={styles.bubble} onPress={onDismiss}>
        <Text style={styles.text}>{text}</Text>
      </Pressable>
      <View
        style={[
          styles.arrow,
          position === 'bottom' ? styles.arrowDown : styles.arrowUp,
          arrowAlignStyle,
        ]}
      />
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: {
    position: 'absolute',
    zIndex: 1000,
    alignItems: 'center',
  },
  bubble: {
    backgroundColor: '#FFFFFF',
    borderRadius: radius.lg,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
    maxWidth: 240,
    elevation: 8,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.3,
    shadowRadius: 4,
  },
  text: {
    color: colors.background,
    fontSize: fontSizes.sm,
    fontWeight: 'bold',
    textAlign: 'center',
  },
  arrow: {
    width: 0,
    height: 0,
    borderLeftWidth: 8,
    borderRightWidth: 8,
    borderLeftColor: 'transparent',
    borderRightColor: 'transparent',
  },
  arrowDown: {
    borderTopWidth: 10,
    borderTopColor: '#FFFFFF',
  },
  arrowUp: {
    borderBottomWidth: 10,
    borderBottomColor: '#FFFFFF',
  },
  arrowCenter: {
    alignSelf: 'center',
  },
  arrowLeft: {
    alignSelf: 'flex-start',
    marginLeft: 24,
  },
  arrowRight: {
    alignSelf: 'flex-end',
    marginRight: 24,
  },
});
