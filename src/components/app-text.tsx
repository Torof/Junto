import { createContext, forwardRef, useCallback, useContext, type ComponentRef } from 'react';
import { Text, TextInput, StyleSheet, type TextProps, type TextInputProps, type TextStyle } from 'react-native';
import { useFontStore } from '@/store/font-store';
import { resolveTextStyle, type InheritedFont } from '@/constants/font-families';

// The ONE way the app renders text (eslint forbids Text/TextInput from
// react-native elsewhere). Applies the user's font family: fontWeight → that
// weight's file, fontSize → normalised to Roboto's width so no line wraps or
// truncates differently from one family to another (constants/font-families).

const InheritedFontContext = createContext<InheritedFont | null>(null);

export const AppText = forwardRef<ComponentRef<typeof Text>, TextProps>(function AppText({ style, children, ...rest }, ref) {
  const family = useFontStore((s) => s.family);
  const parent = useContext(InheritedFontContext);
  const resolved = resolveTextStyle(family, StyleSheet.flatten(style) as TextStyle | undefined, parent);
  const plain = typeof children === 'string' || typeof children === 'number';
  return (
    <Text ref={ref} {...rest} style={resolved.style}>
      {plain ? children : <InheritedFontContext.Provider value={resolved.inherited}>{children}</InheritedFontContext.Provider>}
    </Text>
  );
});

export const AppTextInput = forwardRef<ComponentRef<typeof TextInput>, TextInputProps>(function AppTextInput({ style, ...rest }, ref) {
  const family = useFontStore((s) => s.family);
  const resolved = resolveTextStyle(family, StyleSheet.flatten(style) as TextStyle | undefined, null);
  return <TextInput ref={ref} {...rest} style={resolved.style} />;
});

// For text a library renders itself (navigation header titles, tab labels).
export function useFontStyle(): (style: TextStyle) => TextStyle {
  const family = useFontStore((s) => s.family);
  return useCallback((style: TextStyle) => resolveTextStyle(family, style, null).style ?? style, [family]);
}
