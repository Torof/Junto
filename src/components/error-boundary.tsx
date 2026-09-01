import React from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import { captureWarning } from '@/lib/sentry';

interface Props {
  children: React.ReactNode;
}

interface State {
  hasError: boolean;
  msg?: string;   // TEMP diag (Scott 2026-09-01)
  stack?: string; // TEMP diag
}

// App-level error boundary (prod audit D: there were none — any render
// error meant a silent white screen). Catches render-phase errors,
// reports them, and offers a reset instead of a dead app. Kept
// deliberately theme-independent (hardcoded palette, no useColors): if
// theming itself is what crashed, a hook-based fallback would re-crash.
// Colors are hardcoded to the LIGHT theme's values so the crash screen
// matches the app's default appearance instead of jarring dark.
export class ErrorBoundary extends React.Component<Props, State> {
  state: State = { hasError: false };

  static getDerivedStateFromError(error: Error): State {
    return { hasError: true, msg: `${error.name}: ${error.message}` };
  }

  componentDidCatch(error: Error, info: React.ErrorInfo) {
    captureWarning('react.boundary', error.message, {
      componentStack: info.componentStack?.slice(0, 1000),
    });
    this.setState({ stack: info.componentStack?.split('\n').map((l) => l.trim()).filter(Boolean).slice(0, 5).join('\n') });
  }

  handleReset = () => {
    this.setState({ hasError: false });
  };

  render() {
    if (this.state.hasError) {
      return (
        <View style={styles.container}>
          <Text style={styles.title}>Oups.</Text>
          <Text style={styles.body}>
            Une erreur inattendue est survenue. Si le problème persiste, redémarre l&apos;application.
          </Text>
          {(this.state.msg || this.state.stack) ? (
            <Text style={styles.diag} selectable>
              {this.state.msg}{this.state.stack ? `\n${this.state.stack}` : ''}
            </Text>
          ) : null}
          <Pressable style={styles.button} onPress={this.handleReset}>
            <Text style={styles.buttonText}>Réessayer</Text>
          </Pressable>
        </View>
      );
    }
    return this.props.children;
  }
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#F5EEDF', // light theme background
    alignItems: 'center',
    justifyContent: 'center',
    padding: 32,
    gap: 12,
  },
  title: { color: '#1F1A15', fontSize: 28, fontWeight: '800' },
  body: { color: 'rgba(31,26,21,0.7)', fontSize: 15, textAlign: 'center', lineHeight: 22 },
  diag: { color: '#B4341C', fontSize: 12, textAlign: 'left', lineHeight: 17, fontFamily: 'monospace', marginTop: 8 },
  button: {
    marginTop: 12,
    backgroundColor: '#F4642A',
    borderRadius: 12,
    paddingVertical: 12,
    paddingHorizontal: 32,
  },
  buttonText: { color: '#FFFFFF', fontSize: 16, fontWeight: '700' },
});
