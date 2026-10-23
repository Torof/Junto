-- 00548 — the demo carpools get their departure village.
--
-- Since 00521 the members of an outing who are not a driver's passengers, and
-- the carpool summary every viewer sees, show the driver's VILLAGE
-- (participations.transport_from_locality, reverse-geocoded by the app at
-- save time) — never the typed start. The demo carpools were written before
-- that rule and never got a village, so their starts showed nowhere (Scott
-- 2026-10-23: « on ne voit pas d'où vient la personne »).
--
-- Their typed starts are commune names already (Gap, Briançon, Embrun…), so
-- the village is that name. Demo rows only; real rows are filled by the app.

UPDATE public.participations p
SET transport_from_locality = left(trim(p.transport_from_name), 80)
FROM public.activities a
WHERE a.id = p.activity_id
  AND a.is_demo
  AND p.transport_from_name IS NOT NULL
  AND p.transport_from_locality IS NULL;
