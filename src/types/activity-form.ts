import { z } from 'zod';

export const activityFormSchema = z.object({
  // Step 1
  sport_id: z.string().uuid(),
  title: z.string().min(3).max(100),
  description: z.string().max(2000).optional(),
  level: z.string().min(1),
  distance_km: z.number().positive().max(9999).nullable().optional(),
  elevation_gain_m: z.number().int().positive().max(99999).nullable().optional(),
  max_participants: z.number().int().min(2).max(50),
  // Step 2
  location_start: z
    .object({
      lng: z.number(),
      lat: z.number(),
    })
    .optional(),
  location_meeting: z.object({
    lng: z.number(),
    lat: z.number(),
  }),
  location_end: z
    .object({
      lng: z.number(),
      lat: z.number(),
    })
    .optional(),
  location_objective: z
    .object({
      lng: z.number(),
      lat: z.number(),
    })
    .optional(),
  objective_name: z.string().max(100).optional(),
  start_name: z.string().max(100).optional(),
  starts_at: z.date().refine((d) => d > new Date(), 'Must be in the future'),
  duration_hours: z.number().min(0).max(24),
  duration_minutes: z.number().min(0).max(59),
  // Step 3
  visibility: z.enum(['public', 'approval', 'private_link', 'private_link_approval']),
  requires_presence: z.boolean().default(true).optional(),
});

export type ActivityFormData = z.infer<typeof activityFormSchema>;

export const LEVELS = ['débutant', 'intermédiaire', 'avancé', 'expert'] as const;
