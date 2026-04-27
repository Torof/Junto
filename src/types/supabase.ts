export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  graphql_public: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      graphql: {
        Args: {
          extensions?: Json
          operationName?: string
          query?: string
          variables?: Json
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
      activities: {
        Row: {
          cancelled_reason: string | null
          created_at: string
          creator_id: string
          deleted_at: string | null
          description: string | null
          distance_km: number | null
          duration: string
          elevation_gain_m: number | null
          id: string
          invite_token: string
          level: string
          location_end: unknown
          location_meeting: unknown
          location_objective: unknown
          location_start: unknown
          max_participants: number | null
          objective_name: string | null
          requires_presence: boolean
          route: unknown
          sport_id: string
          start_name: string | null
          starts_at: string
          status: string
          title: string
          trace_geojson: Json | null
          updated_at: string
          visibility: string
        }
        Insert: {
          cancelled_reason?: string | null
          created_at?: string
          creator_id: string
          deleted_at?: string | null
          description?: string | null
          distance_km?: number | null
          duration: string
          elevation_gain_m?: number | null
          id?: string
          invite_token?: string
          level: string
          location_end?: unknown
          location_meeting?: unknown
          location_objective?: unknown
          location_start: unknown
          max_participants?: number | null
          objective_name?: string | null
          requires_presence?: boolean
          route?: unknown
          sport_id: string
          start_name?: string | null
          starts_at: string
          status?: string
          title: string
          trace_geojson?: Json | null
          updated_at?: string
          visibility?: string
        }
        Update: {
          cancelled_reason?: string | null
          created_at?: string
          creator_id?: string
          deleted_at?: string | null
          description?: string | null
          distance_km?: number | null
          duration?: string
          elevation_gain_m?: number | null
          id?: string
          invite_token?: string
          level?: string
          location_end?: unknown
          location_meeting?: unknown
          location_objective?: unknown
          location_start?: unknown
          max_participants?: number | null
          objective_name?: string | null
          requires_presence?: boolean
          route?: unknown
          sport_id?: string
          start_name?: string | null
          starts_at?: string
          status?: string
          title?: string
          trace_geojson?: Json | null
          updated_at?: string
          visibility?: string
        }
        Relationships: [
          {
            foreignKeyName: "activities_creator_id_fkey"
            columns: ["creator_id"]
            isOneToOne: false
            referencedRelation: "public_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activities_creator_id_fkey"
            columns: ["creator_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activities_sport_id_fkey"
            columns: ["sport_id"]
            isOneToOne: false
            referencedRelation: "sports"
            referencedColumns: ["id"]
          },
        ]
      }
      activity_alerts: {
        Row: {
          created_at: string
          ends_on: string | null
          id: string
          levels: string[] | null
          location: unknown
          radius_km: number
          sport_key: string | null
          starts_on: string | null
          user_id: string
        }
        Insert: {
          created_at?: string
          ends_on?: string | null
          id?: string
          levels?: string[] | null
          location: unknown
          radius_km: number
          sport_key?: string | null
          starts_on?: string | null
          user_id: string
        }
        Update: {
          created_at?: string
          ends_on?: string | null
          id?: string
          levels?: string[] | null
          location?: unknown
          radius_km?: number
          sport_key?: string | null
          starts_on?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "activity_alerts_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "public_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_alerts_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      activity_gear: {
        Row: {
          activity_id: string
          created_at: string
          gear_name: string
          id: string
          quantity: number
          user_id: string
        }
        Insert: {
          activity_id: string
          created_at?: string
          gear_name: string
          id?: string
          quantity?: number
          user_id: string
        }
        Update: {
          activity_id?: string
          created_at?: string
          gear_name?: string
          id?: string
          quantity?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "activity_gear_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "activities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_gear_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "activities_with_coords"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_gear_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "my_activities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_gear_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "my_joined_activities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_gear_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "public_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_gear_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      app_config: {
        Row: {
          name: string
          value: string
        }
        Insert: {
          name: string
          value: string
        }
        Update: {
          name?: string
          value?: string
        }
        Relationships: []
      }
      blocked_users: {
        Row: {
          blocked_id: string
          blocker_id: string
          created_at: string
        }
        Insert: {
          blocked_id: string
          blocker_id: string
          created_at?: string
        }
        Update: {
          blocked_id?: string
          blocker_id?: string
          created_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "blocked_users_blocked_id_fkey"
            columns: ["blocked_id"]
            isOneToOne: false
            referencedRelation: "public_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "blocked_users_blocked_id_fkey"
            columns: ["blocked_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "blocked_users_blocker_id_fkey"
            columns: ["blocker_id"]
            isOneToOne: false
            referencedRelation: "public_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "blocked_users_blocker_id_fkey"
            columns: ["blocker_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      conversations: {
        Row: {
          created_at: string
          hidden_by_user_1: boolean
          hidden_by_user_2: boolean
          id: string
          initiated_by: string
          initiated_from: string | null
          last_message_at: string | null
          request_expires_at: string | null
          request_message: string | null
          request_sender_id: string | null
          status: string
          user_1: string
          user_2: string
        }
        Insert: {
          created_at?: string
          hidden_by_user_1?: boolean
          hidden_by_user_2?: boolean
          id?: string
          initiated_by: string
          initiated_from?: string | null
          last_message_at?: string | null
          request_expires_at?: string | null
          request_message?: string | null
          request_sender_id?: string | null
          status?: string
          user_1: string
          user_2: string
        }
        Update: {
          created_at?: string
          hidden_by_user_1?: boolean
          hidden_by_user_2?: boolean
          id?: string
          initiated_by?: string
          initiated_from?: string | null
          last_message_at?: string | null
          request_expires_at?: string | null
          request_message?: string | null
          request_sender_id?: string | null
          status?: string
          user_1?: string
          user_2?: string
        }
        Relationships: [
          {
            foreignKeyName: "conversations_initiated_by_fkey"
            columns: ["initiated_by"]
            isOneToOne: false
            referencedRelation: "public_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "conversations_initiated_by_fkey"
            columns: ["initiated_by"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "conversations_request_sender_id_fkey"
            columns: ["request_sender_id"]
            isOneToOne: false
            referencedRelation: "public_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "conversations_request_sender_id_fkey"
            columns: ["request_sender_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "conversations_user_1_fkey"
            columns: ["user_1"]
            isOneToOne: false
            referencedRelation: "public_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "conversations_user_1_fkey"
            columns: ["user_1"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "conversations_user_2_fkey"
            columns: ["user_2"]
            isOneToOne: false
            referencedRelation: "public_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "conversations_user_2_fkey"
            columns: ["user_2"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      gear_catalog: {
        Row: {
          category_key: string
          display_order: number
          id: string
          name_key: string
          per_person: boolean
          shared_recommended_qty: number | null
          sport_keys: string[]
        }
        Insert: {
          category_key?: string
          display_order?: number
          id?: string
          name_key: string
          per_person?: boolean
          shared_recommended_qty?: number | null
          sport_keys?: string[]
        }
        Update: {
          category_key?: string
          display_order?: number
          id?: string
          name_key?: string
          per_person?: boolean
          shared_recommended_qty?: number | null
          sport_keys?: string[]
        }
        Relationships: []
      }
      notifications: {
        Row: {
          body: string
          created_at: string
          data: Json | null
          id: string
          read_at: string | null
          title: string
          type: string
          user_id: string
        }
        Insert: {
          body: string
          created_at?: string
          data?: Json | null
          id?: string
          read_at?: string | null
          title: string
          type: string
          user_id: string
        }
        Update: {
          body?: string
          created_at?: string
          data?: Json | null
          id?: string
          read_at?: string | null
          title?: string
          type?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "notifications_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "public_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      participations: {
        Row: {
          activity_id: string
          confirmed_present: boolean | null
          created_at: string
          id: string
          left_at: string | null
          left_reason: string | null
          penalty_waived: boolean
          refused_at: string | null
          status: string
          transport_departs_at: string | null
          transport_from_name: string | null
          transport_seats: number | null
          transport_type: string | null
          user_id: string
        }
        Insert: {
          activity_id: string
          confirmed_present?: boolean | null
          created_at?: string
          id?: string
          left_at?: string | null
          left_reason?: string | null
          penalty_waived?: boolean
          refused_at?: string | null
          status?: string
          transport_departs_at?: string | null
          transport_from_name?: string | null
          transport_seats?: number | null
          transport_type?: string | null
          user_id: string
        }
        Update: {
          activity_id?: string
          confirmed_present?: boolean | null
          created_at?: string
          id?: string
          left_at?: string | null
          left_reason?: string | null
          penalty_waived?: boolean
          refused_at?: string | null
          status?: string
          transport_departs_at?: string | null
          transport_from_name?: string | null
          transport_seats?: number | null
          transport_type?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "participations_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "activities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "participations_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "activities_with_coords"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "participations_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "my_activities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "participations_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "my_joined_activities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "participations_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "public_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "participations_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      peer_validations: {
        Row: {
          activity_id: string
          created_at: string
          id: string
          voted_id: string
          voter_id: string
        }
        Insert: {
          activity_id: string
          created_at?: string
          id?: string
          voted_id: string
          voter_id: string
        }
        Update: {
          activity_id?: string
          created_at?: string
          id?: string
          voted_id?: string
          voter_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "peer_validations_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "activities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "peer_validations_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "activities_with_coords"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "peer_validations_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "my_activities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "peer_validations_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "my_joined_activities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "peer_validations_voted_id_fkey"
            columns: ["voted_id"]
            isOneToOne: false
            referencedRelation: "public_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "peer_validations_voted_id_fkey"
            columns: ["voted_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "peer_validations_voter_id_fkey"
            columns: ["voter_id"]
            isOneToOne: false
            referencedRelation: "public_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "peer_validations_voter_id_fkey"
            columns: ["voter_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      presence_tokens: {
        Row: {
          activity_id: string
          created_at: string
          expires_at: string
          token: string
        }
        Insert: {
          activity_id: string
          created_at?: string
          expires_at: string
          token: string
        }
        Update: {
          activity_id?: string
          created_at?: string
          expires_at?: string
          token?: string
        }
        Relationships: [
          {
            foreignKeyName: "presence_tokens_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "activities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "presence_tokens_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "activities_with_coords"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "presence_tokens_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "my_activities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "presence_tokens_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "my_joined_activities"
            referencedColumns: ["id"]
          },
        ]
      }
      private_messages: {
        Row: {
          content: string
          conversation_id: string
          created_at: string
          deleted_at: string | null
          edited_at: string | null
          id: string
          metadata: Json | null
          receiver_id: string
          sender_id: string
        }
        Insert: {
          content: string
          conversation_id: string
          created_at?: string
          deleted_at?: string | null
          edited_at?: string | null
          id?: string
          metadata?: Json | null
          receiver_id: string
          sender_id: string
        }
        Update: {
          content?: string
          conversation_id?: string
          created_at?: string
          deleted_at?: string | null
          edited_at?: string | null
          id?: string
          metadata?: Json | null
          receiver_id?: string
          sender_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "private_messages_conversation_id_fkey"
            columns: ["conversation_id"]
            isOneToOne: false
            referencedRelation: "conversations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "private_messages_receiver_id_fkey"
            columns: ["receiver_id"]
            isOneToOne: false
            referencedRelation: "public_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "private_messages_receiver_id_fkey"
            columns: ["receiver_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "private_messages_sender_id_fkey"
            columns: ["sender_id"]
            isOneToOne: false
            referencedRelation: "public_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "private_messages_sender_id_fkey"
            columns: ["sender_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      reports: {
        Row: {
          admin_note: string | null
          created_at: string
          id: string
          reason: string
          reporter_id: string
          resolved_at: string | null
          status: string
          target_id: string
          target_type: string
        }
        Insert: {
          admin_note?: string | null
          created_at?: string
          id?: string
          reason: string
          reporter_id: string
          resolved_at?: string | null
          status?: string
          target_id: string
          target_type: string
        }
        Update: {
          admin_note?: string | null
          created_at?: string
          id?: string
          reason?: string
          reporter_id?: string
          resolved_at?: string | null
          status?: string
          target_id?: string
          target_type?: string
        }
        Relationships: [
          {
            foreignKeyName: "reports_reporter_id_fkey"
            columns: ["reporter_id"]
            isOneToOne: false
            referencedRelation: "public_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reports_reporter_id_fkey"
            columns: ["reporter_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      reputation_votes: {
        Row: {
          activity_id: string
          badge_key: string
          created_at: string
          id: string
          voted_id: string
          voter_id: string
        }
        Insert: {
          activity_id: string
          badge_key: string
          created_at?: string
          id?: string
          voted_id: string
          voter_id: string
        }
        Update: {
          activity_id?: string
          badge_key?: string
          created_at?: string
          id?: string
          voted_id?: string
          voter_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "reputation_votes_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "activities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reputation_votes_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "activities_with_coords"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reputation_votes_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "my_activities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reputation_votes_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "my_joined_activities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reputation_votes_voted_id_fkey"
            columns: ["voted_id"]
            isOneToOne: false
            referencedRelation: "public_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reputation_votes_voted_id_fkey"
            columns: ["voted_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reputation_votes_voter_id_fkey"
            columns: ["voter_id"]
            isOneToOne: false
            referencedRelation: "public_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reputation_votes_voter_id_fkey"
            columns: ["voter_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      seat_requests: {
        Row: {
          activity_id: string
          created_at: string
          driver_id: string
          id: string
          message: string | null
          pickup_from: string | null
          requested_pickup_at: string | null
          requester_id: string
          status: string
        }
        Insert: {
          activity_id: string
          created_at?: string
          driver_id: string
          id?: string
          message?: string | null
          pickup_from?: string | null
          requested_pickup_at?: string | null
          requester_id: string
          status?: string
        }
        Update: {
          activity_id?: string
          created_at?: string
          driver_id?: string
          id?: string
          message?: string | null
          pickup_from?: string | null
          requested_pickup_at?: string | null
          requester_id?: string
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "seat_requests_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "activities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "seat_requests_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "activities_with_coords"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "seat_requests_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "my_activities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "seat_requests_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "my_joined_activities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "seat_requests_driver_id_fkey"
            columns: ["driver_id"]
            isOneToOne: false
            referencedRelation: "public_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "seat_requests_driver_id_fkey"
            columns: ["driver_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "seat_requests_requester_id_fkey"
            columns: ["requester_id"]
            isOneToOne: false
            referencedRelation: "public_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "seat_requests_requester_id_fkey"
            columns: ["requester_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      spatial_ref_sys: {
        Row: {
          auth_name: string | null
          auth_srid: number | null
          proj4text: string | null
          srid: number
          srtext: string | null
        }
        Insert: {
          auth_name?: string | null
          auth_srid?: number | null
          proj4text?: string | null
          srid: number
          srtext?: string | null
        }
        Update: {
          auth_name?: string | null
          auth_srid?: number | null
          proj4text?: string | null
          srid?: number
          srtext?: string | null
        }
        Relationships: []
      }
      sport_level_endorsements: {
        Row: {
          activity_id: string
          created_at: string
          id: string
          is_confirmation: boolean
          sport_key: string
          target_id: string
          voter_id: string
        }
        Insert: {
          activity_id: string
          created_at?: string
          id?: string
          is_confirmation: boolean
          sport_key: string
          target_id: string
          voter_id: string
        }
        Update: {
          activity_id?: string
          created_at?: string
          id?: string
          is_confirmation?: boolean
          sport_key?: string
          target_id?: string
          voter_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "sport_level_endorsements_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "activities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sport_level_endorsements_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "activities_with_coords"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sport_level_endorsements_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "my_activities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sport_level_endorsements_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "my_joined_activities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sport_level_endorsements_target_id_fkey"
            columns: ["target_id"]
            isOneToOne: false
            referencedRelation: "public_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sport_level_endorsements_target_id_fkey"
            columns: ["target_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sport_level_endorsements_voter_id_fkey"
            columns: ["voter_id"]
            isOneToOne: false
            referencedRelation: "public_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sport_level_endorsements_voter_id_fkey"
            columns: ["voter_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      sports: {
        Row: {
          category: string
          display_order: number
          icon: string
          id: string
          key: string
        }
        Insert: {
          category: string
          display_order: number
          icon: string
          id?: string
          key: string
        }
        Update: {
          category?: string
          display_order?: number
          icon?: string
          id?: string
          key?: string
        }
        Relationships: []
      }
      users: {
        Row: {
          accepted_privacy_at: string | null
          accepted_tos_at: string | null
          avatar_url: string | null
          bio: string | null
          created_at: string
          date_of_birth: string | null
          display_name: string
          email: string
          id: string
          is_admin: boolean
          is_pro_verified: boolean
          levels_per_sport: Json | null
          notification_preferences: Json
          phone_verified: boolean
          phone_verified_at: string | null
          pro_verified_at: string | null
          push_token: string | null
          reliability_score: number | null
          sports: Json | null
          suspended_at: string | null
          tier: string
          tutorial_seen_at: string | null
          updated_at: string
        }
        Insert: {
          accepted_privacy_at?: string | null
          accepted_tos_at?: string | null
          avatar_url?: string | null
          bio?: string | null
          created_at?: string
          date_of_birth?: string | null
          display_name: string
          email: string
          id: string
          is_admin?: boolean
          is_pro_verified?: boolean
          levels_per_sport?: Json | null
          notification_preferences?: Json
          phone_verified?: boolean
          phone_verified_at?: string | null
          pro_verified_at?: string | null
          push_token?: string | null
          reliability_score?: number | null
          sports?: Json | null
          suspended_at?: string | null
          tier?: string
          tutorial_seen_at?: string | null
          updated_at?: string
        }
        Update: {
          accepted_privacy_at?: string | null
          accepted_tos_at?: string | null
          avatar_url?: string | null
          bio?: string | null
          created_at?: string
          date_of_birth?: string | null
          display_name?: string
          email?: string
          id?: string
          is_admin?: boolean
          is_pro_verified?: boolean
          levels_per_sport?: Json | null
          notification_preferences?: Json
          phone_verified?: boolean
          phone_verified_at?: string | null
          pro_verified_at?: string | null
          push_token?: string | null
          reliability_score?: number | null
          sports?: Json | null
          suspended_at?: string | null
          tier?: string
          tutorial_seen_at?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      wall_messages: {
        Row: {
          activity_id: string
          content: string
          created_at: string
          deleted_at: string | null
          edited_at: string | null
          id: string
          user_id: string | null
        }
        Insert: {
          activity_id: string
          content: string
          created_at?: string
          deleted_at?: string | null
          edited_at?: string | null
          id?: string
          user_id?: string | null
        }
        Update: {
          activity_id?: string
          content?: string
          created_at?: string
          deleted_at?: string | null
          edited_at?: string | null
          id?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "wall_messages_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "activities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "wall_messages_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "activities_with_coords"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "wall_messages_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "my_activities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "wall_messages_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "my_joined_activities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "wall_messages_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "public_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "wall_messages_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      activities_with_coords: {
        Row: {
          created_at: string | null
          creator_avatar: string | null
          creator_id: string | null
          creator_name: string | null
          deleted_at: string | null
          description: string | null
          distance_km: number | null
          duration: string | null
          elevation_gain_m: number | null
          end_lat: number | null
          end_lng: number | null
          id: string | null
          lat: number | null
          level: string | null
          lng: number | null
          max_participants: number | null
          meeting_lat: number | null
          meeting_lng: number | null
          objective_lat: number | null
          objective_lng: number | null
          objective_name: string | null
          participant_count: number | null
          requires_presence: boolean | null
          sport_category: string | null
          sport_icon: string | null
          sport_id: string | null
          sport_key: string | null
          start_lat: number | null
          start_lng: number | null
          start_name: string | null
          starts_at: string | null
          status: string | null
          title: string | null
          trace_geojson: Json | null
          updated_at: string | null
          visibility: string | null
        }
        Relationships: [
          {
            foreignKeyName: "activities_creator_id_fkey"
            columns: ["creator_id"]
            isOneToOne: false
            referencedRelation: "public_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activities_creator_id_fkey"
            columns: ["creator_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activities_sport_id_fkey"
            columns: ["sport_id"]
            isOneToOne: false
            referencedRelation: "sports"
            referencedColumns: ["id"]
          },
        ]
      }
      activity_participants: {
        Row: {
          activity_id: string | null
          avatar_url: string | null
          created_at: string | null
          creator_id: string | null
          display_name: string | null
          left_at: string | null
          left_reason: string | null
          levels_per_sport: Json | null
          participation_id: string | null
          penalty_waived: boolean | null
          reliability_tier: string | null
          sports: Json | null
          status: string | null
          transport_departs_at: string | null
          transport_from_name: string | null
          transport_seats: number | null
          transport_type: string | null
          user_id: string | null
        }
        Relationships: [
          {
            foreignKeyName: "activities_creator_id_fkey"
            columns: ["creator_id"]
            isOneToOne: false
            referencedRelation: "public_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activities_creator_id_fkey"
            columns: ["creator_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "participations_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "activities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "participations_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "activities_with_coords"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "participations_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "my_activities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "participations_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "my_joined_activities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "participations_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "public_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "participations_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      geography_columns: {
        Row: {
          coord_dimension: number | null
          f_geography_column: unknown
          f_table_catalog: unknown
          f_table_name: unknown
          f_table_schema: unknown
          srid: number | null
          type: string | null
        }
        Relationships: []
      }
      geometry_columns: {
        Row: {
          coord_dimension: number | null
          f_geometry_column: unknown
          f_table_catalog: string | null
          f_table_name: unknown
          f_table_schema: unknown
          srid: number | null
          type: string | null
        }
        Insert: {
          coord_dimension?: number | null
          f_geometry_column?: unknown
          f_table_catalog?: string | null
          f_table_name?: unknown
          f_table_schema?: unknown
          srid?: number | null
          type?: string | null
        }
        Update: {
          coord_dimension?: number | null
          f_geometry_column?: unknown
          f_table_catalog?: string | null
          f_table_name?: unknown
          f_table_schema?: unknown
          srid?: number | null
          type?: string | null
        }
        Relationships: []
      }
      my_activities: {
        Row: {
          created_at: string | null
          creator_avatar: string | null
          creator_id: string | null
          creator_name: string | null
          deleted_at: string | null
          description: string | null
          distance_km: number | null
          duration: string | null
          elevation_gain_m: number | null
          end_lat: number | null
          end_lng: number | null
          id: string | null
          lat: number | null
          level: string | null
          lng: number | null
          max_participants: number | null
          meeting_lat: number | null
          meeting_lng: number | null
          objective_lat: number | null
          objective_lng: number | null
          objective_name: string | null
          participant_count: number | null
          requires_presence: boolean | null
          sport_category: string | null
          sport_icon: string | null
          sport_id: string | null
          sport_key: string | null
          start_lat: number | null
          start_lng: number | null
          start_name: string | null
          starts_at: string | null
          status: string | null
          title: string | null
          trace_geojson: Json | null
          updated_at: string | null
          visibility: string | null
        }
        Relationships: [
          {
            foreignKeyName: "activities_creator_id_fkey"
            columns: ["creator_id"]
            isOneToOne: false
            referencedRelation: "public_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activities_creator_id_fkey"
            columns: ["creator_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activities_sport_id_fkey"
            columns: ["sport_id"]
            isOneToOne: false
            referencedRelation: "sports"
            referencedColumns: ["id"]
          },
        ]
      }
      my_joined_activities: {
        Row: {
          created_at: string | null
          creator_avatar: string | null
          creator_id: string | null
          creator_name: string | null
          deleted_at: string | null
          description: string | null
          distance_km: number | null
          duration: string | null
          elevation_gain_m: number | null
          end_lat: number | null
          end_lng: number | null
          id: string | null
          lat: number | null
          level: string | null
          lng: number | null
          max_participants: number | null
          meeting_lat: number | null
          meeting_lng: number | null
          objective_lat: number | null
          objective_lng: number | null
          objective_name: string | null
          participant_count: number | null
          requires_presence: boolean | null
          sport_category: string | null
          sport_icon: string | null
          sport_id: string | null
          sport_key: string | null
          start_lat: number | null
          start_lng: number | null
          start_name: string | null
          starts_at: string | null
          status: string | null
          title: string | null
          trace_geojson: Json | null
          updated_at: string | null
          visibility: string | null
        }
        Relationships: [
          {
            foreignKeyName: "activities_creator_id_fkey"
            columns: ["creator_id"]
            isOneToOne: false
            referencedRelation: "public_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activities_creator_id_fkey"
            columns: ["creator_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activities_sport_id_fkey"
            columns: ["sport_id"]
            isOneToOne: false
            referencedRelation: "sports"
            referencedColumns: ["id"]
          },
        ]
      }
      public_participants: {
        Row: {
          activity_id: string | null
          avatar_url: string | null
          created_at: string | null
          display_name: string | null
          left_at: string | null
          participation_id: string | null
          status: string | null
          transport_departs_at: string | null
          transport_from_name: string | null
          transport_seats: number | null
          transport_type: string | null
          user_id: string | null
        }
        Relationships: [
          {
            foreignKeyName: "participations_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "activities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "participations_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "activities_with_coords"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "participations_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "my_activities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "participations_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "my_joined_activities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "participations_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "public_profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "participations_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      public_profiles: {
        Row: {
          avatar_url: string | null
          bio: string | null
          created_at: string | null
          display_name: string | null
          id: string | null
          levels_per_sport: Json | null
          sports: Json | null
        }
        Insert: {
          avatar_url?: string | null
          bio?: string | null
          created_at?: string | null
          display_name?: string | null
          id?: string | null
          levels_per_sport?: Json | null
          sports?: Json | null
        }
        Update: {
          avatar_url?: string | null
          bio?: string | null
          created_at?: string | null
          display_name?: string | null
          id?: string | null
          levels_per_sport?: Json | null
          sports?: Json | null
        }
        Relationships: []
      }
    }
    Functions: {
      _is_presence_window: { Args: { p_activity_id: string }; Returns: boolean }
      _postgis_deprecate: {
        Args: { newname: string; oldname: string; version: string }
        Returns: undefined
      }
      _postgis_index_extent: {
        Args: { col: string; tbl: unknown }
        Returns: unknown
      }
      _postgis_pgsql_version: { Args: never; Returns: string }
      _postgis_scripts_pgsql_version: { Args: never; Returns: string }
      _postgis_selectivity: {
        Args: { att_name: string; geom: unknown; mode?: string; tbl: unknown }
        Returns: number
      }
      _postgis_stats: {
        Args: { ""?: string; att_name: string; tbl: unknown }
        Returns: string
      }
      _st_3dintersects: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      _st_contains: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      _st_containsproperly: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      _st_coveredby:
        | { Args: { geog1: unknown; geog2: unknown }; Returns: boolean }
        | { Args: { geom1: unknown; geom2: unknown }; Returns: boolean }
      _st_covers:
        | { Args: { geog1: unknown; geog2: unknown }; Returns: boolean }
        | { Args: { geom1: unknown; geom2: unknown }; Returns: boolean }
      _st_crosses: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      _st_dwithin: {
        Args: {
          geog1: unknown
          geog2: unknown
          tolerance: number
          use_spheroid?: boolean
        }
        Returns: boolean
      }
      _st_equals: { Args: { geom1: unknown; geom2: unknown }; Returns: boolean }
      _st_intersects: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      _st_linecrossingdirection: {
        Args: { line1: unknown; line2: unknown }
        Returns: number
      }
      _st_longestline: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: unknown
      }
      _st_maxdistance: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: number
      }
      _st_orderingequals: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      _st_overlaps: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      _st_sortablehash: { Args: { geom: unknown }; Returns: number }
      _st_touches: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      _st_voronoi: {
        Args: {
          clip?: unknown
          g1: unknown
          return_polygons?: boolean
          tolerance?: number
        }
        Returns: unknown
      }
      _st_within: { Args: { geom1: unknown; geom2: unknown }; Returns: boolean }
      accept_contact_request: {
        Args: { p_conversation_id: string }
        Returns: undefined
      }
      accept_participation: {
        Args: { p_participation_id: string }
        Returns: undefined
      }
      accept_seat_request: {
        Args: { p_request_id: string }
        Returns: undefined
      }
      accept_tos: { Args: never; Returns: undefined }
      addauth: { Args: { "": string }; Returns: boolean }
      addgeometrycolumn:
        | {
            Args: {
              catalog_name: string
              column_name: string
              new_dim: number
              new_srid_in: number
              new_type: string
              schema_name: string
              table_name: string
              use_typmod?: boolean
            }
            Returns: string
          }
        | {
            Args: {
              column_name: string
              new_dim: number
              new_srid: number
              new_type: string
              schema_name: string
              table_name: string
              use_typmod?: boolean
            }
            Returns: string
          }
        | {
            Args: {
              column_name: string
              new_dim: number
              new_srid: number
              new_type: string
              table_name: string
              use_typmod?: boolean
            }
            Returns: string
          }
      cancel_accepted_seat: {
        Args: { p_request_id: string }
        Returns: undefined
      }
      cancel_activity: {
        Args: { p_activity_id: string; p_reason: string }
        Returns: undefined
      }
      cancel_contact_request: {
        Args: { p_conversation_id: string }
        Returns: undefined
      }
      check_activity_transitions: { Args: never; Returns: undefined }
      check_alerts_for_activity: {
        Args: { p_activity_id: string }
        Returns: undefined
      }
      close_due_presence_windows: { Args: never; Returns: undefined }
      close_presence_window_for: {
        Args: { p_activity_id: string }
        Returns: undefined
      }
      confirm_presence: {
        Args: { p_activity_id: string; p_present_user_ids: string[] }
        Returns: undefined
      }
      confirm_presence_via_geo: {
        Args: { p_activity_id: string; p_lat: number; p_lng: number }
        Returns: undefined
      }
      confirm_presence_via_token: { Args: { p_token: string }; Returns: string }
      create_activity: {
        Args: {
          p_description: string
          p_distance_km?: number
          p_duration?: string
          p_elevation_gain_m?: number
          p_end_lat?: number
          p_end_lng?: number
          p_level: string
          p_max_participants: number
          p_meeting_lat?: number
          p_meeting_lng?: number
          p_objective_lat?: number
          p_objective_lng?: number
          p_objective_name?: string
          p_requires_presence?: boolean
          p_sport_id: string
          p_start_lat: number
          p_start_lng: number
          p_start_name?: string
          p_starts_at?: string
          p_title: string
          p_trace_geojson?: Json
          p_visibility?: string
        }
        Returns: string
      }
      create_alert: {
        Args: {
          p_ends_on?: string
          p_lat: number
          p_levels?: string[]
          p_lng: number
          p_radius_km: number
          p_sport_key?: string
          p_starts_on?: string
        }
        Returns: string
      }
      create_notification: {
        Args: {
          p_body: string
          p_data?: Json
          p_title: string
          p_type: string
          p_user_id: string
        }
        Returns: string
      }
      create_or_get_conversation: {
        Args: { p_other_user_id: string }
        Returns: string
      }
      create_presence_token: {
        Args: { p_activity_id: string }
        Returns: string
      }
      create_report: {
        Args: { p_reason: string; p_target_id: string; p_target_type: string }
        Returns: string
      }
      decline_contact_request: {
        Args: { p_conversation_id: string }
        Returns: undefined
      }
      decline_seat_request: {
        Args: { p_request_id: string }
        Returns: undefined
      }
      delete_own_account: { Args: never; Returns: undefined }
      disablelongtransactions: { Args: never; Returns: string }
      dropgeometrycolumn:
        | {
            Args: {
              catalog_name: string
              column_name: string
              schema_name: string
              table_name: string
            }
            Returns: string
          }
        | {
            Args: {
              column_name: string
              schema_name: string
              table_name: string
            }
            Returns: string
          }
        | { Args: { column_name: string; table_name: string }; Returns: string }
      dropgeometrytable:
        | {
            Args: {
              catalog_name: string
              schema_name: string
              table_name: string
            }
            Returns: string
          }
        | { Args: { schema_name: string; table_name: string }; Returns: string }
        | { Args: { table_name: string }; Returns: string }
      edit_private_message: {
        Args: { p_content?: string; p_delete?: boolean; p_message_id: string }
        Returns: undefined
      }
      edit_wall_message: {
        Args: { p_content?: string; p_delete?: boolean; p_message_id: string }
        Returns: undefined
      }
      enablelongtransactions: { Args: never; Returns: string }
      ensure_user_row: { Args: never; Returns: undefined }
      equals: { Args: { geom1: unknown; geom2: unknown }; Returns: boolean }
      generate_random_name: { Args: never; Returns: string }
      geometry: { Args: { "": string }; Returns: unknown }
      geometry_above: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      geometry_below: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      geometry_cmp: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: number
      }
      geometry_contained_3d: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      geometry_contains: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      geometry_contains_3d: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      geometry_distance_box: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: number
      }
      geometry_distance_centroid: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: number
      }
      geometry_eq: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      geometry_ge: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      geometry_gt: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      geometry_le: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      geometry_left: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      geometry_lt: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      geometry_overabove: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      geometry_overbelow: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      geometry_overlaps: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      geometry_overlaps_3d: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      geometry_overleft: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      geometry_overright: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      geometry_right: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      geometry_same: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      geometry_same_3d: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      geometry_within: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      geomfromewkt: { Args: { "": string }; Returns: unknown }
      get_activity_by_invite_token: {
        Args: { p_token: string }
        Returns: {
          creator_avatar: string
          creator_id: string
          creator_name: string
          description: string
          duration: string
          id: string
          lat: number
          level: string
          lng: number
          max_participants: number
          participant_count: number
          sport_category: string
          sport_icon: string
          sport_id: string
          sport_key: string
          starts_at: string
          status: string
          title: string
          visibility: string
        }[]
      }
      get_activity_peer_review_state: {
        Args: { p_activity_id: string }
        Returns: {
          avatar_url: string
          confirmed_present: boolean
          display_name: string
          i_voted_presence: boolean
          my_badge_votes: string[]
          peer_validation_count: number
          user_id: string
        }[]
      }
      get_my_active_presence_activities: {
        Args: never
        Returns: {
          activity_id: string
          duration: string
          end_lat: number
          end_lng: number
          meeting_lat: number
          meeting_lng: number
          start_lat: number
          start_lng: number
          starts_at: string
          title: string
        }[]
      }
      get_own_invite_token: { Args: { p_activity_id: string }; Returns: string }
      get_transport_summary: {
        Args: { p_activity_id: string }
        Returns: {
          cities: string[]
          count: number
          total_seats: number
          transport_type: string
        }[]
      }
      get_user_public_stats: {
        Args: { p_user_id: string }
        Returns: {
          completed_activities: number
          created_activities: number
          joined_activities: number
          reliability_tier: string
          sports_count: number
          total_activities: number
        }[]
      }
      get_user_reputation: {
        Args: { p_user_id: string }
        Returns: {
          badge_key: string
          vote_count: number
        }[]
      }
      get_user_sport_breakdown: {
        Args: { p_user_id: string }
        Returns: {
          completed_count: number
          level: string
          sport_icon: string
          sport_key: string
        }[]
      }
      get_user_sport_endorsements: {
        Args: { p_user_id: string }
        Returns: {
          net_count: number
          sport_key: string
        }[]
      }
      get_user_trophies: {
        Args: { p_user_id: string }
        Returns: {
          trophy_count: number
          trophy_key: string
        }[]
      }
      gettransactionid: { Args: never; Returns: unknown }
      give_reputation_badge: {
        Args: { p_activity_id: string; p_badge_key: string; p_voted_id: string }
        Returns: undefined
      }
      hide_conversation: {
        Args: { p_conversation_id: string }
        Returns: undefined
      }
      join_activity: { Args: { p_activity_id: string }; Returns: string }
      leave_activity: {
        Args: { p_activity_id: string; p_reason?: string }
        Returns: undefined
      }
      longtransactionsenabled: { Args: never; Returns: boolean }
      mark_all_notifications_read: { Args: never; Returns: undefined }
      mark_notification_read: {
        Args: { p_notification_id: string }
        Returns: undefined
      }
      mark_tutorial_seen: { Args: never; Returns: undefined }
      moderate_report: {
        Args: {
          p_action: string
          p_admin_note?: string
          p_report_id: string
          p_suspend_user_id?: string
        }
        Returns: undefined
      }
      notify_creator_qr_reminder: {
        Args: { p_activity_id: string }
        Returns: undefined
      }
      notify_participant_joined: {
        Args: {
          p_activity_id: string
          p_activity_title: string
          p_creator_id: string
          p_joiner_name: string
        }
        Returns: undefined
      }
      notify_peer_review_closing: {
        Args: { p_activity_id: string }
        Returns: undefined
      }
      notify_presence_last_call: {
        Args: { p_activity_id: string }
        Returns: undefined
      }
      notify_presence_pre_warning: {
        Args: { p_activity_id: string }
        Returns: undefined
      }
      notify_presence_reminders: {
        Args: { p_activity_id: string }
        Returns: undefined
      }
      peer_validate_presence: {
        Args: { p_activity_id: string; p_voted_id: string }
        Returns: undefined
      }
      populate_geometry_columns:
        | { Args: { tbl_oid: unknown; use_typmod?: boolean }; Returns: number }
        | { Args: { use_typmod?: boolean }; Returns: string }
      postgis_constraint_dims: {
        Args: { geomcolumn: string; geomschema: string; geomtable: string }
        Returns: number
      }
      postgis_constraint_srid: {
        Args: { geomcolumn: string; geomschema: string; geomtable: string }
        Returns: number
      }
      postgis_constraint_type: {
        Args: { geomcolumn: string; geomschema: string; geomtable: string }
        Returns: string
      }
      postgis_extensions_upgrade: { Args: never; Returns: string }
      postgis_full_version: { Args: never; Returns: string }
      postgis_geos_version: { Args: never; Returns: string }
      postgis_lib_build_date: { Args: never; Returns: string }
      postgis_lib_revision: { Args: never; Returns: string }
      postgis_lib_version: { Args: never; Returns: string }
      postgis_libjson_version: { Args: never; Returns: string }
      postgis_liblwgeom_version: { Args: never; Returns: string }
      postgis_libprotobuf_version: { Args: never; Returns: string }
      postgis_libxml_version: { Args: never; Returns: string }
      postgis_proj_version: { Args: never; Returns: string }
      postgis_scripts_build_date: { Args: never; Returns: string }
      postgis_scripts_installed: { Args: never; Returns: string }
      postgis_scripts_released: { Args: never; Returns: string }
      postgis_svn_version: { Args: never; Returns: string }
      postgis_type_name: {
        Args: {
          coord_dimension: number
          geomname: string
          use_new_name?: boolean
        }
        Returns: string
      }
      postgis_version: { Args: never; Returns: string }
      postgis_wagyu_version: { Args: never; Returns: string }
      purge_old_notifications: { Args: never; Returns: undefined }
      recalculate_reliability_score: {
        Args: { p_user_id: string }
        Returns: undefined
      }
      refuse_participation: {
        Args: { p_participation_id: string }
        Returns: undefined
      }
      register_push_token: { Args: { p_token: string }; Returns: undefined }
      reliability_tier: { Args: { p_score: number }; Returns: string }
      remove_participant: {
        Args: { p_participation_id: string }
        Returns: undefined
      }
      request_seat: {
        Args: {
          p_activity_id: string
          p_driver_id: string
          p_message?: string
          p_pickup_from?: string
          p_requested_pickup_at?: string
        }
        Returns: string
      }
      revoke_reputation_badge: {
        Args: { p_activity_id: string; p_badge_key: string; p_voted_id: string }
        Returns: undefined
      }
      sanitize_notif_text: { Args: { p: string }; Returns: string }
      send_contact_request: {
        Args: { p_message: string; p_source?: string; p_target_user_id: string }
        Returns: string
      }
      send_private_message: {
        Args: { p_content: string; p_conversation_id: string }
        Returns: string
      }
      send_wall_message: {
        Args: { p_activity_id: string; p_content: string }
        Returns: string
      }
      set_activity_gear: {
        Args: { p_activity_id: string; p_items: Json }
        Returns: undefined
      }
      set_date_of_birth: {
        Args: { p_date_of_birth: string }
        Returns: undefined
      }
      set_participation_transport: {
        Args: {
          p_activity_id: string
          p_transport_departs_at?: string
          p_transport_from_name?: string
          p_transport_seats?: number
          p_transport_type: string
        }
        Returns: undefined
      }
      share_activity_message: {
        Args: { p_activity_id: string; p_conversation_id: string }
        Returns: string
      }
      share_trace_message: {
        Args: {
          p_conversation_id: string
          p_name: string
          p_trace_geojson: Json
        }
        Returns: string
      }
      st_3dclosestpoint: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: unknown
      }
      st_3ddistance: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: number
      }
      st_3dintersects: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      st_3dlongestline: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: unknown
      }
      st_3dmakebox: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: unknown
      }
      st_3dmaxdistance: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: number
      }
      st_3dshortestline: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: unknown
      }
      st_addpoint: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: unknown
      }
      st_angle:
        | { Args: { line1: unknown; line2: unknown }; Returns: number }
        | {
            Args: { pt1: unknown; pt2: unknown; pt3: unknown; pt4?: unknown }
            Returns: number
          }
      st_area:
        | { Args: { geog: unknown; use_spheroid?: boolean }; Returns: number }
        | { Args: { "": string }; Returns: number }
      st_asencodedpolyline: {
        Args: { geom: unknown; nprecision?: number }
        Returns: string
      }
      st_asewkt: { Args: { "": string }; Returns: string }
      st_asgeojson:
        | {
            Args: { geog: unknown; maxdecimaldigits?: number; options?: number }
            Returns: string
          }
        | {
            Args: { geom: unknown; maxdecimaldigits?: number; options?: number }
            Returns: string
          }
        | {
            Args: {
              geom_column?: string
              maxdecimaldigits?: number
              pretty_bool?: boolean
              r: Record<string, unknown>
            }
            Returns: string
          }
        | { Args: { "": string }; Returns: string }
      st_asgml:
        | {
            Args: {
              geog: unknown
              id?: string
              maxdecimaldigits?: number
              nprefix?: string
              options?: number
            }
            Returns: string
          }
        | {
            Args: { geom: unknown; maxdecimaldigits?: number; options?: number }
            Returns: string
          }
        | { Args: { "": string }; Returns: string }
        | {
            Args: {
              geog: unknown
              id?: string
              maxdecimaldigits?: number
              nprefix?: string
              options?: number
              version: number
            }
            Returns: string
          }
        | {
            Args: {
              geom: unknown
              id?: string
              maxdecimaldigits?: number
              nprefix?: string
              options?: number
              version: number
            }
            Returns: string
          }
      st_askml:
        | {
            Args: { geog: unknown; maxdecimaldigits?: number; nprefix?: string }
            Returns: string
          }
        | {
            Args: { geom: unknown; maxdecimaldigits?: number; nprefix?: string }
            Returns: string
          }
        | { Args: { "": string }; Returns: string }
      st_aslatlontext: {
        Args: { geom: unknown; tmpl?: string }
        Returns: string
      }
      st_asmarc21: { Args: { format?: string; geom: unknown }; Returns: string }
      st_asmvtgeom: {
        Args: {
          bounds: unknown
          buffer?: number
          clip_geom?: boolean
          extent?: number
          geom: unknown
        }
        Returns: unknown
      }
      st_assvg:
        | {
            Args: { geog: unknown; maxdecimaldigits?: number; rel?: number }
            Returns: string
          }
        | {
            Args: { geom: unknown; maxdecimaldigits?: number; rel?: number }
            Returns: string
          }
        | { Args: { "": string }; Returns: string }
      st_astext: { Args: { "": string }; Returns: string }
      st_astwkb:
        | {
            Args: {
              geom: unknown
              prec?: number
              prec_m?: number
              prec_z?: number
              with_boxes?: boolean
              with_sizes?: boolean
            }
            Returns: string
          }
        | {
            Args: {
              geom: unknown[]
              ids: number[]
              prec?: number
              prec_m?: number
              prec_z?: number
              with_boxes?: boolean
              with_sizes?: boolean
            }
            Returns: string
          }
      st_asx3d: {
        Args: { geom: unknown; maxdecimaldigits?: number; options?: number }
        Returns: string
      }
      st_azimuth:
        | { Args: { geog1: unknown; geog2: unknown }; Returns: number }
        | { Args: { geom1: unknown; geom2: unknown }; Returns: number }
      st_boundingdiagonal: {
        Args: { fits?: boolean; geom: unknown }
        Returns: unknown
      }
      st_buffer:
        | {
            Args: { geom: unknown; options?: string; radius: number }
            Returns: unknown
          }
        | {
            Args: { geom: unknown; quadsegs: number; radius: number }
            Returns: unknown
          }
      st_centroid: { Args: { "": string }; Returns: unknown }
      st_clipbybox2d: {
        Args: { box: unknown; geom: unknown }
        Returns: unknown
      }
      st_closestpoint: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: unknown
      }
      st_collect: { Args: { geom1: unknown; geom2: unknown }; Returns: unknown }
      st_concavehull: {
        Args: {
          param_allow_holes?: boolean
          param_geom: unknown
          param_pctconvex: number
        }
        Returns: unknown
      }
      st_contains: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      st_containsproperly: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      st_coorddim: { Args: { geometry: unknown }; Returns: number }
      st_coveredby:
        | { Args: { geog1: unknown; geog2: unknown }; Returns: boolean }
        | { Args: { geom1: unknown; geom2: unknown }; Returns: boolean }
      st_covers:
        | { Args: { geog1: unknown; geog2: unknown }; Returns: boolean }
        | { Args: { geom1: unknown; geom2: unknown }; Returns: boolean }
      st_crosses: { Args: { geom1: unknown; geom2: unknown }; Returns: boolean }
      st_curvetoline: {
        Args: { flags?: number; geom: unknown; tol?: number; toltype?: number }
        Returns: unknown
      }
      st_delaunaytriangles: {
        Args: { flags?: number; g1: unknown; tolerance?: number }
        Returns: unknown
      }
      st_difference: {
        Args: { geom1: unknown; geom2: unknown; gridsize?: number }
        Returns: unknown
      }
      st_disjoint: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      st_distance:
        | {
            Args: { geog1: unknown; geog2: unknown; use_spheroid?: boolean }
            Returns: number
          }
        | { Args: { geom1: unknown; geom2: unknown }; Returns: number }
      st_distancesphere:
        | { Args: { geom1: unknown; geom2: unknown }; Returns: number }
        | {
            Args: { geom1: unknown; geom2: unknown; radius: number }
            Returns: number
          }
      st_distancespheroid: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: number
      }
      st_dwithin: {
        Args: {
          geog1: unknown
          geog2: unknown
          tolerance: number
          use_spheroid?: boolean
        }
        Returns: boolean
      }
      st_equals: { Args: { geom1: unknown; geom2: unknown }; Returns: boolean }
      st_expand:
        | { Args: { box: unknown; dx: number; dy: number }; Returns: unknown }
        | {
            Args: { box: unknown; dx: number; dy: number; dz?: number }
            Returns: unknown
          }
        | {
            Args: {
              dm?: number
              dx: number
              dy: number
              dz?: number
              geom: unknown
            }
            Returns: unknown
          }
      st_force3d: { Args: { geom: unknown; zvalue?: number }; Returns: unknown }
      st_force3dm: {
        Args: { geom: unknown; mvalue?: number }
        Returns: unknown
      }
      st_force3dz: {
        Args: { geom: unknown; zvalue?: number }
        Returns: unknown
      }
      st_force4d: {
        Args: { geom: unknown; mvalue?: number; zvalue?: number }
        Returns: unknown
      }
      st_generatepoints:
        | { Args: { area: unknown; npoints: number }; Returns: unknown }
        | {
            Args: { area: unknown; npoints: number; seed: number }
            Returns: unknown
          }
      st_geogfromtext: { Args: { "": string }; Returns: unknown }
      st_geographyfromtext: { Args: { "": string }; Returns: unknown }
      st_geohash:
        | { Args: { geog: unknown; maxchars?: number }; Returns: string }
        | { Args: { geom: unknown; maxchars?: number }; Returns: string }
      st_geomcollfromtext: { Args: { "": string }; Returns: unknown }
      st_geometricmedian: {
        Args: {
          fail_if_not_converged?: boolean
          g: unknown
          max_iter?: number
          tolerance?: number
        }
        Returns: unknown
      }
      st_geometryfromtext: { Args: { "": string }; Returns: unknown }
      st_geomfromewkt: { Args: { "": string }; Returns: unknown }
      st_geomfromgeojson:
        | { Args: { "": Json }; Returns: unknown }
        | { Args: { "": Json }; Returns: unknown }
        | { Args: { "": string }; Returns: unknown }
      st_geomfromgml: { Args: { "": string }; Returns: unknown }
      st_geomfromkml: { Args: { "": string }; Returns: unknown }
      st_geomfrommarc21: { Args: { marc21xml: string }; Returns: unknown }
      st_geomfromtext: { Args: { "": string }; Returns: unknown }
      st_gmltosql: { Args: { "": string }; Returns: unknown }
      st_hasarc: { Args: { geometry: unknown }; Returns: boolean }
      st_hausdorffdistance: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: number
      }
      st_hexagon: {
        Args: { cell_i: number; cell_j: number; origin?: unknown; size: number }
        Returns: unknown
      }
      st_hexagongrid: {
        Args: { bounds: unknown; size: number }
        Returns: Record<string, unknown>[]
      }
      st_interpolatepoint: {
        Args: { line: unknown; point: unknown }
        Returns: number
      }
      st_intersection: {
        Args: { geom1: unknown; geom2: unknown; gridsize?: number }
        Returns: unknown
      }
      st_intersects:
        | { Args: { geog1: unknown; geog2: unknown }; Returns: boolean }
        | { Args: { geom1: unknown; geom2: unknown }; Returns: boolean }
      st_isvaliddetail: {
        Args: { flags?: number; geom: unknown }
        Returns: Database["public"]["CompositeTypes"]["valid_detail"]
        SetofOptions: {
          from: "*"
          to: "valid_detail"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      st_length:
        | { Args: { geog: unknown; use_spheroid?: boolean }; Returns: number }
        | { Args: { "": string }; Returns: number }
      st_letters: { Args: { font?: Json; letters: string }; Returns: unknown }
      st_linecrossingdirection: {
        Args: { line1: unknown; line2: unknown }
        Returns: number
      }
      st_linefromencodedpolyline: {
        Args: { nprecision?: number; txtin: string }
        Returns: unknown
      }
      st_linefromtext: { Args: { "": string }; Returns: unknown }
      st_linelocatepoint: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: number
      }
      st_linetocurve: { Args: { geometry: unknown }; Returns: unknown }
      st_locatealong: {
        Args: { geometry: unknown; leftrightoffset?: number; measure: number }
        Returns: unknown
      }
      st_locatebetween: {
        Args: {
          frommeasure: number
          geometry: unknown
          leftrightoffset?: number
          tomeasure: number
        }
        Returns: unknown
      }
      st_locatebetweenelevations: {
        Args: { fromelevation: number; geometry: unknown; toelevation: number }
        Returns: unknown
      }
      st_longestline: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: unknown
      }
      st_makebox2d: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: unknown
      }
      st_makeline: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: unknown
      }
      st_makevalid: {
        Args: { geom: unknown; params: string }
        Returns: unknown
      }
      st_maxdistance: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: number
      }
      st_minimumboundingcircle: {
        Args: { inputgeom: unknown; segs_per_quarter?: number }
        Returns: unknown
      }
      st_mlinefromtext: { Args: { "": string }; Returns: unknown }
      st_mpointfromtext: { Args: { "": string }; Returns: unknown }
      st_mpolyfromtext: { Args: { "": string }; Returns: unknown }
      st_multilinestringfromtext: { Args: { "": string }; Returns: unknown }
      st_multipointfromtext: { Args: { "": string }; Returns: unknown }
      st_multipolygonfromtext: { Args: { "": string }; Returns: unknown }
      st_node: { Args: { g: unknown }; Returns: unknown }
      st_normalize: { Args: { geom: unknown }; Returns: unknown }
      st_offsetcurve: {
        Args: { distance: number; line: unknown; params?: string }
        Returns: unknown
      }
      st_orderingequals: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      st_overlaps: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      st_perimeter: {
        Args: { geog: unknown; use_spheroid?: boolean }
        Returns: number
      }
      st_pointfromtext: { Args: { "": string }; Returns: unknown }
      st_pointm: {
        Args: {
          mcoordinate: number
          srid?: number
          xcoordinate: number
          ycoordinate: number
        }
        Returns: unknown
      }
      st_pointz: {
        Args: {
          srid?: number
          xcoordinate: number
          ycoordinate: number
          zcoordinate: number
        }
        Returns: unknown
      }
      st_pointzm: {
        Args: {
          mcoordinate: number
          srid?: number
          xcoordinate: number
          ycoordinate: number
          zcoordinate: number
        }
        Returns: unknown
      }
      st_polyfromtext: { Args: { "": string }; Returns: unknown }
      st_polygonfromtext: { Args: { "": string }; Returns: unknown }
      st_project: {
        Args: { azimuth: number; distance: number; geog: unknown }
        Returns: unknown
      }
      st_quantizecoordinates: {
        Args: {
          g: unknown
          prec_m?: number
          prec_x: number
          prec_y?: number
          prec_z?: number
        }
        Returns: unknown
      }
      st_reduceprecision: {
        Args: { geom: unknown; gridsize: number }
        Returns: unknown
      }
      st_relate: { Args: { geom1: unknown; geom2: unknown }; Returns: string }
      st_removerepeatedpoints: {
        Args: { geom: unknown; tolerance?: number }
        Returns: unknown
      }
      st_segmentize: {
        Args: { geog: unknown; max_segment_length: number }
        Returns: unknown
      }
      st_setsrid:
        | { Args: { geog: unknown; srid: number }; Returns: unknown }
        | { Args: { geom: unknown; srid: number }; Returns: unknown }
      st_sharedpaths: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: unknown
      }
      st_shortestline: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: unknown
      }
      st_simplifypolygonhull: {
        Args: { geom: unknown; is_outer?: boolean; vertex_fraction: number }
        Returns: unknown
      }
      st_split: { Args: { geom1: unknown; geom2: unknown }; Returns: unknown }
      st_square: {
        Args: { cell_i: number; cell_j: number; origin?: unknown; size: number }
        Returns: unknown
      }
      st_squaregrid: {
        Args: { bounds: unknown; size: number }
        Returns: Record<string, unknown>[]
      }
      st_srid:
        | { Args: { geog: unknown }; Returns: number }
        | { Args: { geom: unknown }; Returns: number }
      st_subdivide: {
        Args: { geom: unknown; gridsize?: number; maxvertices?: number }
        Returns: unknown[]
      }
      st_swapordinates: {
        Args: { geom: unknown; ords: unknown }
        Returns: unknown
      }
      st_symdifference: {
        Args: { geom1: unknown; geom2: unknown; gridsize?: number }
        Returns: unknown
      }
      st_symmetricdifference: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: unknown
      }
      st_tileenvelope: {
        Args: {
          bounds?: unknown
          margin?: number
          x: number
          y: number
          zoom: number
        }
        Returns: unknown
      }
      st_touches: { Args: { geom1: unknown; geom2: unknown }; Returns: boolean }
      st_transform:
        | {
            Args: { from_proj: string; geom: unknown; to_proj: string }
            Returns: unknown
          }
        | {
            Args: { from_proj: string; geom: unknown; to_srid: number }
            Returns: unknown
          }
        | { Args: { geom: unknown; to_proj: string }; Returns: unknown }
      st_triangulatepolygon: { Args: { g1: unknown }; Returns: unknown }
      st_union:
        | { Args: { geom1: unknown; geom2: unknown }; Returns: unknown }
        | {
            Args: { geom1: unknown; geom2: unknown; gridsize: number }
            Returns: unknown
          }
      st_voronoilines: {
        Args: { extend_to?: unknown; g1: unknown; tolerance?: number }
        Returns: unknown
      }
      st_voronoipolygons: {
        Args: { extend_to?: unknown; g1: unknown; tolerance?: number }
        Returns: unknown
      }
      st_within: { Args: { geom1: unknown; geom2: unknown }; Returns: boolean }
      st_wkbtosql: { Args: { wkb: string }; Returns: unknown }
      st_wkttosql: { Args: { "": string }; Returns: unknown }
      st_wrapx: {
        Args: { geom: unknown; move: number; wrap: number }
        Returns: unknown
      }
      submit_sport_level_endorsement: {
        Args: {
          p_activity_id: string
          p_is_confirmation: boolean
          p_sport_key: string
          p_target_id: string
        }
        Returns: undefined
      }
      transition_activity_status: { Args: never; Returns: undefined }
      transition_single_activity: {
        Args: { p_activity_id: string }
        Returns: string
      }
      transition_statuses_only: { Args: never; Returns: undefined }
      unlockrows: { Args: { "": string }; Returns: number }
      update_activity: {
        Args: {
          p_activity_id: string
          p_description?: string
          p_duration?: string
          p_level?: string
          p_max_participants?: number
          p_meeting_lat?: number
          p_meeting_lng?: number
          p_start_lat?: number
          p_start_lng?: number
          p_starts_at?: string
          p_title?: string
          p_visibility?: string
        }
        Returns: undefined
      }
      update_activity_trace: {
        Args: { p_activity_id: string; p_trace_geojson: Json }
        Returns: undefined
      }
      updategeometrysrid: {
        Args: {
          catalogn_name: string
          column_name: string
          new_srid_in: number
          schema_name: string
          table_name: string
        }
        Returns: string
      }
      waive_late_cancel_penalty: {
        Args: { p_participation_id: string }
        Returns: undefined
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      geometry_dump: {
        path: number[] | null
        geom: unknown
      }
      valid_detail: {
        valid: boolean | null
        reason: string | null
        location: unknown
      }
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  graphql_public: {
    Enums: {},
  },
  public: {
    Enums: {},
  },
} as const
