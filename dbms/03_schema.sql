-- ============================================================================
-- Nosh (Inovix) — Campus food-ordering app
-- dbms/03_schema.sql · CP2 AP
-- Team: Adil Reyaz (2501010025), Utkarsh Singh (2501010488),
--       Renuka Yadav (2501010373), Shubham (2501010672)
--
-- This is the BCNF schema that 01_normalization.md arrives at: students,
-- campuses, outlets, menu categories, menu items, customization groups and
-- options, orders, order lines, payments and refunds. The four deliberate
-- denormalizations (ORDER_ITEMS snapshot columns, OUTLETS.rating, OUTLETS.tags,
-- ORDERS.outlet_snapshot) are kept, exactly as documented in §5 of the
-- normalization doc.
--
-- Runs top-to-bottom on an empty PostgreSQL 15+ database.
-- ============================================================================

-- Re-runnable from a clean slate.
DROP SCHEMA IF EXISTS nosh CASCADE;
CREATE SCHEMA nosh;
SET search_path TO nosh;

-- ----------------------------------------------------------------------------
-- 1. campuses — one row per university served by Nosh
-- ----------------------------------------------------------------------------
CREATE TABLE campuses (
    campus_id   VARCHAR(20) PRIMARY KEY,         -- e.g. 'RU'
    name        VARCHAR(120) NOT NULL,
    domain      VARCHAR(120) NOT NULL UNIQUE,     -- e.g. 'rishihood.edu.in' — alternate key
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ----------------------------------------------------------------------------
-- 2. users — a login account (email + password hash + role)
--    Student, outlet-staff and admin accounts all live here; role decides what
--    they can do. The identity record (profile) is split out below so the
--    login account stays separate from the student profile (see §3 of
--    01_normalization.md).
-- ----------------------------------------------------------------------------
CREATE TABLE users (
    user_id          VARCHAR(30) PRIMARY KEY,     -- cuid in the app
    email            VARCHAR(200) NOT NULL UNIQUE,
    password_hash    VARCHAR(200),               -- NULL for Google-only logins
    role             VARCHAR(20)  NOT NULL,
    google_id        VARCHAR(60)  UNIQUE,        -- alternate key for Google logins
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT users_role_valid
        CHECK (role IN ('STUDENT', 'OUTLET_STAFF', 'SUPER_ADMIN'))
);

-- ----------------------------------------------------------------------------
-- 3. student_profiles — 1:1 with users (STUDENT role); the identity record
-- ----------------------------------------------------------------------------
CREATE TABLE student_profiles (
    student_id    VARCHAR(30) PRIMARY KEY,
    user_id       VARCHAR(30) NOT NULL UNIQUE REFERENCES users (user_id)
                                          ON DELETE CASCADE,
    full_name     VARCHAR(120) NOT NULL,
    phone         VARCHAR(15)  NOT NULL,
    course        VARCHAR(80),                   -- e.g. 'BTech CS & AI'
    year          SMALLINT,
    college_id    VARCHAR(30)  NOT NULL UNIQUE,  -- e.g. 'RU12345' — alternate key
    campus_id     VARCHAR(20)  REFERENCES campuses (campus_id)
                                  ON DELETE RESTRICT,

    CONSTRAINT student_profiles_year_sane
        CHECK (year IS NULL OR year BETWEEN 1 AND 6)
);

-- ----------------------------------------------------------------------------
-- 4. outlets — campus food outlets (The Commons, Brew & Bites, ...)
-- ----------------------------------------------------------------------------
CREATE TABLE outlets (
    outlet_id    VARCHAR(30) PRIMARY KEY,
    slug         VARCHAR(60)  NOT NULL UNIQUE,   -- URL key, e.g. 'the-commons'
    name         VARCHAR(120) NOT NULL,
    description  TEXT,
    location     VARCHAR(200),
    image_url    VARCHAR(400),
    rating       NUMERIC(2,1),                    -- derived from reviews; kept for one-row reads (denormalization §5.3)
    is_open      BOOLEAN     NOT NULL DEFAULT FALSE,
    tags         VARCHAR(200),                   -- comma-separated, e.g. 'Meals, Beverages' (denormalization §5.4)
    campus_id    VARCHAR(20) NOT NULL REFERENCES campuses (campus_id)
                                 ON DELETE RESTRICT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT outlets_rating_range
        CHECK (rating IS NULL OR rating BETWEEN 0 AND 5)
);

-- ----------------------------------------------------------------------------
-- 5. menu_categories — categories within one outlet's menu (Meals, Snacks...)
-- ----------------------------------------------------------------------------
CREATE TABLE menu_categories (
    category_id  VARCHAR(30) PRIMARY KEY,
    outlet_id    VARCHAR(30) NOT NULL REFERENCES outlets (outlet_id)
                                 ON DELETE CASCADE,
    name         VARCHAR(80) NOT NULL,           -- e.g. 'Meals'
    sort_order   INTEGER     NOT NULL DEFAULT 0,
    image_url    VARCHAR(400),

    UNIQUE (outlet_id, name),                      -- a category name is unique per outlet
    CONSTRAINT menu_categories_sort_order_nonneg
        CHECK (sort_order >= 0)
);

-- ----------------------------------------------------------------------------
-- 6. menu_items — the dishes on a menu
-- ----------------------------------------------------------------------------
CREATE TABLE menu_items (
    menu_item_id   VARCHAR(30) PRIMARY KEY,
    outlet_id      VARCHAR(30) NOT NULL REFERENCES outlets (outlet_id)
                                     ON DELETE CASCADE,
    category_id    VARCHAR(30) REFERENCES menu_categories (category_id)
                                 ON DELETE SET NULL,
    name           VARCHAR(120) NOT NULL,
    description    TEXT,
    price          NUMERIC(8,2) NOT NULL,
    image_url      VARCHAR(400),
    is_available    BOOLEAN     NOT NULL DEFAULT TRUE,
    calories       INTEGER,
    is_veg          BOOLEAN     NOT NULL DEFAULT TRUE,
    sort_order     INTEGER     NOT NULL DEFAULT 0,

    UNIQUE (outlet_id, name),                      -- a dish name is unique per outlet
    CONSTRAINT menu_items_price_positive
        CHECK (price > 0),
    CONSTRAINT menu_items_calories_nonneg
        CHECK (calories IS NULL OR calories >= 0),
    CONSTRAINT menu_items_sort_order_nonneg
        CHECK (sort_order >= 0)
);

-- ----------------------------------------------------------------------------
-- 7. customization_groups — option groups on a menu item (Add-ons, Size, Spice)
-- ----------------------------------------------------------------------------
CREATE TABLE customization_groups (
    group_id      VARCHAR(30) PRIMARY KEY,
    menu_item_id  VARCHAR(30) NOT NULL REFERENCES menu_items (menu_item_id)
                                     ON DELETE CASCADE,
    name          VARCHAR(80) NOT NULL,           -- e.g. 'Add-ons'
    is_required   BOOLEAN     NOT NULL DEFAULT FALSE,
    min_select    SMALLINT    NOT NULL DEFAULT 0,
    max_select    SMALLINT    NOT NULL DEFAULT 1,

    CONSTRAINT customization_groups_select_bounds
        CHECK (min_select >= 0 AND max_select >= min_select)
);

-- ----------------------------------------------------------------------------
-- 8. customization_options — the selectable options inside a group
-- ----------------------------------------------------------------------------
CREATE TABLE customization_options (
    option_id     VARCHAR(30) PRIMARY KEY,
    group_id      VARCHAR(30) NOT NULL REFERENCES customization_groups (group_id)
                                     ON DELETE CASCADE,
    label         VARCHAR(80) NOT NULL,           -- e.g. 'Extra cheese'
    price_delta   NUMERIC(8,2) NOT NULL DEFAULT 0,-- can be negative (a discount)
    is_available  BOOLEAN     NOT NULL DEFAULT TRUE,

    CONSTRAINT customization_options_price_delta_sane
        CHECK (price_delta > -1000)
);

-- ----------------------------------------------------------------------------
-- 9. orders — one order placed by a student at an outlet
--    pickup_code is a candidate key (the OTP shown at the counter), so UNIQUE.
-- ----------------------------------------------------------------------------
CREATE TABLE orders (
    order_id        VARCHAR(30) PRIMARY KEY,
    order_number    VARCHAR(20)  NOT NULL UNIQUE,  -- human-readable, e.g. NOSH-0001
    student_id      VARCHAR(30)  NOT NULL REFERENCES student_profiles (student_id)
                                     ON DELETE RESTRICT,   -- orders are history; keep them
    outlet_id       VARCHAR(30)  NOT NULL REFERENCES outlets (outlet_id)
                                     ON DELETE RESTRICT,
    placed_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    status          VARCHAR(20)  NOT NULL,
    pickup_code     VARCHAR(20)  NOT NULL UNIQUE,  -- OTP; alternate key
    subtotal        NUMERIC(10,2) NOT NULL,
    platform_fee    NUMERIC(10,2) NOT NULL DEFAULT 0,
    total_amount    NUMERIC(10,2) NOT NULL,
    outlet_snapshot JSONB,                          -- denormalization §5.2: outlet name/timing at order time
    timeline        JSONB,                           -- denormalization §5.4: status history (app plans OrderStatusEvent table)
    notes           TEXT,
    ready_at        TIMESTAMPTZ,

    CONSTRAINT orders_status_valid
        CHECK (status IN ('PENDING', 'CONFIRMED', 'PREPARING', 'READY',
                          'COMPLETED', 'REJECTED', 'CANCELLED')),
    CONSTRAINT orders_total_matches
        CHECK (total_amount = subtotal + platform_fee)
);

-- ----------------------------------------------------------------------------
-- 10. order_items — the lines of an order
--     snapshot columns (name, price, image_url, options_snapshot) are kept as
--     historical facts: what was *actually charged* on that day (denorm §5.1).
-- ----------------------------------------------------------------------------
CREATE TABLE order_items (
    order_item_id     VARCHAR(30) PRIMARY KEY,
    order_id          VARCHAR(30) NOT NULL REFERENCES orders (order_id)
                                       ON DELETE CASCADE,
    menu_item_id      VARCHAR(30) REFERENCES menu_items (menu_item_id)
                                       ON DELETE SET NULL,   -- keep the line even if the dish is removed
    name              VARCHAR(120) NOT NULL,                -- snapshot
    price             NUMERIC(8,2) NOT NULL,                -- snapshot
    image_url         VARCHAR(400),                        -- snapshot
    quantity          INTEGER     NOT NULL,
    line_total        NUMERIC(10,2) NOT NULL,
    options_snapshot  JSONB,                               -- selected options + deltas, frozen

    CONSTRAINT order_items_quantity_positive
        CHECK (quantity > 0),
    CONSTRAINT order_items_line_total_matches
        CHECK (line_total = quantity * price)
);

-- ----------------------------------------------------------------------------
-- 11. payments — one payment per order (1:1)
-- ----------------------------------------------------------------------------
CREATE TABLE payments (
    payment_id        VARCHAR(30) PRIMARY KEY,
    order_id          VARCHAR(30) NOT NULL UNIQUE REFERENCES orders (order_id)
                                        ON DELETE RESTRICT,   -- finance history
    amount            NUMERIC(10,2) NOT NULL,
    status            VARCHAR(20)  NOT NULL,
    method            VARCHAR(20)  NOT NULL DEFAULT 'ONLINE',
    gateway_ref       VARCHAR(60),                          -- e.g. Razorpay payment id
    razorpay_order_id VARCHAR(60)  UNIQUE,                  -- alternate key
    created_at        TIMESTAMPTZ  NOT NULL DEFAULT now(),
    paid_at           TIMESTAMPTZ,

    CONSTRAINT payments_status_valid
        CHECK (status IN ('PENDING', 'PAID', 'FAILED', 'REFUNDED')),
    CONSTRAINT payments_method_valid
        CHECK (method IN ('ONLINE', 'WALLET', 'CASH')),
    CONSTRAINT payments_amount_positive
        CHECK (amount > 0)
);

-- ----------------------------------------------------------------------------
-- 12. refunds — multiple per payment (supports partial refunds)
-- ----------------------------------------------------------------------------
CREATE TABLE refunds (
    refund_id     VARCHAR(30) PRIMARY KEY,
    payment_id    VARCHAR(30) NOT NULL REFERENCES payments (payment_id)
                                   ON DELETE CASCADE,
    amount        NUMERIC(10,2) NOT NULL,
    reason        VARCHAR(40)  NOT NULL,
    status        VARCHAR(20)  NOT NULL,
    triggered_by  VARCHAR(30)  NOT NULL,           -- the user/system that started the refund
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    completed_at  TIMESTAMPTZ,

    CONSTRAINT refunds_reason_valid
        CHECK (reason IN ('OUTLET_REJECT', 'SUPER_ADMIN_MANUAL', 'PAYMENT_FAILED',
                          'ORDER_CANCELLED', 'DUPLICATE_PAYMENT')),
    CONSTRAINT refunds_status_valid
        CHECK (status IN ('PENDING', 'COMPLETED', 'FAILED')),
    CONSTRAINT refunds_amount_positive
        CHECK (amount > 0)
);

-- Convenience indexes that the app's hottest screens rely on (created here so
-- the schema is usable out of the box; CP3 covers tuning these explicitly).
CREATE INDEX idx_orders_student_placed   ON orders (student_id, placed_at DESC);
CREATE INDEX idx_orders_outlet_status    ON orders (outlet_id, status, placed_at DESC);
CREATE INDEX idx_order_items_order       ON order_items (order_id);
CREATE INDEX idx_menu_items_outlet_avail ON menu_items (outlet_id, is_available, sort_order);

-- Verify the schema is valid by counting the tables.
SELECT 'nosh schema loaded' AS status, count(*) AS tables
FROM information_schema.tables
WHERE table_schema = 'nosh';
