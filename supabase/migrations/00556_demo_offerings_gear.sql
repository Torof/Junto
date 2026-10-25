-- ============================================================================
-- 00556 — Matériel des quatre offres démo (Scott 2026-10-25 : « sur une page
-- de sortie pro on avait parlé de mettre le matériel, je ne le vois pas »).
-- La section existe sur la fiche ; aucune offre n'avait de matériel renseigné.
-- Données de démonstration uniquement (is_demo), derrière le rideau démo.
-- ============================================================================

DO $$
BEGIN
  PERFORM set_config('junto.bypass_lock', 'true', true);

  UPDATE public.pro_offerings SET
    equipment_provided = '["Combinaison néoprène 5 mm", "Casque", "Baudrier et longe", "Navette retour"]'::jsonb,
    equipment_required = '["Maillot de bain", "Baskets qui vont dans l''eau", "Serviette", "Pique-nique"]'::jsonb
  WHERE id = 'b0000000-0000-4000-a000-000000000001' AND is_demo;

  UPDATE public.pro_offerings SET
    equipment_provided = '["Combinaison néoprène 5 mm", "Casque", "Baudrier et longe", "Sac étanche"]'::jsonb,
    equipment_required = '["Maillot de bain", "Chaussures de canyon ou baskets", "Serviette", "Encas et eau"]'::jsonb
  WHERE id = 'b0000000-0000-4000-a000-000000000002' AND is_demo;

  UPDATE public.pro_offerings SET
    equipment_provided = '["Sellette et casque", "Coupe-vent", "Vidéo du vol (en option)"]'::jsonb,
    equipment_required = '["Chaussures montantes", "Pantalon long", "Lunettes de soleil"]'::jsonb
  WHERE id = 'b0000000-0000-4000-a000-000000000003' AND is_demo;

  UPDATE public.pro_offerings SET
    equipment_provided = '["Combinaison néoprène", "Gilet et casque", "Pagaie", "Navette"]'::jsonb,
    equipment_required = '["Maillot de bain", "Baskets qui vont dans l''eau", "Serviette"]'::jsonb
  WHERE id = 'b0000000-0000-4000-a000-000000000004' AND is_demo;

  PERFORM set_config('junto.bypass_lock', 'false', true);
END $$;
