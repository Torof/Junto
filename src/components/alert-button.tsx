import { useEffect, useRef } from 'react';
import { Animated, Pressable, StyleSheet } from 'react-native';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { Radar } from 'lucide-react-native';
import { colors, spacing, radius } from '@/constants/theme';

interface Props {
  blink?: boolean;
}

export function AlertButton({ blink = false }: Props) {
  const { t } = useTranslation();
  const router = useRouter();
  const scale = useRef(new Animated.Value(1)).current;
  const opacity = useRef(new Animated.Value(1)).current;

  useEffect(() => {
    if (!blink) {
      scale.setValue(1);
      opacity.setValue(1);
      return;
    }
    const loop = Animated.loop(
      Animated.sequence([
        Animated.parallel([
          Animated.timing(scale, { toValue: 1.25, duration: 450, useNativeDriver: true }),
          Animated.timing(opacity, { toValue: 0.6, duration: 450, useNativeDriver: true }),
        ]),
        Animated.parallel([
          Animated.timing(scale, { toValue: 1, duration: 450, useNativeDriver: true }),
          Animated.timing(opacity, { toValue: 1, duration: 450, useNativeDriver: true }),
        ]),
      ]),
    );
    loop.start();
    return () => loop.stop();
  }, [blink, scale, opacity]);

  return (
    <Animated.View style={[styles.wrapper, { transform: [{ scale }], opacity }]}>
      <Pressable style={styles.button} onPress={() => router.push('/(auth)/create-alert')} accessibilityLabel={t('alerts.createButton')}>
        <Radar size={22} color={colors.textPrimary} strokeWidth={2.2} />
      </Pressable>
    </Animated.View>
  );
}

const styles = StyleSheet.create({
  wrapper: {
    position: 'absolute',
    bottom: 140,
    right: spacing.md,
    zIndex: 10,
  },
  button: {
    backgroundColor: colors.surface,
    borderRadius: radius.full,
    width: 40,
    height: 40,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
    borderColor: colors.surface,
  },
});
