-- 20260408010000_home_school_menu_sync_rpc.sql
-- Sprint 005 — App scraper menu Azzurra senza service_role.
--
-- Two SECURITY DEFINER functions callable from the `authenticated` role:
--
-- 1. home_school_menu_sync(family, member, week_start, dishes)
--    Atomic upsert of school menus + mirror rows in home_menu_items.
--
-- 2. home_school_menu_toggle_exclusion(family, member, date, reason, excluded)
--    Atomic insert/delete of exclusion + corresponding mirror cleanup/restore.
--
-- Authorization: both functions accept calls only when either
--   (a) p_family_id = home_get_my_family_id()  (normal user, own family), or
--   (b) the JWT email equals 'scraper@loomx.local' (dedicated cron user).
-- Without this guard SECURITY DEFINER would let any authenticated user write
-- arbitrary family data.
--
-- Convention: day_of_week is 1..7 with 1 = Monday. week_start is the Monday
-- of the week. The date for a (week_start, day_of_week) pair is therefore
-- week_start + (day_of_week - 1) days.
--
-- Mirror rows in home_menu_items are tagged with notes = 'school:YYYY-MM-DD'
-- so the sync can locate and remove its own previous output without touching
-- non-school rows.

BEGIN;

-- Hard-coded scraper account email — keep in sync with the Supabase Auth user
-- created via Studio. If renamed, update this constant and re-apply.
-- (Tracked in CLAUDE.md or DECISIONS.md as part of the sprint 005 setup.)

-- ============================================================================
-- 1. home_school_menu_sync
-- ============================================================================

