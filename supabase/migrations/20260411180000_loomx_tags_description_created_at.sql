-- 20260411180000_loomx_tags_description_created_at.sql
-- D-028 — Allinea schema loomx_tags al contratto richiesto da Achille:
-- aggiunge `description TEXT` (nullable) e `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`.
--
-- Contesto:
--   loomx_tags esiste dal 20260405100000 con (id, name, color). Achille ha
--   chiesto esplicitamente description + created_at per uniformare il modello
--   con gli altri dimension table loomx_*. `color` resta perché già usato
--   dall'UI GTD per il rendering chip.
--
-- Idempotente via IF NOT EXISTS / DEFAULT.

BEGIN;

ALTER TABLE public.loomx_tags
  ADD COLUMN IF NOT EXISTS description TEXT;

ALTER TABLE public.loomx_tags
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT now();

COMMENT ON COLUMN public.loomx_tags.description IS
  'Descrizione human-readable opzionale del tag (semantica, regole d''uso).';

COMMENT ON COLUMN public.loomx_tags.created_at IS
  'Timestamp di creazione del tag. Default now().';

-- Documenta la semantica del tag famiglia, ora che description esiste.
UPDATE public.loomx_tags
   SET description = 'Visibilità di gruppo: ogni item con questo tag è visibile a tutti i family member (loomx_owner_auth.is_family). Vedi D-027.'
 WHERE name = 'famiglia'
   AND description IS NULL;

COMMIT;
