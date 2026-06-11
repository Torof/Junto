import React from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import { captureWarning } from '@/lib/sentry';

interface Props {
  children: React.ReactNode;
}

interface State {
  hasError: boolean;
}

// App-level error boundary (prod audit D: there were none — any render
// error meant a silent white screen). Catches render-phase errors,
// reports them, and offers a reset instead of a dead app. Kept
// deliberately theme-independent: if theming itself is what crashed,
// this screen must still render.
export class ErrorBoundary extends React.Component<Props, State> {
  state: State = { hasError: false };

  static getDerivedStateFromError(): State {
    return { hasError: true };
  }

  componentDidCatch(error: Error, info: React.ErrorInfo) {
    captureWarning('react.boundary', error.message, {
      componentStack: info.componentStack?.slice(0, 1000),
    });
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
    backgroundColor: '#0D1B2A',
    alignItems: 'center',
    justifyContent: 'center',
    padding: 32,
    gap: 12,
  },
  title: { color: '#F5F5F0', fontSize: 28, fontWeight: '800' },
  body: { color: 'rgba(245,245,240,0.7)', fontSize: 15, textAlign: 'center', lineHeight: 22 },
  button: {
    marginTop: 12,
    backgroundColor: '#F4642A',
    borderRadius: 12,
    paddingVertical: 12,
    paddingHorizontal: 32,
  },
  buttonText: { color: '#0D1B2A', fontSize: 16, fontWeight: '700' },
});
