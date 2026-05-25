import { supabase } from './supabase';
import { pushTokenService } from './push-token-service';

const WEB_HOST = process.env.EXPO_PUBLIC_JUNTO_WEB_HOST ?? 'getjunto.app';

export const authService = {
  getSession: async () => {
    const { data, error } = await supabase.auth.getSession();
    if (error) throw error;
    return data.session;
  },

  signInWithEmail: async (email: string, password: string) => {
    const { data, error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) throw error;
    return data;
  },

  signUpWithEmail: async (email: string, password: string) => {
    const { data, error } = await supabase.auth.signUp({ email, password });
    if (error) throw error;
    return data;
  },

  signOut: async () => {
    // Best-effort: revoke this device's push token BEFORE clearing
    // the session so the RPC runs while we still have auth. If the
    // session is already gone, the revoke silently no-ops inside the
    // service.
    await pushTokenService.revokeForCurrentDevice();
    const { error } = await supabase.auth.signOut();
    if (error) throw error;
  },

  requestPasswordReset: async (email: string) => {
    const { error } = await supabase.auth.resetPasswordForEmail(email, {
      redirectTo: `https://${WEB_HOST}/auth/reset-password`,
    });
    if (error) throw error;
  },

  verifyRecoveryToken: async (tokenHash: string) => {
    const { data, error } = await supabase.auth.verifyOtp({
      token_hash: tokenHash,
      type: 'recovery',
    });
    if (error) throw error;
    return data;
  },

  setRecoverySession: async (accessToken: string, refreshToken: string) => {
    const { data, error } = await supabase.auth.setSession({
      access_token: accessToken,
      refresh_token: refreshToken,
    });
    if (error) throw error;
    return data;
  },

  updatePassword: async (newPassword: string) => {
    const { error } = await supabase.auth.updateUser({ password: newPassword });
    if (error) throw error;
  },

  onAuthStateChange: (callback: Parameters<typeof supabase.auth.onAuthStateChange>[0]) => {
    return supabase.auth.onAuthStateChange(callback);
  },
};
