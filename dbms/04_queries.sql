-- Nosh (Inovix) - every SQL query the app uses
-- Marked -- READ or -- WRITE, with ids R1..R20, W1..W9
SET search_path TO nosh;

-- @R1
-- READ - Login: find a user by email (auth.service passwordLogin / devLogin)
SELECT user_id, email, password_hash, role, google_id
FROM users
WHERE email = 'adil@rishihood.edu.in';

-- @R2
-- READ - Student profile for the logged-in user (auth OUTLET_STAFF_INCLUDE -> studentProfile + campus)
SELECT sp.student_id, sp.full_name, sp.phone, sp.course, sp.year, sp.college_id,
       c.campus_id, c.name AS campus
FROM student_profiles sp
JOIN users u        ON u.user_id = sp.user_id
JOIN campuses c     ON c.campus_id = sp.campus_id
WHERE u.email = 'adil@rishihood.edu.in';

-- @R3
-- READ - Browse: list open outlets on a campus, best-rated first (catalog GET /outlets)
SELECT o.outlet_id, o.slug, o.name, o.description, o.image_url, o.is_open,
       o.rating, o.location, o.tags
FROM outlets o
WHERE o.campus_id = 'RU'
  AND o.is_open = TRUE
ORDER BY o.rating DESC NULLS LAST, o.name;

-- @R4
-- READ - Browse: one outlet by slug, with its campus (catalog GET /outlets/:id)
SELECT o.outlet_id, o.slug, o.name, o.description, o.image_url, o.is_open,
       o.rating, o.location, o.tags, o.campus_id, c.name AS campus
FROM outlets o
JOIN campuses c ON c.campus_id = o.campus_id
WHERE o.slug = 'the-commons';

-- @R5
-- READ - Browse: menu categories for an outlet, in display order (catalog GET /outlets/:id/categories)
SELECT mc.category_id, mc.name, mc.image_url, mc.sort_order
FROM menu_categories mc
WHERE mc.outlet_id = 'out_commons'
ORDER BY mc.sort_order, mc.name;

-- @R6
-- READ - Browse: menu items for an outlet, joined to their category (menu.findAllByOutletId)
SELECT mi.menu_item_id, mi.category_id, mc.name AS category,
       mi.name, mi.description, mi.price, mi.image_url,
       mi.is_available, mi.calories, mi.is_veg, mi.sort_order
FROM menu_items mi
LEFT JOIN menu_categories mc ON mc.category_id = mi.category_id
WHERE mi.outlet_id = 'out_commons'
ORDER BY mc.sort_order NULLS LAST, mi.sort_order, mi.name;

-- @R7
-- READ - Item detail: customization groups + options for one menu item (menu.findById include customizationGroups.options)
SELECT cg.group_id, cg.name, cg.is_required, cg.min_select, cg.max_select,
       co.option_id, co.label, co.price_delta, co.is_available
FROM customization_groups cg
JOIN customization_options co ON co.group_id = cg.group_id
WHERE cg.menu_item_id = 'mi_dosa'
ORDER BY cg.group_id, co.option_id;

-- @R8
-- READ - Search: available menu items by name within one open outlet (catalog GET /search, scoped)
SELECT mi.menu_item_id, mi.name, mi.description, mi.price, mi.image_url,
       mi.is_available, mi.is_veg
FROM menu_items mi
JOIN outlets o ON o.outlet_id = mi.outlet_id
WHERE mi.outlet_id = 'out_commons'
  AND o.is_open = TRUE
  AND mi.is_available = TRUE
  AND mi.name ILIKE '%dosa%'
ORDER BY mi.sort_order, mi.name;

-- @R9
-- READ - Tracking: full order by order_number with items, student, outlet, payment (orders.findByOrderNumber + ORDER_INCLUDE)
SELECT o.order_id, o.order_number, o.status, o.pickup_code, o.placed_at,
       o.subtotal, o.platform_fee, o.total_amount, o.outlet_snapshot, o.timeline, o.notes,
       sp.full_name AS student_name, sp.phone AS student_phone, u.email AS student_email,
       ot.name AS outlet_name, ot.slug AS outlet_slug,
       p.payment_id, p.amount AS paid_amount, p.status AS payment_status, p.gateway_ref,
       COALESCE(jsonb_agg(jsonb_build_object(
           'order_item_id', oi.order_item_id,
           'menu_item_id', oi.menu_item_id,
           'name', oi.name,
           'price', oi.price,
           'quantity', oi.quantity,
           'line_total', oi.line_total,
           'options_snapshot', oi.options_snapshot
       ) ORDER BY oi.order_item_id) FILTER (WHERE oi.order_item_id IS NOT NULL), '[]'::jsonb) AS items
FROM orders o
JOIN student_profiles sp ON sp.student_id = o.student_id
JOIN users u             ON u.user_id = sp.user_id
JOIN outlets ot          ON ot.outlet_id = o.outlet_id
LEFT JOIN payments p     ON p.order_id = o.order_id
LEFT JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.order_number = 'NOSH-000123'
GROUP BY o.order_id, sp.student_id, u.user_id, ot.outlet_id, p.payment_id;

