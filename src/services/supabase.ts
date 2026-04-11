import { createClient } from '@supabase/supabase-js';
import * as SecureStore from 'expo-secure-store';
import { type Database } from '@/types/supabase';

const supabaseUrl = process.env.EXPO_PUBLIC_SUPABASE_URL;
const supabaseAnonKey = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY;

if (!supabaseUrl || !supabaseAnonKey) {
  throw new Error('Missing Supabase environment variables. Check .env file.');
}

// SecureStore has a 2048 byte limit per key.
// Supabase sessions exceed this. Split large values into chunks.
const CHUNK_SIZE = 2000;

const chunkedSecureStoreAdapter = {
  getItem: async (key: string): Promise<string | null> => {
    const firstChunk = await SecureStore.getItemAsync(key);
    if (firstChunk === null) return null;

    let result = firstChunk;
    let i = 1;
    while (true) {
      const chunk = await SecureStore.getItemAsync(`${key}_chunk_${i}`);
      if (chunk === null) break;
      result += chunk;
      i++;
    }
    return result;
  },

  setItem: async (key: string, value: string): Promise<void> => {
    // Remove old chunks first
    let i = 1;
    while (true) {
      const existing = await SecureStore.getItemAsync(`${key}_chunk_${i}`);
      if (existing === null) break;
      await SecureStore.deleteItemAsync(`${key}_chunk_${i}`);
      i++;
    }

    // Write new chunks
    const chunks = Math.ceil(value.length / CHUNK_SIZE);
    await SecureStore.setItemAsync(key, value.slice(0, CHUNK_SIZE));
    for (let j = 1; j < chunks; j++) {
      await SecureStore.setItemAsync(
        `${key}_chunk_${j}`,
        value.slice(j * CHUNK_SIZE, (j + 1) * CHUNK_SIZE),
      );
    }
  },

  removeItem: async (key: string): Promise<void> => {
    await SecureStore.deleteItemAsync(key);
    let i = 1;
    while (true) {
      const existing = await SecureStore.getItemAsync(`${key}_chunk_${i}`);
      if (existing === null) break;
      await SecureStore.deleteItemAsync(`${key}_chunk_${i}`);
      i++;
    }
  },
};

export const supabase = createClient<Database>(supabaseUrl, supabaseAnonKey, {
  auth: {
    storage: chunkedSecureStoreAdapter,
    autoRefreshToken: true,
    persistSession: true,
    detectSessionInUrl: false,
  },
});
