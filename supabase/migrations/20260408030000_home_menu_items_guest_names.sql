-- 20260408030000_home_menu_items_guest_names.sql
-- Sprint 007 — multi-row pasti + ospiti.
-- Add guest_names text[] to home_menu_items to track free-text guest names
-- alongside member_ids[] (family members). RLS unchanged: row-level access
-- already enforced via FK to home_weekly_menus → family_id.

BEGIN;

ALTER TABLE public.home_menu_items
  ADD COLUMN IF NOT EXISTS guest_names text[] NOT NULL DEFAULT '{}';

COMMIT;
