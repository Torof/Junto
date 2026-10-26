import { createContext, useContext, useEffect, useMemo } from 'react';
import { Appearance, useColorScheme } from 'react-native';
import { useThemeStore } from '@/store/theme-store';
import { darkColors, lightColors, type AppColors } from '@/constants/colors';

const ThemeContext = createContext<AppColors>(darkColors);

export function useColors(): AppColors {
  return useContext(ThemeContext);
}

export function ThemeProvider({ children }: { children: React.ReactNode }) {
  const systemScheme = useColorScheme();
  const preference = useThemeStore((s) => s.preference);
  const accent = useThemeStore((s) => s.accent);

  const resolved: 'dark' | 'light' =
    preference === 'system'
      ? (systemScheme === 'light' ? 'light' : 'dark')
      : preference;

  // Tell the OS which appearance the app runs in, so native surfaces (permission
  // and picker dialogs, keyboard) follow the in-app theme rather than the phone's
  // (2026-10-26). 'unspecified' hands the choice back to the system.
  useEffect(() => {
    Appearance.setColorScheme(preference === 'system' ? 'unspecified' : preference);
  }, [preference]);

  const themeColors = useMemo(() => {
    const base = resolved === 'light' ? lightColors : darkColors;
    // User accent override → recolor the single `cta` token; everything that
    // reads it (buttons, tabs, FAB, links, active states) follows.
    return accent ? { ...base, cta: accent } : base;
  }, [resolved, accent]);

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
