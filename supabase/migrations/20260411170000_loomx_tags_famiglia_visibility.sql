-- 20260411170000_loomx_tags_famiglia_visibility.sql
-- D-027 — Tag 'famiglia' come visibilità di gruppo sulla famiglia Barban.
--
-- Contesto:
--   loomx_tags / loomx_item_tags esistono già (id, name UNIQUE, color / item_id+tag_id PK)
--   con RLS abilitato ma senza policy → oggi nessun utente authenticated può
--   leggere o scrivere tag.
--
-- Obiettivi:
--   1. Marcare in `loomx_owner_auth` i membri della famiglia Barban (Achille, Vanessa).
--   2. Introdurre un tag 'famiglia' che, applicato a un item GTD, lo rende
--      visibile (SELECT) a tutti i family member, **indipendentemente dall'owner**.
--   3. Mantenere la regola: i ruoli/agenti consulting NON devono vedere gli
--      item taggati famiglia (sono utenti diversi dai family member, niente
--      accesso via questa policy).
--
-- Modello:
--   - `loomx_owner_auth.is_family BOOLEAN` (default false). Marcato true su
--     achille + vanessa.
--   - Funzioni SECURITY DEFINER:
--       loomx_is_family_member()              → bool, è family member?
--       loomx_item_has_family_tag(uuid)       → bool, l'item ha il tag famiglia?
--     Sono SECURITY DEFINER per bypassare la RLS di loomx_item_tags / loomx_tags
--     ed evitare ricorsione fra policy (stesso pattern di D-026).
--   - Nuova policy permissiva su loomx_items: SELECT consentita anche se
--     l'item è taggato 'famiglia' E l'utente è family member. Si OR-somma
--     alle policy esistenti (PMO / owner / co-engaged) senza toccarle.
--   - Policy di base su loomx_tags / loomx_item_tags: lettura per tutti gli
--     authenticated (i tag sono dimensione condivisa), write riservata a PMO
--     e all'owner dell'item per i pin item↔tag.
--   - Seed: tag 'famiglia' (idempotente).

BEGIN;

-- ============================================================
-- 1. is_family su loomx_owner_auth
-- ============================================================

ALTER TABLE public.loomx_owner_auth
  ADD COLUMN IF NOT EXISTS is_family BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN public.loomx_owner_auth.is_family IS
  'True per i membri della famiglia Barban. Abilita la visibilità sui GTD items '
  'taggati ''famiglia'' (vedi loomx_is_family_member / D-027).';

UPDATE public.loomx_owner_auth
   SET is_family = true
 WHERE owner_slug IN ('achille', 'vanessa');

-- ============================================================
-- 2. Helper SECURITY DEFINER
-- ============================================================

CREATE OR REPLACE FUNCTION public.loomx_is_family_member()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT COALESCE(
    (SELECT is_family FROM loomx_owner_auth WHERE user_id = auth.uid()),
    false
  )
$$;

COMMENT ON FUNCTION public.loomx_is_family_member() IS
  'SECURITY DEFINER: true se l''utente corrente è marcato is_family su loomx_owner_auth. '
  'Usata dalle policy per concedere visibilità sui GTD items taggati ''famiglia''.';

CREATE OR REPLACE FUNCTION public.loomx_item_has_family_tag(p_item_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
      FROM loomx_item_tags it
      JOIN loomx_tags t ON t.id = it.tag_id
     WHERE it.item_id = p_item_id
       AND t.name = 'famiglia'
  )
$$;

COMMENT ON FUNCTION public.loomx_item_has_family_tag(uuid) IS
  'SECURITY DEFINER: true se l''item ha il tag ''famiglia''. Bypassa la RLS di '
  'loomx_item_tags / loomx_tags per evitare ricorsione fra policy.';

GRANT EXECUTE ON FUNCTION public.loomx_is_family_member()             TO authenticated;
GRANT EXECUTE ON FUNCTION public.loomx_item_has_family_tag(uuid)      TO authenticated;

