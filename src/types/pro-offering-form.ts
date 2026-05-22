import { z } from 'zod';

// Mirrors the create_pro_offering RPC contract. Runtime validation is
// in the SECURITY DEFINER function; this schema exists for type
// derivation and minimal client-side guardrails on the form.
export const proOfferingFormSchema = z.object({
  sport_id: z.string().uuid(),
  title: z.string().trim().min(3).max(100),
  description: z.string().max(2000),
  level: z.string().min(1),
  location_lng: z.number(),
  location_lat: z.number(),
  location_name: z.string().trim().min(1).max(100),
  duration_hours: z.number().min(0).max(24).nullable(),
  duration_minutes: z.number().min(0).max(59).nullable(),
  max_participants: z.number().int().min(1).max(50).nullable(),
  schedule_text: z.string().max(100).nullable(),
  distance_km: z.number().positive().max(9999).nullable(),
  elevation_gain_m: z.number().int().positive().max(99999).nullable(),
  image_url: z.string().max(500).nullable(),
});

export type ProOfferingFormData = z.infer<typeof proOfferingFormSchema>;
