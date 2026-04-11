-- 20260411200000_home_shopping_items_proposal_fields.sql
-- Spesa redesign — add `from_menu` flag and `status` column for Evaristo proposals.
--
-- Trigger: app session 2026-04-11, board msg 1d446e8c (app -> dba). Sprint
-- "redesign Spesa" (GTD 3609d4e1). Nuovo flusso:
--   1) "Genera spesa" non scrive piu' direttamente nella lista. Crea un GTD
--      item per Evaristo (assistant), che processa il task e pusha gli
--      ingredienti calcolati come item con `status='proposed'`.
--   2) La pagina Spesa mostra una sotto-sezione "Proposta di Evaristo" con gli
--      item proposti. L'utente puo' confermare singolarmente, modificare
--      quantita', rimuovere, oppure "Importare tutto" (bulk
--      `UPDATE ... SET status='active' WHERE status='proposed'`).
--   3) Gli item provenienti dal menu settimanale ricevono `from_menu=true` per
--      mostrare un indicatore visivo che li distingue dagli item aggiunti a
--      mano.
--
-- Decisione: due colonne nuove, niente tabella separata. La pagina spesa fa
-- gia' query su `home_shopping_items` con filtro `list_id`; tenere proposed e
-- active nella stessa tabella permette di riusare le RLS policy esistenti
-- senza duplicazione e di fare bulk import con un singolo UPDATE.
--
-- RLS: invariato. Le policy esistenti (D-001, migration 20260330110000)
-- filtrano via `list_id IN (SELECT id FROM home_shopping_lists WHERE
-- family_id = home_get_my_family_id())`. Non dipendono dalle nuove colonne,
-- quindi sono automaticamente family-scoped sia per item active che proposed.
-- Verificato anche che `home_shopping_lists` ha la stessa policy di scoping
-- via family_id, quindi un membro famiglia A non puo' iniettare proposed
-- items in liste della famiglia B.
--
-- Indice: `(list_id, status)` per velocizzare le query split-view (la pagina
-- Spesa fa due fetch contigui sullo stesso list_id, uno per active e uno per
-- proposed). Non serve un indice piu' largo perche' product_name/category_id
-- non sono filtri primari.

BEGIN;

ALTER TABLE home_shopping_items
  ADD COLUMN from_menu BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN status TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'proposed'));

CREATE INDEX idx_home_shopping_items_list_status
  ON home_shopping_items (list_id, status);

COMMENT ON COLUMN home_shopping_items.from_menu IS
  'true se l''item proviene dal menu settimanale (mostrato con icona dedicata in UI). Vedi D-030.';

COMMENT ON COLUMN home_shopping_items.status IS
  '''active'' = item nella lista spesa principale; ''proposed'' = item proposto da Evaristo, in attesa di review utente nella sotto-sezione "Proposta di Evaristo". Vedi D-030.';

COMMIT;
