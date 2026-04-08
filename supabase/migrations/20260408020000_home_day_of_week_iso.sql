-- 20260408020000_home_day_of_week_iso.sql
-- Sprint 005 hotfix — align day_of_week constraints to ISO 1..7 convention.
--
-- Background: home_school_menus had CHECK (day_of_week BETWEEN 0 AND 4) and
-- home_menu_items had CHECK (day_of_week BETWEEN 0 AND 6). The new RPCs from
-- migration 20260408010000 (home_school_menu_sync, home_school_menu_toggle_exclusion)
-- use ISO day-of-week 1..7 (1=Mon..7=Sun), matching EXTRACT(ISODOW FROM date).
--
-- Both tables are empty at apply-time (verified S014), so the constraint
-- swap is data-safe.
--
-- After this migration the convention is:
--   1 = Monday, 2 = Tuesday, ..., 7 = Sunday
--
-- App must adapt any frontend code generating day_of_week values (typical
-- JS Date.getDay() returns 0=Sun..6=Sat — needs normalization).

BEGIN;

ALTER TABLE public.home_school_menus
  DROP CONSTRAINT IF EXISTS home_school_menus_day_of_week_check;

ALTER TABLE public.home_school_menus
  ADD  CONSTRAINT home_school_menus_day_of_week_check
       CHECK (day_of_week BETWEEN 1 AND 7);

ALTER TABLE public.home_menu_items
  DROP CONSTRAINT IF EXISTS home_menu_items_day_of_week_check;

ALTER TABLE public.home_menu_items
  ADD  CONSTRAINT home_menu_items_day_of_week_check
       CHECK (day_of_week BETWEEN 1 AND 7);

COMMIT;