-- @R10
-- READ - Counter: order by pickup_code (the OTP the student reads out - alternate key)
SELECT o.order_id, o.order_number, o.status, o.pickup_code, o.placed_at, o.total_amount,
       sp.full_name AS student_name, sp.phone AS student_phone,
       ot.name AS outlet_name
FROM orders o
JOIN student_profiles sp ON sp.student_id = o.student_id
JOIN outlets ot          ON ot.outlet_id = o.outlet_id
WHERE o.pickup_code = '4827';

-- @R11
-- READ - Tracking: order timeline + status milestones (orders.timeline JSONB is the source of truth)
SELECT o.order_id, o.order_number, o.status, o.placed_at, o.ready_at,
       o.timeline,
       jsonb_array_length(o.timeline) AS event_count
FROM orders o
WHERE o.order_id = 'ord_001';

-- @R12
-- READ - Student: order history, paid/refunded only, newest first (orders.findByUserId)
SELECT o.order_id, o.order_number, o.status, o.pickup_code, o.placed_at, o.total_amount,
       ot.name AS outlet_name, ot.slug AS outlet_slug,
       p.status AS payment_status
FROM orders o
JOIN outlets ot          ON ot.outlet_id = o.outlet_id
LEFT JOIN payments p     ON p.order_id = o.order_id
WHERE o.student_id = 'stu_adil'
  AND (p.status IN ('PAID', 'REFUNDED') OR p.status IS NULL)
ORDER BY o.placed_at DESC
LIMIT 20 OFFSET 0;

-- @R13
-- READ - Outlet: active orders for the kitchen board, paid only (orders.findByOutletId)
SELECT o.order_id, o.order_number, o.status, o.pickup_code, o.placed_at, o.total_amount, o.notes,
       sp.full_name AS student_name, sp.phone AS student_phone,
       p.status AS payment_status
FROM orders o
JOIN student_profiles sp ON sp.student_id = o.student_id
LEFT JOIN payments p     ON p.order_id = o.order_id
WHERE o.outlet_id = 'out_commons'
  AND o.status IN ('PENDING', 'CONFIRMED', 'PREPARING', 'READY')
  AND (p.status IN ('PAID', 'REFUNDED') OR p.status IS NULL)
ORDER BY o.placed_at DESC;

-- @R14
-- READ - Refund: list refunds for a payment, newest first (admin getOrder include payment.refunds)
SELECT r.refund_id, r.amount, r.reason, r.status, r.triggered_by,
       r.created_at, r.completed_at,
       p.payment_id, p.amount AS payment_amount, p.gateway_ref
FROM refunds r
JOIN payments p ON p.payment_id = r.payment_id
WHERE p.payment_id = 'pay_001'
ORDER BY r.created_at DESC;

-- @R15
-- READ - Dashboard: revenue by outlet in a date range, paid payments only (admin getOutlets + outlet analytics)
SELECT o.outlet_id, ot.name AS outlet_name,
       COALESCE(SUM(p.amount), 0) AS revenue,
       COUNT(*) AS paid_payment_count
FROM payments p
JOIN orders o   ON o.order_id = p.order_id
JOIN outlets ot ON ot.outlet_id = o.outlet_id
WHERE p.status = 'PAID'
  AND p.paid_at >= '2026-11-01'
  AND p.paid_at <  '2026-11-08'
GROUP BY o.outlet_id, ot.name
ORDER BY revenue DESC;

-- @R16
-- READ - Dashboard: top-selling menu items by outlet, units + gross sales (outlet getOutletAnalytics)
SELECT mi.menu_item_id, mi.name, mi.image_url,
       SUM(oi.quantity) AS units_sold,
       SUM(oi.line_total) AS gross_sales
FROM order_items oi
JOIN orders o        ON o.order_id = oi.order_id
JOIN menu_items mi   ON mi.menu_item_id = oi.menu_item_id
JOIN payments p     ON p.order_id = o.order_id AND p.status = 'PAID'
WHERE o.outlet_id = 'out_commons'
  AND o.placed_at >= '2026-11-01'
GROUP BY mi.menu_item_id, mi.name, mi.image_url
ORDER BY units_sold DESC, gross_sales DESC
LIMIT 10;

-- @R17
-- READ - Dashboard: average outlet rating across open outlets (platform overview - denormalized §5.3 column)
SELECT AVG(o.rating) AS avg_rating,
       COUNT(*) AS outlet_count,
       COUNT(*) FILTER (WHERE o.rating IS NULL) AS unrated_outlets
FROM outlets o
WHERE o.is_open = TRUE;

-- @R18
-- READ - Dashboard: order status distribution (admin getOverview ordersByStatus groupBy)
SELECT o.status, COUNT(*) AS order_count
FROM orders o
WHERE o.placed_at >= '2026-11-01'
GROUP BY o.status
ORDER BY order_count DESC, o.status;

