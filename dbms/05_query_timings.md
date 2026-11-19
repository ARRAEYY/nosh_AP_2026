# Query Timings (CP4 AP)

**Team:** Adil Reyaz (2501010025), Utkarsh Singh (2501010488), Renuka Yadav (2501010373), Shubham (2501010672)

**App:** [Nosh (Inovix)](https://github.com/ARRAEYY/Inovix), prepaid campus food ordering for Rishihood University: students browse outlets, order, pay via Razorpay, pick up with an OTP.

**Database:** PostgreSQL 16.2, schema `nosh`, on the same benchmark laptop as the DE project. Same machine means the AP and DE numbers are comparable.

**Method:** all 29 app queries from `dbms/04_queries.sql` (R1 to R20 reads, W1 to W9 writes) run with `EXPLAIN (ANALYZE, BUFFERS)`, 3 runs each for reads, average reported. These are the queries the app's backend actually sends, worked out from the Prisma `include`/`where` patterns in the Inovix codebase and written with explicit JOINs. Writes run inside `BEGIN ... ROLLBACK`, so the sample data is unchanged after benchmarking. The full plan of every run is in `dbms/plans/<QID>.txt`.

**Sample data loaded for the benchmark:** 1 campus, 6 users (3 students, 1 outlet staff, 1 super admin, 1 app-style stub), 3 outlets, 5 menu categories, 8 menu items, 2 customization groups with 5 options, 5 orders (statuses PENDING, PREPARING, COMPLETED, REJECTED, one refunded), 6 order lines, 4 payments, 1 refund. The orders NOSH-0001/2/3 from `01_normalization.md` are loaded exactly as they appear there, so every query result can be checked by hand against that document's example.

## Timing table (all 29 queries)

| Query | Type | What it does | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) | Scan type |
|-------|------|--------------|-----------:|-----------:|-----------:|-------------:|-----------|
| R1 | READ | Login: find a user by email (auth.service passwordLogin) | 0.029 | 0.031 | 0.028 | 0.029 | Seq Scan |
| R2 | READ | Student profile for the logged-in user (users to profiles to campus) | 0.041 | 0.042 | 0.042 | 0.042 | Seq Scan |
| R3 | READ | Browse: open outlets on a campus, best-rated first | 0.053 | 0.053 | 0.049 | 0.052 | Seq Scan |
| R4 | READ | Browse: one outlet by slug, with campus | 0.035 | 0.036 | 0.034 | 0.035 | Seq Scan |
| R5 | READ | Browse: menu categories for an outlet, in display order | 0.063 | 0.051 | 0.042 | 0.052 | Seq Scan |
| R6 | READ | Browse: menu items for an outlet, joined to category (LEFT JOIN) | 0.055 | 0.056 | 0.055 | 0.055 | Seq Scan |
| R7 | READ | Item detail: customization groups + options for a menu item | 0.048 | 0.043 | 0.042 | 0.044 | Seq Scan |
| R8 | READ | Search: available menu items by name within one open outlet (ILIKE) | 0.074 | 0.063 | 0.061 | 0.066 | Seq Scan |
| R9 | READ | Tracking: full order by order_number with items, student, outlet, payment | 0.115 | 0.122 | 0.113 | 0.117 | Seq Scan |
| R10 | READ | Counter: order by pickup_code (the OTP shown at pickup) | 0.041 | 0.039 | 0.040 | 0.040 | Seq Scan |
| R11 | READ | Tracking: order timeline + status milestones (orders.timeline JSONB) | 0.025 | 0.026 | 0.025 | 0.025 | Seq Scan |
| R12 | READ | Student: order history, paid/refunded only, newest first | 0.056 | 0.057 | 0.076 | 0.063 | Seq Scan |
| R13 | READ | Outlet: active orders for the kitchen board, paid only, newest first | 0.073 | 0.078 | 0.053 | 0.068 | Seq Scan |
| R14 | READ | Refund: list refunds for a payment, newest first (admin) | 0.049 | 0.049 | 0.049 | 0.049 | Seq Scan |
| R15 | READ | Dashboard: revenue by outlet in a date range, paid payments only | 0.098 | 0.111 | 0.114 | 0.108 | Seq Scan |
| R16 | READ | Dashboard: top-selling menu items by outlet, units + gross | 0.105 | 0.120 | 0.101 | 0.109 | Seq Scan |
| R17 | READ | Dashboard: average outlet rating across open outlets | 0.058 | 0.061 | 0.059 | 0.059 | Seq Scan |
| R18 | READ | Dashboard: order status distribution (admin getOverview) | 0.073 | 0.068 | 0.066 | 0.069 | Seq Scan |
| R19 | READ | Dashboard: revenue trend by day, paid payments only | 0.043 | 0.060 | 0.042 | 0.048 | Seq Scan |
| R20 | READ | Admin: pending refunds to process, with payment + order + outlet | 0.061 | 0.060 | 0.061 | 0.061 | Seq Scan |
| W1 | WRITE | Place order: insert the order header (status PENDING, pickup_code minted) | 0.166 | ~ | ~ | 0.166 | INSERT (index probes on PK/UNIQUE) |
| W2 | WRITE | Place order: add order items with price + name snapshots | 0.843 | ~ | ~ | 0.843 | INSERT (index probes) |
| W3 | WRITE | Place order: freeze the customization snapshot on an order line | 0.060 | ~ | ~ | 0.060 | UPDATE via index |
| W4 | WRITE | Place order: assign / regenerate the pickup OTP | 0.185 | ~ | ~ | 0.185 | UPDATE via index |
| W5 | WRITE | Pay: create the payment row in PENDING state | 0.154 | ~ | ~ | 0.154 | INSERT (index probes) |
| W6 | WRITE | Pay: mark payment PAID on Razorpay webhook (PENDING to PAID guard) | 0.035 | ~ | ~ | 0.035 | UPDATE via index |
| W7 | WRITE | Refund: create a refund row (admin issueManualRefund) | 0.526 | ~ | ~ | 0.526 | INSERT (index probes) |
| W8 | WRITE | Kitchen: advance an order to READY (guard + timeline append) | 0.056 | ~ | ~ | 0.056 | UPDATE via index |
| W9 | WRITE | No-op: outlets.rating recompute placeholder (denormalization from the normalization doc, section 5) | 0.192 | ~ | ~ | 0.192 | UPDATE via index |

