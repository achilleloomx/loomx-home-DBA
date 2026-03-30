-- Migration: home_* namespace — Family App schema
-- Date: 2026-03-30
-- Source: loomx-home-app/supabase/migrations/001-003 (adapted with home_ prefix)
-- Decision: D-005 — physical prefix home_ on all app tables

-- ============================================================
-- 1. Core tables
-- ============================================================

-- Families
CREATE TABLE home_families (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE home_families ENABLE ROW LEVEL SECURITY;

-- Profiles (user ↔ family link)
CREATE TABLE home_profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  family_id UUID NOT NULL REFERENCES home_families(id) ON DELETE CASCADE,
  display_name TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('admin', 'member')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id)
);

ALTER TABLE home_profiles ENABLE ROW LEVEL SECURITY;

-- Family members (people in the household, not auth users)
CREATE TABLE home_family_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id UUID NOT NULL REFERENCES home_families(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  age INTEGER NOT NULL,
  sex TEXT NOT NULL CHECK (sex IN ('M', 'F')),
  role TEXT NOT NULL DEFAULT 'adult' CHECK (role IN ('adult', 'child', 'infant')),
  dietary_notes TEXT,
  conditions TEXT[] NOT NULL DEFAULT '{}',
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE home_family_members ENABLE ROW LEVEL SECURITY;

-- Pets
CREATE TABLE home_pets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id UUID NOT NULL REFERENCES home_families(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  species TEXT NOT NULL,
  breed TEXT,
  weight_kg NUMERIC(5,2),
  diet_notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE home_pets ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 2. Shopping
-- ============================================================

-- Shopping categories
CREATE TABLE home_shopping_categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id UUID NOT NULL REFERENCES home_families(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  is_default BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE home_shopping_categories ENABLE ROW LEVEL SECURITY;

-- Shopping lists
CREATE TABLE home_shopping_lists (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id UUID NOT NULL REFERENCES home_families(id) ON DELETE CASCADE,
  name TEXT NOT NULL DEFAULT 'Lista della spesa',
  week_start DATE,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE home_shopping_lists ENABLE ROW LEVEL SECURITY;

-- Shopping items
CREATE TABLE home_shopping_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  list_id UUID NOT NULL REFERENCES home_shopping_lists(id) ON DELETE CASCADE,
  category_id UUID NOT NULL REFERENCES home_shopping_categories(id),
  product_name TEXT NOT NULL,
  quantity NUMERIC(8,2) NOT NULL DEFAULT 1,
  unit TEXT NOT NULL DEFAULT 'pz',
  notes TEXT,
  is_checked BOOLEAN NOT NULL DEFAULT false,
  checked_at TIMESTAMPTZ,
  checked_by UUID REFERENCES auth.users(id),
  added_by UUID NOT NULL REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE home_shopping_items ENABLE ROW LEVEL SECURITY;

-- Purchase history
CREATE TABLE home_purchase_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id UUID NOT NULL REFERENCES home_families(id) ON DELETE CASCADE,
  product_name TEXT NOT NULL,
  quantity NUMERIC(8,2) NOT NULL,
  unit TEXT NOT NULL DEFAULT 'pz',
  purchased_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  store TEXT,
  purchased_by UUID NOT NULL REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE home_purchase_history ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 3. Menu
-- ============================================================

-- Weekly menus
CREATE TABLE home_weekly_menus (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id UUID NOT NULL REFERENCES home_families(id) ON DELETE CASCADE,
  week_start DATE NOT NULL,
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'approved')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(family_id, week_start)
);

ALTER TABLE home_weekly_menus ENABLE ROW LEVEL SECURITY;

-- Menu items
CREATE TABLE home_menu_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  menu_id UUID NOT NULL REFERENCES home_weekly_menus(id) ON DELETE CASCADE,
  day_of_week INTEGER NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
  meal_type TEXT NOT NULL CHECK (meal_type IN ('breakfast', 'lunch', 'dinner', 'snack')),
  dish_name TEXT NOT NULL,
  ingredients JSONB,
  covered_by_school BOOLEAN NOT NULL DEFAULT false,
  member_ids UUID[] NOT NULL DEFAULT '{}',
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE home_menu_items ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 4. RLS Policies
-- ============================================================

-- Helper: get current user's family_id
CREATE OR REPLACE FUNCTION home_get_my_family_id()
RETURNS UUID AS $$
  SELECT family_id FROM home_profiles WHERE user_id = auth.uid()
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- home_families
CREATE POLICY "Users can view their own family"
  ON home_families FOR SELECT TO authenticated
  USING (id = home_get_my_family_id());

-- home_profiles
CREATE POLICY "Users can view family profiles"
  ON home_profiles FOR SELECT TO authenticated
  USING (family_id = home_get_my_family_id());

CREATE POLICY "Users can update their own profile"
  ON home_profiles FOR UPDATE TO authenticated
  USING (user_id = auth.uid());

-- home_family_members
CREATE POLICY "Users can view family members"
  ON home_family_members FOR SELECT TO authenticated
  USING (family_id = home_get_my_family_id());

CREATE POLICY "Users can insert family members"
  ON home_family_members FOR INSERT TO authenticated
  WITH CHECK (family_id = home_get_my_family_id());

CREATE POLICY "Users can update family members"
  ON home_family_members FOR UPDATE TO authenticated
  USING (family_id = home_get_my_family_id());

CREATE POLICY "Users can delete family members"
  ON home_family_members FOR DELETE TO authenticated
  USING (family_id = home_get_my_family_id());

-- home_pets
CREATE POLICY "Users can view pets"
  ON home_pets FOR SELECT TO authenticated
  USING (family_id = home_get_my_family_id());

CREATE POLICY "Users can manage pets"
  ON home_pets FOR ALL TO authenticated
  USING (family_id = home_get_my_family_id());

-- home_shopping_categories
CREATE POLICY "Users can view categories"
  ON home_shopping_categories FOR SELECT TO authenticated
  USING (family_id = home_get_my_family_id());

CREATE POLICY "Users can manage categories"
  ON home_shopping_categories FOR ALL TO authenticated
  USING (family_id = home_get_my_family_id());

-- home_shopping_lists
CREATE POLICY "Users can view lists"
  ON home_shopping_lists FOR SELECT TO authenticated
  USING (family_id = home_get_my_family_id());

CREATE POLICY "Users can manage lists"
  ON home_shopping_lists FOR ALL TO authenticated
  USING (family_id = home_get_my_family_id());

-- home_shopping_items (join through list → family)
CREATE POLICY "Users can view items"
  ON home_shopping_items FOR SELECT TO authenticated
  USING (
    list_id IN (
      SELECT id FROM home_shopping_lists WHERE family_id = home_get_my_family_id()
    )
  );

CREATE POLICY "Users can insert items"
  ON home_shopping_items FOR INSERT TO authenticated
  WITH CHECK (
    list_id IN (
      SELECT id FROM home_shopping_lists WHERE family_id = home_get_my_family_id()
    )
  );

CREATE POLICY "Users can update items"
  ON home_shopping_items FOR UPDATE TO authenticated
  USING (
    list_id IN (
      SELECT id FROM home_shopping_lists WHERE family_id = home_get_my_family_id()
    )
  );

CREATE POLICY "Users can delete items"
  ON home_shopping_items FOR DELETE TO authenticated
  USING (
    list_id IN (
      SELECT id FROM home_shopping_lists WHERE family_id = home_get_my_family_id()
    )
  );

-- home_purchase_history
CREATE POLICY "Users can view purchase history"
  ON home_purchase_history FOR SELECT TO authenticated
  USING (family_id = home_get_my_family_id());

CREATE POLICY "Users can insert purchase history"
  ON home_purchase_history FOR INSERT TO authenticated
  WITH CHECK (family_id = home_get_my_family_id());

-- home_weekly_menus
CREATE POLICY "Users can view menus"
  ON home_weekly_menus FOR SELECT TO authenticated
  USING (family_id = home_get_my_family_id());

CREATE POLICY "Users can manage menus"
  ON home_weekly_menus FOR ALL TO authenticated
  USING (family_id = home_get_my_family_id());

-- home_menu_items (join through menu → family)
CREATE POLICY "Users can view menu items"
  ON home_menu_items FOR SELECT TO authenticated
  USING (
    menu_id IN (
      SELECT id FROM home_weekly_menus WHERE family_id = home_get_my_family_id()
    )
  );

CREATE POLICY "Users can manage menu items"
  ON home_menu_items FOR ALL TO authenticated
  USING (
    menu_id IN (
      SELECT id FROM home_weekly_menus WHERE family_id = home_get_my_family_id()
    )
  );

-- ============================================================
-- 5. Grants
-- ============================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON home_families TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON home_profiles TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON home_family_members TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON home_pets TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON home_shopping_categories TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON home_shopping_lists TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON home_shopping_items TO authenticated;
GRANT SELECT, INSERT ON home_purchase_history TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON home_weekly_menus TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON home_menu_items TO authenticated;

-- ============================================================
-- 6. Seed function
-- ============================================================

CREATE OR REPLACE FUNCTION home_seed_default_categories(p_family_id UUID)
RETURNS void AS $$
BEGIN
  INSERT INTO home_shopping_categories (family_id, name, sort_order, is_default) VALUES
    (p_family_id, 'Verdure & Frutta', 1, true),
    (p_family_id, 'Carne & Salumi', 2, true),
    (p_family_id, 'Pesce', 3, true),
    (p_family_id, 'Latticini & Uova', 4, true),
    (p_family_id, 'Pasta & Cereali', 5, true),
    (p_family_id, 'Legumi', 6, true),
    (p_family_id, 'Dispensa', 7, true),
    (p_family_id, 'Prodotti per la Casa', 8, true),
    (p_family_id, 'Animali', 9, true),
    (p_family_id, 'Da ordinare / ritirare', 10, true),
    (p_family_id, 'Varie', 11, true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