-- ============================================================
-- 3. Seed tag 'famiglia'
-- ============================================================

INSERT INTO public.loomx_tags (name, color)
VALUES ('famiglia', '#e91e63')
ON CONFLICT (name) DO NOTHING;

-- ============================================================
-- 4. Policy permissiva su loomx_items per family + tag famiglia
-- ============================================================

DROP POLICY IF EXISTS loomx_items_select_family_tag ON public.loomx_items;
CREATE POLICY loomx_items_select_family_tag
  ON public.loomx_items
  FOR SELECT
  TO authenticated
  USING (
    loomx_is_family_member()
    AND loomx_item_has_family_tag(id)
  );

COMMENT ON POLICY loomx_items_select_family_tag ON public.loomx_items IS
  'D-027 — visibilità di gruppo: i family member (loomx_owner_auth.is_family) '
  'vedono ogni item taggato ''famiglia'', indipendentemente dall''owner. '
  'Si OR-somma alle policy PMO / owner / co-engaged.';

-- ============================================================
-- 5. Policy minimal su loomx_tags
-- ============================================================
-- I tag sono dimensione condivisa: ogni authenticated li può leggere
-- (necessario per renderizzare label, autocomplete, ecc.).
-- Solo PMO può creare/modificare/eliminare tag globali.

DROP POLICY IF EXISTS loomx_tags_select_authenticated ON public.loomx_tags;
CREATE POLICY loomx_tags_select_authenticated
  ON public.loomx_tags
  FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS loomx_tags_insert_pmo ON public.loomx_tags;
CREATE POLICY loomx_tags_insert_pmo
  ON public.loomx_tags
  FOR INSERT
  TO authenticated
  WITH CHECK (loomx_is_pmo());

DROP POLICY IF EXISTS loomx_tags_update_pmo ON public.loomx_tags;
CREATE POLICY loomx_tags_update_pmo
  ON public.loomx_tags
  FOR UPDATE
  TO authenticated
  USING (loomx_is_pmo())
  WITH CHECK (loomx_is_pmo());

DROP POLICY IF EXISTS loomx_tags_delete_pmo ON public.loomx_tags;
CREATE POLICY loomx_tags_delete_pmo
  ON public.loomx_tags
  FOR DELETE
  TO authenticated
  USING (loomx_is_pmo());

-- ============================================================
-- 6. Policy minimal su loomx_item_tags
-- ============================================================
-- SELECT: chi può vedere l'item può vederne i tag (la sub-policy su loomx_items
--   già applica le regole authenticated, incluso il nuovo bypass family).
-- INSERT/DELETE: PMO o owner dell'item.
-- UPDATE: la PK è (item_id, tag_id), non ci sono colonne mutevoli → no UPDATE policy.

DROP POLICY IF EXISTS loomx_item_tags_select_authenticated ON public.loomx_item_tags;
CREATE POLICY loomx_item_tags_select_authenticated
  ON public.loomx_item_tags
  FOR SELECT
  TO authenticated
  USING (
    loomx_is_pmo()
    OR loomx_item_owner(item_id) = loomx_get_owner_slug()
    OR loomx_user_engaged_role(item_id) IS NOT NULL
    OR (loomx_is_family_member() AND loomx_item_has_family_tag(item_id))
  );

DROP POLICY IF EXISTS loomx_item_tags_insert_authenticated ON public.loomx_item_tags;
CREATE POLICY loomx_item_tags_insert_authenticated
  ON public.loomx_item_tags
  FOR INSERT
  TO authenticated
  WITH CHECK (
    loomx_is_pmo()
    OR loomx_item_owner(item_id) = loomx_get_owner_slug()
  );

DROP POLICY IF EXISTS loomx_item_tags_delete_authenticated ON public.loomx_item_tags;
CREATE POLICY loomx_item_tags_delete_authenticated
  ON public.loomx_item_tags
  FOR DELETE
  TO authenticated
  USING (
    loomx_is_pmo()
    OR loomx_item_owner(item_id) = loomx_get_owner_slug()
  );

COMMIT;