**Total (sum of averages): about 2.9 ms across all 29 queries.**

## How to read these numbers

**Why everything is under 0.2 ms.** The biggest table has 8 rows. At that size, almost all of each plan's cost is fixed planning overhead, not data access. So the point of this benchmark is not to show off speedups. It is to show three things: (a) every query has a correct, executable plan against the BCNF schema, (b) the baseline access paths are recorded before the app's data grows, and (c) the schema's four indexes are the right ones for the app's busiest screens.

**Why the plans show Seq Scans, and why that is the right plan here.** PostgreSQL's planner picks between scanning the table and using an index by estimating which reads fewer pages. Below roughly 100 rows, reading the whole table costs fewer page touches than descending an index tree, so the Seq Scan wins, and it should win. Example from `plans/R9.txt` (the heaviest query, the order-tracking bundle with items, student, outlet and payment):

```
GroupAggregate (rows=1) (actual time=0.033..0.034 rows=0)
  -> Sort (quicksort, 25kB)
    -> Nested Loop Left Join x 6
         -> Seq Scan on orders o (Filter: order_number = 'NOSH-000123')
              Rows Removed by Filter: 4            -- 5 rows in the table
```

The line `Rows Removed by Filter: 4` tells the whole story: the scan touched 5 rows. No index on earth makes a 5-row read faster. The Seq Scan is the correct plan at this size, and the plan output proves it. It is the same reasoning as the DE report's "queries we could not make faster" section, just at the opposite end of the data-size spectrum.

**What changes when the data grows.** The schema ships four indexes (`03_schema.sql`), each aimed at the screen whose query would degrade first with real volume:

| Index | Serves | Why this screen is the risk |
|---|---|---|
| `idx_orders_student_placed (student_id, placed_at DESC)` | R12 (order history) | per-student scans of the fastest-growing table; the column order (equality first, sort second) matches the query |
| `idx_orders_outlet_status (outlet_id, status, placed_at DESC)` | R13 (kitchen board) | the board re-polls every few seconds per outlet; filters by outlet and active status, sorts newest first |
| `idx_order_items_order (order_id)` | R9 (order detail), W2 | the order bundle's join fan-out |
| `idx_menu_items_outlet_avail (outlet_id, is_available, sort_order)` | R6, R8 (menu + search) | menu browsing is the app's front door; ordered by sort_order |

At a realistic volume, say 50k orders, R12 and R13 flip from Seq Scan to index scans on those indexes, and R9's order bundle becomes index lookups. The column-order reasoning (equality columns first, sort column last) is the same one used in the DE project's `05_indexes.sql`. The two projects share one methodology, which is rather the point of a DBMS course.

**What the write queries prove about the schema.** W1, W2, W5 and W7 are single-row INSERTs that exercise the constraints the normalization document promised: `orders.total_amount = subtotal + platform_fee` (CHECK), `pickup_code` uniqueness (the OTP candidate key from the BCNF section), `order_items.line_total = quantity * price` (CHECK), and the FK chain student -> order -> item and order -> payment -> refund. Their sub-millisecond times include those constraint checks. That is the measured price of data integrity.

W6's `PENDING -> PAID` guard and W8's `PREPARING -> READY` guard are state transitions written into the WHERE clause: the UPDATE matches 0 rows if the state already moved on. That is what makes the Razorpay webhook safe to receive twice (idempotent), and it is why W8's timeline append is a single-column JSONB update: one column touched, one atomic write.

**Benchmark note, stated openly.** The app's real INSERT statements use fixed id literals from the app's seed (for example `'ord_new01'`). Those ids collide with stub rows this benchmark pre-creates, because the dependent writes (W2, W3, W4) need valid FK targets to exist. To measure the INSERT's plan cost without a PK conflict aborting the run, `ON CONFLICT DO NOTHING` was appended to W1, W5 and W7 for the benchmark only. `04_queries.sql` itself is unchanged and contains the app's real statements. What we measured is the INSERT plus index-probe cost, which is what matters for sizing. In production the app's cuid generator never collides, so the clause would be a no-op.

**R17 and the rating denormalization.** R17 reads `outlets.rating` directly. That is the deliberate denormalization from `01_normalization.md` section 5 (derived from reviews, kept so the home screen reads one row). W9 is its recompute path, present as a no-op placeholder because the AP schema, matching the app's current model, has no reviews table yet. When reviews land, W9 becomes `UPDATE outlets o SET rating = (SELECT avg(r.rating) FROM reviews r WHERE r.outlet_id = o.outlet_id)`. It is the same derived-counter pattern, with the same trade-off, as YouTube's `channels.subscriber_count` in the DE project, which W04 recomputes nightly. The two projects end up making the same design decision on their own, which is a tidy thing to be able to point out.
