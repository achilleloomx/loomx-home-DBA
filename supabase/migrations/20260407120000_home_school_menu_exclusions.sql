-- Migration: home_school_menu_exclusions
-- Date: 2026-04-07
-- Request: 003/app via board message 6b3b2a38 (sprint 005, scraper Azzurra)
-- Description: Days to exclude from school menu scraping/import
--   (festività, malattia, gita, libero). Scraper skips these dates;
--   UI can mark/unmark a day.

CREATE TABLE home_school_menu_exclusions (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id   UUID NOT NULL REFERENCES home_families(id) ON DELETE CASCADE,
  member_id   UUID NOT NULL REFERENCES home_family_members(id) ON DELETE CASCADE,
  date        DATE NOT NULL,
  reason      TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (family_id, member_id, date)
);

CREATE INDEX home_school_menu_exclusions_family_date_idx
  ON home_school_menu_exclusions (family_id, date);

ALTER TABLE home_school_menu_exclusions ENABLE ROW LEVEL SECURITY;

-- RLS: family-based, same pattern as the rest of home_*
CREATE POLICY "Users can view school menu exclusions"
  ON home_school_menu_exclusions FOR SELECT TO authenticated
  USING (family_id = home_get_my_family_id());

CREATE POLICY "Users can manage school menu exclusions"
  ON home_school_menu_exclusions FOR ALL TO authenticated
  USING (family_id = home_get_my_family_id())
  WITH CHECK (family_id = home_get_my_family_id());

GRANT SELECT, INSERT, UPDATE, DELETE ON home_school_menu_exclusions TO authenticated;
