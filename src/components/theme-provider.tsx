import { createContext, useContext, useMemo } from 'react';
import { useColorScheme } from 'react-native';
import { useThemeStore } from '@/store/theme-store';
import { darkColors, lightColors, type AppColors } from '@/constants/colors';

const ThemeContext = createContext<AppColors>(darkColors);

export function useColors(): AppColors {
  return useContext(ThemeContext);
}

export function ThemeProvider({ children }: { children: React.ReactNode }) {
  const systemScheme = useColorScheme();
  const preference = useThemeStore((s) => s.preference);

  const resolved: 'dark' | 'light' =
    preference === 'system'
      ? (systemScheme === 'light' ? 'light' : 'dark')
      : preference;

  const themeColors = useMemo(
    () => (resolved === 'light' ? lightColors : darkColors),
    [resolved],
  );

  return (
    <ThemeContext.Provider value={themeColors}>
      {children}
    </ThemeContext.Provider>
  );
}

export function useResolvedTheme(): 'dark' | 'light' {
  const systemScheme = useColorScheme();
  const preference = useThemeStore((s) => s.preference);
  return preference === 'system'
    ? (systemScheme === 'light' ? 'light' : 'dark')
    : preference;
}