-- @R19
-- READ - Dashboard: revenue trend by day, paid payments only (admin revenue over time)
SELECT date_trunc('day', p.paid_at) AS day,
       COALESCE(SUM(p.amount), 0) AS revenue,
       COUNT(*) AS paid_payments
FROM payments p
WHERE p.status = 'PAID'
  AND p.paid_at >= '2026-11-01'
  AND p.paid_at <  '2026-11-30'
GROUP BY day
ORDER BY day;

-- @R20
-- READ - Admin: pending refunds to process, with payment + order + outlet context (admin refund queue)
SELECT r.refund_id, r.amount, r.reason, r.triggered_by, r.created_at,
       p.payment_id, p.gateway_ref, p.amount AS payment_amount,
       o.order_id, o.order_number,
       ot.name AS outlet_name
FROM refunds r
JOIN payments p ON p.payment_id = r.payment_id
JOIN orders o   ON o.order_id = p.order_id
JOIN outlets ot ON ot.outlet_id = o.outlet_id
WHERE r.status = 'PENDING'
ORDER BY r.created_at ASC;

-- @W1
-- WRITE - Place order: insert the order header (orders.repository createOrder, status PENDING, pickup_code minted)
INSERT INTO orders (order_id, order_number, student_id, outlet_id, status, pickup_code,
                    subtotal, platform_fee, total_amount, outlet_snapshot, timeline, notes)
VALUES ('ord_new01', 'NOSH-000124', 'stu_adil', 'out_commons', 'PENDING', '9182',
        300.00, 5.00, 305.00,
        '{"id":"out_commons","name":"The Commons"}'::jsonb,
        '[{"status":"PENDING","at":"2026-11-15T10:00:00Z","by":"stu_adil"}]'::jsonb,
        'Less spicy');

-- @W2
-- WRITE - Place order: add order items with price + name snapshot (orders.repository items.create)
INSERT INTO order_items (order_item_id, order_id, menu_item_id, name, price, image_url,
                         quantity, line_total, options_snapshot)
VALUES ('oi_new01', 'ord_new01', 'mi_dosa',   'Masala Dosa',   120.00, NULL, 2, 240.00, '[]'::jsonb),
       ('oi_new02', 'ord_new01', 'mi_coffee', 'Filter Coffee',  60.00, NULL, 1,  60.00,
        '[{"group":"Add-ons","option":"Extra shot","delta":15.00}]'::jsonb);

-- @W3
-- WRITE - Place order: freeze the customization snapshot on an order line (denorm §5.1 - what was charged)
UPDATE order_items
SET options_snapshot = '[{"group":"Add-ons","option":"Extra cheese","delta":30.00}]'::jsonb
WHERE order_item_id = 'oi_new01';

-- @W4
-- WRITE - Place order: assign / regenerate the pickup OTP on an order (orders.service generatePickupCode)
UPDATE orders
SET pickup_code = '5294'
WHERE order_id = 'ord_new01';

-- @W5
-- WRITE - Pay: create the payment row in PENDING state (orders.repository createOrder -> payment.create)
INSERT INTO payments (payment_id, order_id, amount, status, method, razorpay_order_id)
VALUES ('pay_new01', 'ord_new01', 305.00, 'PENDING', 'ONLINE', 'order_NOSH000124');

-- @W6
-- WRITE - Pay: mark payment PAID on Razorpay webhook / verify (payments.service verifyPayment, PENDING->PAID guard)
UPDATE payments
SET status      = 'PAID',
    paid_at     = now(),
    gateway_ref = 'pay_NOSH000124'
WHERE payment_id = 'pay_new01'
  AND status = 'PENDING';

-- @W7
-- WRITE - Refund: create a refund row (admin issueManualRefund / transition.service auto-refund)
INSERT INTO refunds (refund_id, payment_id, amount, reason, status, triggered_by)
VALUES ('ref_new01', 'pay_new01', 50.00, 'SUPER_ADMIN_MANUAL', 'PENDING', 'usr_admin01');

-- @W8
-- WRITE - Kitchen: advance an order to READY (orders.repository updateStatus, PREPARING->READY guard + timeline append)
UPDATE orders
SET status   = 'READY',
    ready_at = now(),
    timeline = '[{"status":"PENDING","at":"2026-11-15T10:00:00Z","by":"stu_adil"},'
               '{"status":"PREPARING","at":"2026-11-15T10:05:00Z","by":"out_commons"},'
               '{"status":"READY","at":"2026-11-15T10:15:00Z","by":"out_commons"}]'::jsonb
WHERE order_id = 'ord_new01'
  AND status = 'PREPARING';

-- @W9
-- WRITE - Nightly: recompute outlets.rating from reviews. The AP schema keeps outlets.rating
-- as a denormalized column (§5.3) and has no reviews table, so there is nothing to aggregate;
-- this is a no-op that becomes a real recompute once a reviews table is added.
UPDATE outlets
SET rating = outlets.rating
WHERE outlet_id = 'out_commons';

-- @END
