-- Migration: home_school_menus
-- Date: 2026-03-31
-- Request: from 003/app via board message d395afd6
-- Description: School menu import table for family members (children)

CREATE TABLE home_school_menus (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id UUID NOT NULL REFERENCES home_families(id) ON DELETE CASCADE,
  member_id UUID NOT NULL REFERENCES home_family_members(id) ON DELETE CASCADE,
  week_start DATE NOT NULL,
  day_of_week INTEGER NOT NULL CHECK (day_of_week BETWEEN 0 AND 4),
  dish_name TEXT NOT NULL,
  dish_details TEXT,
  source TEXT NOT NULL DEFAULT 'manual' CHECK (source IN ('manual', 'scraper')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(family_id, member_id, week_start, day_of_week)
);

ALTER TABLE home_school_menus ENABLE ROW LEVEL SECURITY;

-- RLS: same family-based pattern as other home_* tables
CREATE POLICY "Users can view school menus"
  ON home_school_menus FOR SELECT TO authenticated
  USING (family_id = home_get_my_family_id());

CREATE POLICY "Users can manage school menus"
  ON home_school_menus FOR ALL TO authenticated
  USING (family_id = home_get_my_family_id());

-- Grants
GRANT SELECT, INSERT, UPDATE, DELETE ON home_school_menus TO authenticated;