CREATE OR REPLACE FUNCTION public.home_school_menu_sync(
  p_family_id  uuid,
  p_member_id  uuid,
  p_week_start date,
  p_dishes     jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_email text;
  v_my_family    uuid;
  v_weekly_id    uuid;
  v_dish         jsonb;
  v_dow          int;
  v_date         date;
  v_dish_name    text;
  v_dish_details text;
  v_excluded     boolean;
  v_upserted     int := 0;
  v_mirrored     int := 0;
  v_skipped      int := 0;
BEGIN
  -- 1. Authorization
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'home_school_menu_sync: unauthenticated';
  END IF;

  v_caller_email := COALESCE(auth.jwt() ->> 'email', '');

  IF v_caller_email <> 'scraper@loomx.local' THEN
    v_my_family := home_get_my_family_id();
    IF v_my_family IS NULL OR v_my_family <> p_family_id THEN
      RAISE EXCEPTION 'home_school_menu_sync: forbidden (family_id mismatch)';
    END IF;
  END IF;

  -- 2. Validate input shape
  IF p_family_id IS NULL OR p_member_id IS NULL OR p_week_start IS NULL THEN
    RAISE EXCEPTION 'home_school_menu_sync: family_id, member_id, week_start required';
  END IF;

  IF p_dishes IS NULL OR jsonb_typeof(p_dishes) <> 'array' THEN
    RAISE EXCEPTION 'home_school_menu_sync: p_dishes must be a jsonb array';
  END IF;

  -- 3. Get-or-create the weekly menu container
  INSERT INTO public.home_weekly_menus (family_id, week_start, status)
  VALUES (p_family_id, p_week_start, 'draft')
  ON CONFLICT (family_id, week_start) DO NOTHING;

  SELECT id INTO v_weekly_id
    FROM public.home_weekly_menus
   WHERE family_id = p_family_id AND week_start = p_week_start;

  -- 4. Wipe previous mirror rows for this week (school marker only)
  DELETE FROM public.home_menu_items
   WHERE menu_id = v_weekly_id
     AND notes LIKE 'school:%'
     AND substring(notes FROM 8)::date BETWEEN p_week_start AND p_week_start + 6;

  -- 5. Iterate dishes
  FOR v_dish IN SELECT * FROM jsonb_array_elements(p_dishes)
  LOOP
    v_dow          := (v_dish ->> 'day_of_week')::int;
    v_dish_name    := v_dish ->> 'dish_name';
    v_dish_details := v_dish ->> 'dish_details';

    IF v_dow IS NULL OR v_dow < 1 OR v_dow > 7 THEN
      RAISE EXCEPTION 'home_school_menu_sync: invalid day_of_week %', v_dow;
    END IF;

    IF v_dish_name IS NULL OR length(v_dish_name) = 0 THEN
      v_skipped := v_skipped + 1;
      CONTINUE;
    END IF;

    v_date := p_week_start + (v_dow - 1);

    -- 5a. Check exclusion
    SELECT EXISTS (
      SELECT 1 FROM public.home_school_menu_exclusions
       WHERE family_id = p_family_id
         AND member_id = p_member_id
         AND date      = v_date
    ) INTO v_excluded;

    IF v_excluded THEN
      v_skipped := v_skipped + 1;
      CONTINUE;
    END IF;

    -- 5b. Upsert school menu row
    INSERT INTO public.home_school_menus (
      family_id, member_id, week_start, day_of_week,
      dish_name, dish_details, source
    )
    VALUES (
      p_family_id, p_member_id, p_week_start, v_dow,
      v_dish_name, v_dish_details, 'scraper'
    )
    ON CONFLICT (family_id, member_id, week_start, day_of_week)
    DO UPDATE SET
      dish_name    = EXCLUDED.dish_name,
      dish_details = EXCLUDED.dish_details,
      source       = EXCLUDED.source;

    v_upserted := v_upserted + 1;

    -- 5c. Insert mirror row in home_menu_items
    INSERT INTO public.home_menu_items (
      menu_id, day_of_week, meal_type, dish_name,
      covered_by_school, member_ids, notes
    )
    VALUES (
      v_weekly_id, v_dow, 'lunch', v_dish_name,
      true, ARRAY[p_member_id], 'school:' || v_date::text
    );

    v_mirrored := v_mirrored + 1;
  END LOOP;

  -- 6. Touch the weekly menu updated_at
  UPDATE public.home_weekly_menus
     SET updated_at = now()
   WHERE id = v_weekly_id;

  RETURN jsonb_build_object(
    'upserted', v_upserted,
    'mirrored', v_mirrored,
    'skipped',  v_skipped,
    'weekly_menu_id', v_weekly_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.home_school_menu_sync(uuid, uuid, date, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.home_school_menu_sync(uuid, uuid, date, jsonb) TO authenticated;

COMMENT ON FUNCTION public.home_school_menu_sync(uuid, uuid, date, jsonb) IS
'Sprint 005: atomic upsert of school menus + mirror rows in home_menu_items. SECURITY DEFINER, callable by family member or by scraper@loomx.local.';

-- ============================================================================
-- 2. home_school_menu_toggle_exclusion
-- ============================================================================

CREATE OR REPLACE FUNCTION public.home_school_menu_toggle_exclusion(
  p_family_id uuid,
  p_member_id uuid,
  p_date      date,
  p_reason    text,
  p_excluded  boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_email text;
  v_my_family    uuid;
  v_week_start   date;
  v_dow          int;
  v_weekly_id    uuid;
  v_school_dish  record;
  v_action       text;
BEGIN
  -- 1. Authorization (same model as sync)
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'home_school_menu_toggle_exclusion: unauthenticated';
  END IF;

  v_caller_email := COALESCE(auth.jwt() ->> 'email', '');

  IF v_caller_email <> 'scraper@loomx.local' THEN
    v_my_family := home_get_my_family_id();
    IF v_my_family IS NULL OR v_my_family <> p_family_id THEN
      RAISE EXCEPTION 'home_school_menu_toggle_exclusion: forbidden (family_id mismatch)';
    END IF;
  END IF;

  -- 2. Compute the Monday-anchored week_start and 1..7 day_of_week
  --    extract(isodow) → 1=Mon..7=Sun, matches our convention.
  v_dow        := EXTRACT(ISODOW FROM p_date)::int;
  v_week_start := p_date - (v_dow - 1);

  -- 3. Resolve weekly_menu_id (may be NULL if no weekly menu exists yet)
  SELECT id INTO v_weekly_id
    FROM public.home_weekly_menus
   WHERE family_id = p_family_id AND week_start = v_week_start;

  IF p_excluded THEN
    -- Insert (or update reason of) the exclusion row
    INSERT INTO public.home_school_menu_exclusions (family_id, member_id, date, reason)
    VALUES (p_family_id, p_member_id, p_date, p_reason)
    ON CONFLICT (family_id, member_id, date)
    DO UPDATE SET reason = EXCLUDED.reason;

    -- Remove the mirror row if present
    IF v_weekly_id IS NOT NULL THEN
      DELETE FROM public.home_menu_items
       WHERE menu_id = v_weekly_id
         AND notes   = 'school:' || p_date::text
         AND p_member_id = ANY(member_ids);
    END IF;

    v_action := 'excluded';
  ELSE
    -- Drop the exclusion row
    DELETE FROM public.home_school_menu_exclusions
     WHERE family_id = p_family_id
       AND member_id = p_member_id
       AND date      = p_date;

    -- Restore the mirror row if a school dish exists for that date and the
    -- weekly menu container is present.
    IF v_weekly_id IS NOT NULL THEN
      SELECT dish_name, day_of_week
        INTO v_school_dish
        FROM public.home_school_menus
       WHERE family_id  = p_family_id
         AND member_id  = p_member_id
         AND week_start = v_week_start
         AND day_of_week = v_dow;

      IF v_school_dish.dish_name IS NOT NULL THEN
        -- Avoid duplicate mirror rows
        IF NOT EXISTS (
          SELECT 1 FROM public.home_menu_items
           WHERE menu_id = v_weekly_id
             AND notes   = 'school:' || p_date::text
             AND p_member_id = ANY(member_ids)
        ) THEN
          INSERT INTO public.home_menu_items (
            menu_id, day_of_week, meal_type, dish_name,
            covered_by_school, member_ids, notes
          )
          VALUES (
            v_weekly_id, v_dow, 'lunch', v_school_dish.dish_name,
            true, ARRAY[p_member_id], 'school:' || p_date::text
          );
        END IF;
      END IF;
    END IF;

    v_action := 'included';
  END IF;

  RETURN jsonb_build_object(
    'action',         v_action,
    'date',           p_date,
    'weekly_menu_id', v_weekly_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.home_school_menu_toggle_exclusion(uuid, uuid, date, text, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.home_school_menu_toggle_exclusion(uuid, uuid, date, text, boolean) TO authenticated;

COMMENT ON FUNCTION public.home_school_menu_toggle_exclusion(uuid, uuid, date, text, boolean) IS
'Sprint 005: atomic toggle of school menu exclusion + mirror row cleanup/restore. SECURITY DEFINER, callable by family member or by scraper@loomx.local.';

COMMIT;
