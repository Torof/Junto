import { z } from 'zod';

export const activityFormSchema = z.object({
  // Step 1
  sport_id: z.string().uuid(),
  title: z.string().min(3).max(100),
  description: z.string().max(2000).optional(),
  level: z.string().min(1),
  max_participants: z.number().int().min(2).max(50),
  // Step 2
  location_start: z.object({
    lng: z.number(),
    lat: z.number(),
  }),
  location_meeting: z
    .object({
      lng: z.number(),
      lat: z.number(),
    })
    .optional(),
  starts_at: z.date().refine((d) => d > new Date(), 'Must be in the future'),
  duration_hours: z.number().min(0).max(24),
  duration_minutes: z.number().min(0).max(59),
  // Step 3
  visibility: z.enum(['public', 'approval', 'private_link', 'private_link_approval']),
});

export type ActivityFormData = z.infer<typeof activityFormSchema>;

export const LEVELS = ['débutant', 'intermédiaire', 'avancé', 'expert'] as const;
