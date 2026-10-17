import type { OfferRow, OutingRow } from './data';

// Illustrative content for the launch window (Scott 2026-10-17: « 5 ou 6
// activités et professionnels faux pour avoir de la donnée sur le site »).
// Shown only while the real anonymous reads come back short (see page.tsx);
// once outings and pros exist, the page becomes fully dynamic by itself.
// Rows carry `mock: true` so the UI never links them to a detail page.

function at(daysAhead: number, hour: number, minute = 0): string {
  const d = new Date();
  d.setDate(d.getDate() + daysAhead);
  d.setHours(hour, minute, 0, 0);
  return d.toISOString();
}

function ago(hours: number): string {
  return new Date(Date.now() - hours * 3600 * 1000).toISOString();
}

export function mockOutings(): OutingRow[] {
  return [
    { id: 'mock-1', mock: true, title: "Rando à la Croix d'Aquila", starts_at: at(1, 9), created_at: ago(6), level: 'intermédiaire', level_max: null, distance_km: 14, elevation_gain_m: 700, max_participants: 8, participant_count: 3, sport_key: 'hiking', sport_category: 'on-foot', meeting_name: 'Parking de la ferme', meeting_locality: 'Puy-Chalvin', creator_name: 'Marie L.' },
    { id: 'mock-2', mock: true, title: 'Gravel autour de Serre-Ponçon', starts_at: at(1, 8, 30), created_at: ago(30), level: 'intermédiaire', level_max: null, distance_km: 70, elevation_gain_m: 900, max_participants: 8, participant_count: 3, sport_key: 'gravel', sport_category: 'cycling', meeting_name: 'Plan d’eau', meeting_locality: 'Embrun', creator_name: 'Nadia K.' },
    { id: 'mock-3', mock: true, title: 'Grimpe au Rocher Baron', starts_at: at(1, 14), created_at: ago(70), level: '5c', level_max: '6c', distance_km: null, elevation_gain_m: null, max_participants: 4, participant_count: 4, sport_key: 'climbing-sport', sport_category: 'mountain', meeting_name: 'Parking de la falaise', meeting_locality: 'Villar-Saint-Pancrace', creator_name: 'Thomas B.' },
    { id: 'mock-4', mock: true, title: 'Arête de la Blanche', starts_at: at(2, 7, 30), created_at: ago(100), level: 'PD', level_max: null, distance_km: null, elevation_gain_m: 1100, max_participants: 4, participant_count: 3, sport_key: 'mountaineering', sport_category: 'mountain', meeting_name: 'Parking de Vallouise', meeting_locality: 'Vallouise', creator_name: 'Julie R.' },
    { id: 'mock-5', mock: true, title: 'Vol du matin, décollage du Prorel', starts_at: at(2, 8, 30), created_at: ago(20), level: 'pilote autonome', level_max: null, distance_km: null, elevation_gain_m: null, max_participants: 6, participant_count: 4, sport_key: 'paragliding', sport_category: 'air', meeting_name: 'Télécabine du Prorel', meeting_locality: 'Briançon', creator_name: 'Karim D.' },
    { id: 'mock-6', mock: true, title: 'Enduro après le boulot', starts_at: at(5, 17, 30), created_at: ago(90), level: 'avancé', level_max: null, distance_km: 18, elevation_gain_m: null, max_participants: 6, participant_count: 2, sport_key: 'mtb-enduro', sport_category: 'cycling', meeting_name: 'Front de neige', meeting_locality: 'Montgenèvre', creator_name: 'Nadia K.' },
    { id: 'mock-7', mock: true, title: 'Ski de rando, crête de Dormillouse', starts_at: at(6, 7), created_at: ago(120), level: 'S2', level_max: null, distance_km: 11, elevation_gain_m: 950, max_participants: 5, participant_count: 4, sport_key: 'ski-touring', sport_category: 'mountain', meeting_name: 'Parking de Dormillouse', meeting_locality: 'Freissinières', creator_name: 'Léa M.' },
  ];
}

export function mockOffers(): OfferRow[] {
  return [
    { id: 'mock-o1', mock: true, pro_id: 'mock-aw', title: 'Canyon du Fournel — découverte', pro_name: 'Air & Water', location_name: "L'Argentière-la-Bessée", duration: '04:00:00', schedule_text: 'Tous les jours en saison', level: 'dès 12 ans', price_eur: 55, price_unit: 'person', sport_key: 'canyoning', sport_category: 'water' },
    { id: 'mock-o2', mock: true, pro_id: 'mock-aw', title: 'Vol biplace, décollage du Prorel', pro_name: 'Air & Water', location_name: 'Briançon', duration: '00:20:00', schedule_text: 'Tous les matins · navette comprise', level: 'découverte', price_eur: 95, price_unit: 'person', sport_key: 'paragliding', sport_category: 'air' },
    { id: 'mock-o3', mock: true, pro_id: 'mock-ve', title: 'Initiation escalade, falaise école', pro_name: 'Vertical Écrins', location_name: 'Ailefroide', duration: '04:00:00', schedule_text: 'Guides de haute montagne', level: 'débutant', price_eur: 60, price_unit: 'person', sport_key: 'climbing-sport', sport_category: 'mountain' },
    { id: 'mock-o4', mock: true, pro_id: 'mock-mg', title: 'Journée ski de rando avec un guide', pro_name: 'Marc G.', location_name: 'Arvieux, Queyras', duration: '08:00:00', schedule_text: 'Guide de haute montagne · DVA fourni', level: 'intermédiaire', price_eur: 110, price_unit: 'person', sport_key: 'ski-touring', sport_category: 'mountain' },
    { id: 'mock-o5', mock: true, pro_id: 'mock-rs', title: 'Rafting sur la Durance', pro_name: 'Rivière Sauvage', location_name: 'Saint-Clément-sur-Durance', duration: '02:00:00', schedule_text: 'Base d’eau vive · combinaison fournie', level: 'dès 8 ans', price_eur: 45, price_unit: 'person', sport_key: 'rafting', sport_category: 'water' },
    { id: 'mock-o6', mock: true, pro_id: 'mock-bs', title: 'Coaching enduro, une après-midi', pro_name: 'Bike School Montgenèvre', location_name: 'Montgenèvre', duration: '03:00:00', schedule_text: 'École de VTT · vélo non fourni', level: 'rouge et plus', price_eur: 70, price_unit: 'person', sport_key: 'mtb-enduro', sport_category: 'cycling' },
  ];
}
