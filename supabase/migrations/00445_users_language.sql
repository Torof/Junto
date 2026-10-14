-- ============================================================================
-- 00445 — users.language : la langue EFFECTIVE de l'utilisateur (fondation
-- multilingue, go Scott 2026-10-14).
--
-- Le serveur ne connaissait pas la langue de personne : les 41 types de
-- notifications sont rédigés en français dans les fonctions SQL et la push
-- les relaie telles quelles. Première brique : l'app écrit ici la langue
-- qu'elle affiche réellement (choix explicite de l'utilisateur, sinon langue
-- de l'appareil ramenée aux langues supportées). La préférence « automatique »
-- vs « choisie » reste locale au téléphone — le serveur n'a besoin que du
-- résultat.
--
-- Colonne NON privilégiée : même statut que notification_preferences, c'est
-- l'utilisateur qui choisit sa propre langue. Le trigger handle_user_update
-- (live 00333) force une LISTE de colonnes à OLD ; `language` n'y figure pas,
-- donc l'UPDATE own-row direct passe — voulu. CHECK fermé sur les 5 langues
-- prévues (fr live, en échafaudage, it/es/de à venir) : élargir par migration.
-- Valeur par défaut 'fr' (launch language) pour l'existant et les comptes
-- créés avant que l'app n'ait synchronisé.
-- ============================================================================

ALTER TABLE users
  ADD COLUMN language TEXT NOT NULL DEFAULT 'fr'
  CHECK (language IN ('fr', 'en', 'it', 'es', 'de'));

COMMENT ON COLUMN users.language IS
  'Langue effective affichée par l''app (écrite par le client). Servira à composer les notifications dans la langue du destinataire.';
