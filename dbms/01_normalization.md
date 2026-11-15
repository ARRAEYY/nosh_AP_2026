# Nosh — Normalization: 1NF to 2NF to 3NF to BCNF

**App:** [Nosh (Inovix)](https://github.com/ARRAEYY/Inovix), a prepaid campus food-ordering platform for Rishihood University. Students order from campus outlets (like *The Commons* and *Brew & Bites*), pay online through Razorpay, and pick up their food with an OTP code. Outlets manage incoming orders in real time.

**What this document covers:** the order and payment flow, which means students, outlets, menus, orders, order lines, customizations, payments and refunds. This is the part of the app where every kind of normal-form violation actually shows up, so it is the right slice to walk through. The supporting tables (sessions, audit log, notifications) are keyed the same way and would not add anything new.

**Why normalization matters for this app in one paragraph:** order history is the one thing we must never corrupt. Money totals, refund rights and pickup codes all hang off it. Normalization is how we make sure each fact lives in exactly one place, so it cannot contradict itself. At each step below we show the specific problem (called an anomaly) that the step removes, using the app's own seed data as the example.

---

## 0. The starting point: one flat order sheet (UNF)

The natural first version of Nosh is a spreadsheet an outlet might actually keep: one row per order, with everything about the student, the outlet, the items, the payment and the refund crammed into that row. We call that sheet `NOSH_ORDERS`. One row has 24 columns, in five groups:

| Group | Columns in the group |
|---|---|
| Order | `order_number`, `placed_at`, `status`, `pickup_code` |
| Student, copied into every row | `student_name`, `student_email`, `college_id`, `phone`, `course`, `year` |
| Outlet, copied into every row | `outlet_name`, `outlet_slug`, `outlet_location`, `outlet_rating`, `campus_name` |
| Items | `line_items` — one text cell holding the whole order |
| Money, payment and refund | `subtotal`, `platform_fee`, `total_amount`, `payment_status`, `payment_method`, `gateway_ref`, `refund_reason`, `refund_amount` |

To see what a full row actually looks like, read NOSH-0001 as a record card:

| Column | Value |
|---|---|
| order_number | NOSH-0001 |
| placed_at | 2026-10-02 13:05 |
| status | COMPLETED |
| pickup_code | PICKUP0001 |
| student_name | Adil Reyaz |
| student_email | adil@rishihood.edu.in |
| college_id | RU12345 |
| phone | 9876543210 |
| course | BTech CS & AI |
| year | 2 |
| outlet_name | The Commons |
| outlet_slug | the-commons |
| outlet_location | Block A, Ground Floor |
| outlet_rating | 4.5 |
| campus_name | Rishihood University |
| line_items | "Miso sesame grain bowl (Meals, ₹150) x1; Campus club sandwich (Snacks, ₹120) x2" |
| subtotal | 390.00 |
| platform_fee | 5.00 |
| total_amount | 395.00 |
| payment_status | PAID |
| payment_method | ONLINE |
| gateway_ref | pay_QxE1uN |
| refund_reason | (none — the order completed) |
| refund_amount | (none) |

And the two rows we will keep coming back to (same student, so the same six student columns repeat again):

| order_number | outlet | line_items (the whole cell) | total | payment | refund |
|---|---|---|---|---|---|
| NOSH-0002 | Brew & Bites | "Cold brew coffee (Beverages, ₹90) x1" | 95.00 | PAID | none |
| NOSH-0003 | Brew & Bites | "Cold brew coffee (Beverages, ₹90) x1" | 95.00 | REFUNDED | "Outlet closed early", ₹95.00 |

NOSH-0003 is included so the refund path, which the app really supports, is visible from the start.

**What is wrong with this sheet, concretely:**

- **Not atomic:** `line_items` packs several items, each with a name, category, price and quantity, into one text cell. A customization like "Extra cheese +₹30" would pack even more into the same cell.
- **Repeating groups:** an order can hold any number of items, and a payment can have several partial refunds (the app supports multiple manual partial refunds). But the sheet has only one `refund_*` set of columns.
- **Redundancy:** Adil's profile and The Commons' details are copied into every row, and would be copied again into every line once we split the items out.
- **Update anomaly:** if Brew & Bites' rating changes, we must find and edit every historical order row, or the sheet disagrees with itself.
- **Insert anomaly:** we cannot record a new menu item or a new outlet until somebody actually orders.
- **Delete anomaly:** delete the only Curry Corner order and we lose the outlet itself.

Each of these gets fixed by one of the normal-form steps below.

---

## 1. First Normal Form (1NF)

**The rule in plain words:** every column holds one single value, there are no repeating groups, and every row can be uniquely identified by a key.

**Step 1. Split the multi-valued `line_items` into one row per line.** Each line gets its own key part, `line_no`, so the key becomes the pair (order_number, line_no). The packed string becomes real columns: `item_name`, `category_name`, `unit_price`, `quantity`, `line_total`.

**Step 2. Split customizations into their own rows.** A line can have several chosen options, so options get a third key part: (order_number, line_no, option_no), with columns `option_label` and `price_delta`.

**Step 3. Split refunds into their own rows.** One payment can be refunded more than once, so refund data moves to rows keyed by (order_number, refund_no).

**Step 4. Notice what else is not atomic.** `outlet_tags` ("Meals, Beverages") would need the same treatment. The real app keeps it as a display-only string. That is a deliberate, documented deviation (section 5).

After steps 1 to 3 the sheet is one wide relation, with options and refunds pulled out into their own relations.

`ORDER_LINES`: key **(order_number, line_no)**. The line-specific columns are these:

| order_number | line_no | item_name | category_name | unit_price | quantity | line_total |
|---|---|---|---|---|---|---|
| NOSH-0001 | 1 | Miso sesame grain bowl | Meals | 150.00 | 1 | 150.00 |
| NOSH-0001 | 2 | Campus club sandwich | Snacks | 120.00 | 2 | 240.00 |
| NOSH-0002 | 1 | Cold brew coffee | Beverages | 90.00 | 1 | 90.00 |
| NOSH-0003 | 1 | Cold brew coffee | Beverages | 90.00 | 1 | 90.00 |

Every one of those rows also still carries all 21 order-level columns from the sheet (`placed_at`, `status`, `pickup_code`, the six student columns, the five outlet columns, `subtotal`, `platform_fee`, `total_amount`, `payment_status`, `gateway_ref`), repeated identically per order. For example, both NOSH-0001 lines also say subtotal 390.00, total 395.00, PAID; the NOSH-0003 line also says REJECTED and REFUNDED. That repetition is exactly what 2NF will remove in the next section.

`ORDER_LINE_OPTIONS`: key **(order_number, line_no, option_no)**. Example of the shape (customizations do not appear in the three seed orders, so this row is illustrative):

| order_number | line_no | option_no | option_label | price_delta |
|---|---|---|---|---|
| NOSH-0001 | 2 | 1 | Extra cheese | 30.00 |

`ORDER_REFUNDS`: key **(order_number, refund_no)**. This one is real — it is NOSH-0003:

| order_number | refund_no | reason | amount | status |
|---|---|---|---|---|
| NOSH-0003 | 1 | OUTLET_REJECT | 95.00 | COMPLETED |

**Functional dependencies in `ORDER_LINES` after 1NF:**

```
order_number            -> placed_at, status, pickup_code, student_name, student_email,
                           college_id, phone, course, year, outlet_name, outlet_slug,
                           outlet_location, outlet_rating, campus_name, subtotal,
                           platform_fee, total_amount, payment_status, gateway_ref
(order_number, line_no) -> item_name, category_name, unit_price, quantity, line_total
```

Read the first line as: the order number alone already tells you all those 20 columns. That observation is exactly what 2NF will act on.

Notice that 1NF fixed atomicity but made redundancy worse, not better: the order's facts now repeat on every line, and nothing stops two lines of the same order from disagreeing about, say, `total_amount`. That is the job of the next two steps.

---

## 2. Second Normal Form (2NF)

**The rule in plain words:** if the key has multiple columns, every non-key column must depend on the whole key, not just part of it.

In `ORDER_LINES` the key is (order_number, line_no). Looking at the dependency list above, there are two kinds of partial dependency:

1. Everything except the five line attributes depends on `order_number` alone. So all of that moves out into a new relation `ORDERS`, keyed by order_number.
2. The item attributes (`item_name`, `category_name`, `unit_price`) describe a dish, not a line. The same "Cold brew coffee (Beverages, ₹90)" appears in NOSH-0002 and NOSH-0003 and will appear in thousands of future orders. So dishes get their own relation with their own stable id, `menu_item_id`, and item facts move into `MENU_ITEMS`. Why an id and not the name: names are only unique per outlet, and if we keyed by name, renaming a dish would orphan all its history. The surrogate id is genuinely needed here.

What stays keyed by the full (order_number, line_no) is exactly the per-line facts: which dish, how many, what was charged.

Result after 2NF (keys in **bold**):

```
ORDERS      (**order_number**, placed_at, status, pickup_code, student_name, student_email,
             college_id, phone, course, year, outlet_name, outlet_slug, outlet_location,
             outlet_rating, campus_name, subtotal, platform_fee, total_amount,
             payment_status, gateway_ref)
MENU_ITEMS  (**menu_item_id**, item_name, category_name, unit_price, outlet_name,
             outlet_slug, outlet_location, outlet_rating)
ORDER_LINES (**order_number**, **line_no**, menu_item_id, quantity, line_total)
ORDER_LINE_OPTIONS (**order_number**, **line_no**, **option_no**, option_label, price_delta)
ORDER_REFUNDS     (**order_number**, **refund_no**, reason, amount, status)
```

**Problems removed:** an order's total or status now lives in exactly one row. A dish's price has one home. A new menu item or outlet can exist before anyone orders.

**What is still wrong (for 3NF):** inside `ORDERS`, the student columns and outlet columns still ride along with every order. They are not partial dependencies (they do depend on the whole key, which is now just order_number). They are transitive dependencies, which is the next rule.

---

## 3. Third Normal Form (3NF)

**The rule in plain words:** a non-key column must not depend on another non-key column. Every non-key column should depend on the key, period.

Inside `ORDERS` (key: order_number) there are three chains like that:

```
order_number -> student_email -> student_name, phone, course, year      (the email identifies the student)
order_number -> outlet_slug   -> outlet_name, outlet_location, outlet_rating
order_number -> outlet_slug   -> campus_name                             (two hops)
```

And one inside `MENU_ITEMS` (key: menu_item_id):

```
menu_item_id -> outlet_slug -> outlet_name, outlet_location, outlet_rating
```

So we keep splitting until every relation's non-key columns depend on its own key alone:

```
STUDENTS     (**student_id**, name, email, phone, course, year, college_id)
CAMPUSES     (**campus_id**, campus_name)
OUTLETS      (**outlet_id**, name, slug, location, rating, campus_id)
ORDERS       (**order_number**, student_id, outlet_id, placed_at, status, pickup_code,
              subtotal, platform_fee, total_amount)
MENU_ITEMS   (**menu_item_id**, outlet_id, item_name, category_name, unit_price)
ORDER_LINES  (**order_number**, **line_no**, menu_item_id, quantity, line_total)
ORDER_LINE_OPTIONS / ORDER_REFUNDS                          (unchanged from 2NF)
```

**Problems removed:** Brew & Bites' rating is updated in one row. Deleting a student's orders no longer deletes the student. Adding Curry Corner needs no order. Changing the campus name touches one row.

**Two refinements the real app makes at this point (both still 3NF):**

- **`STUDENT_PROFILES` split out of `STUDENTS`:** onboarding data (full name, phone, course, year, `college_id` like RU12345) lives in a 1:1 profile table, so the login account (`email`, password hash, role) stays separate from the identity record.
- **`MENU_CATEGORIES`:** categories have their own attributes (per-outlet sort order, image), so `category_name` inside MENU_ITEMS becomes a `category_id` referencing `MENU_CATEGORIES(**category_id**, outlet_id, name, sort_order)`. The pair (outlet_id, name) is unique, matching how the app keys a category inside one outlet's menu.

Payments and refunds also get their own tables, because they have a lifecycle of their own: a payment is created PENDING before it becomes PAID, and refunds belong to the payment, not to the order sheet. So: `PAYMENTS(**payment_id**, order_id, amount, status, method, gateway_ref)` and `REFUNDS(**refund_id**, payment_id, amount, reason, status, triggered_by)`.

---

## 4. Boyce-Codd Normal Form (BCNF)

**The rule in plain words:** for every dependency X -> Y, X must be a key of the relation (a superkey, strictly). BCNF is like 3NF with no exceptions for special cases.

We check every relation's candidate keys:

| Relation | Candidate keys (all unique in the app) | Non-trivial dependencies | Is the left side a key? |
|---|---|---|---|
| STUDENTS / USERS | {student_id}, {email} (and {google_id} for Google logins) | student_id -> all; email -> student_id | Yes, both are candidate keys |
| STUDENT_PROFILES | {student_id} (1:1), {college_id} | student_id -> all; college_id -> student_id | Yes |
| CAMPUSES | {campus_id}, {domain} | campus_id -> all; domain -> campus_id | Yes |
| OUTLETS | {outlet_id}, {slug} | outlet_id -> all; slug -> outlet_id | Yes |
| MENU_CATEGORIES | {category_id}, (outlet_id, name) | both -> all | Yes |
| MENU_ITEMS | {menu_item_id}, (outlet_id, item_name) | both -> all | Yes |
| ORDERS | {order_number}, {pickup_code} | order_number -> all; pickup_code -> order_number | Yes. pickup_code is a candidate key, which is legal |
| ORDER_LINES | (order_number, line_no) | full key -> quantity, line_total | Yes |
| PAYMENTS | {payment_id}, {order_id} (1:1), {razorpay_order_id} | each -> all | Yes |
| REFUNDS | {refund_id} | refund_id -> all | Yes |

Every left side is a key, so **the schema is in BCNF.**

The interesting cases are the alternate keys. `pickup_code` (the OTP students show at the counter) determines its order without being the primary key, and so does `college_id`. A common question here is "isn't pickup_code -> order_number a violation?" It is not, because BCNF only requires the left side to be *a* key, and pickup_code is unique, so it is a candidate key. It becomes a UNIQUE constraint in the schema instead of the primary key.

---

## 5. Denormalizations the app keeps on purpose

The real Inovix schema (Prisma, 24 models) is the BCNF design above plus four deliberate deviations. Each one trades a little purity for something the app needs. Being able to explain why each is justified is the point of this section:

1. **`ORDER_ITEMS` snapshots (`name`, `price`, `image_url`, `options_snapshot`).** Copying name and price onto the line looks like a transitive dependency, since `menu_item_id -> name, price` already lives in MENU_ITEMS. But the copied values are not dependencies, they are historical facts: what was actually charged that day. When The Commons raises the grain bowl to ₹165, last month's receipts must still say ₹150. The snapshot is the whole point.
2. **`ORDERS.outlet_snapshot`.** Same reasoning for the outlet's name and timing at order time.
3. **`OUTLETS.rating`.** Derivable from reviews, like `subscriber_count` in any platform schema. Kept so the home screen reads one row instead of aggregating all reviews. Recomputed as reviews land.
4. **`OUTLETS.tags` and `ORDERS.timeline` (JSON).** Comma-separated tags and a JSON status timeline are 1NF deviations kept for convenience. The team tracks the timeline one as debt: the app's TODO list plans an `OrderStatusEvent` table, which is exactly what a full normalization would produce.

---

## 6. Final mapping: normalized relations to actual app tables

| Normalized relation | Nosh (Inovix) model | Key as implemented |
|---|---|---|
| STUDENTS | `User` | `id` (cuid), `email` unique |
| STUDENT_PROFILES | `StudentProfile` | `userId` unique (1:1), `collegeId` unique |
| CAMPUSES | `Campus` | `id`, `code`/`domain` unique |
| OUTLETS | `Outlet` | `id`, `slug` unique |
| MENU_CATEGORIES | `MenuCategory` | `id`, (outletId, name) unique |
| MENU_ITEMS | `MenuItem` | `id`; category via `categoryId` |
| option catalog | `CustomizationGroup` -> `CustomizationOption` | group per menu item, options per group (`priceDelta`) |
| ORDERS | `Order` | `id`, `orderNumber` unique, `pickupCode` unique |
| ORDER_LINES | `OrderItem` | `id`; (orderId) indexed; item + quantity + snapshot |
| ORDER_LINE_OPTIONS | `OrderItem.optionsSnapshot` (JSON) | deliberate snapshot (section 5); the catalog lives in `CustomizationOption` |
| PAYMENTS | `Payment` | `id`, `orderId` unique (1:1), `razorpayOrderId` unique |
| ORDER_REFUNDS | `Refund` | `id`; multiple per payment for partial refunds; auto-trigger uniqueness via a partial unique index |

**The one-line summary:** taking the flat order sheet through 1NF (atomic values, one row per line/option/refund), then 2NF (order, dish and line facts separated), then 3NF (student, outlet, campus, category and payment each in their own table), then BCNF (every dependency's left side a key) lands exactly on the tables the app ships with, plus four deviations we keep on purpose and can each justify.
