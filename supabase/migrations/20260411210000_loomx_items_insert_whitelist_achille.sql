-- 20260411210000_loomx_items_insert_whitelist_achille.sql
-- Estende la whitelist INSERT non-PMO su loomx_items per includere 'achille'.
--
-- Trigger: gap rilevato in D-029 (migration 20260411190000). La whitelist
-- attuale `('loomy', 'assistant')` consente ai non-PMO (es. Vanessa) di
-- inviare capture solo agli inbox di agente. Manca il caso "Vanessa manda un
-- promemoria/capture ad Achille": entrambi sono utenti familiari, e il flusso
-- di capture cross-utente intra-famiglia e' un caso d'uso esplicito della UI
-- "Capture con Destinatario".
--
-- Decisione: amendment a D-029 -> D-030. Aggiungere 'achille' alla whitelist
-- letterale. Rimane consistente con il rationale di D-029 (whitelist piccola
-- nella policy invece di colonna `can_be_target_by_anyone`): oggi il set di
-- "destinatari ricevibili da chiunque" e' ancora <= 4 elementi.
--
-- Threat model aggiornato. Vanessa (non-PMO) puo' creare item destinati a
-- {loomy, assistant, achille}. NON puo' creare item destinati a `dba`,
-- `app`, `librarian` o ad altri utenti umani futuri (Azzurra, etc.). La
-- restrizione resta significativa: la capture cross-owner e' aperta solo a
-- inbox dispatcher + Achille (capofamiglia / PMO). Nessun rischio di scrittura
-- cross-family perche' Vanessa e Achille appartengono alla stessa
-- `loomx_owner_auth.is_family = true`.
--
-- Edit/delete invariati: una volta scritto un item destinato ad Achille,
-- Vanessa non puo' modificarlo o cancellarlo (D-025 — UPDATE/DELETE
-- consentiti solo a PMO o all'owner stesso). Achille processa la capture
-- come se fosse arrivata da qualunque altro canale.
--
-- Quando promuovere a colonna: se compare un quarto destinatario non-PMO
-- (es. Azzurra che diventa capture target), valutare se l'invariante
-- "destinatario human-friendly" merita una colonna `can_be_target_by_anyone`
-- su loomx_owner_auth invece di continuare ad allargare la whitelist.

BEGIN;

DROP POLICY IF EXISTS loomx_items_insert_authenticated ON loomx_items;
CREATE POLICY loomx_items_insert_authenticated
  ON loomx_items FOR INSERT TO authenticated
  WITH CHECK (
    loomx_is_pmo()
    OR owner = loomx_get_owner_slug()
    OR owner IN ('loomy', 'assistant', 'achille')
  );

COMMIT;
