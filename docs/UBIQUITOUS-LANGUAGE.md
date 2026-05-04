# SolarIQ+ Ubiquitous Language

The shared vocabulary for SolarIQ+. Code, comments, prose, and tests use these terms exactly. If a domain concept is not in this glossary, it is not first-class.

The domain has only three kinds of tenant: **Maverick**, **Partner**, **Customer**. They are stored as rows in a single `organizations` table joined by a self-referential `parent_id`. The table name is a schema implementation detail, not a domain concept; domain language always picks the specific tier.

## Tenants

- **Maverick** — root tenant; the platform owner ("Maverick Dynamics"). Exactly one row exists, seeded at install. `parent_id` is null. `org_type = 'maverick'`.
- **Partner** — direct child of Maverick. Owns Customers. Carries its own sidebar logo via `branding_config.logo_url`. `org_type = 'partner'`.
- **Customer** — direct child of a Partner. Owns Sites. Inherits the parent Partner's `logo_url` for the sidebar (fallback if Customer's own `branding_config` is empty). `org_type = 'customer'`.

## Resources

- **Site** — physical solar installation belonging to a Customer. The most-used screen in the app: `/sites/:id` shows the operational dashboard.
- **Telemetry** — append-only time-series row tied to a Site (denormalized `organization_id` for RLS performance). Partitioned monthly by `recorded_at`. Sort by `recorded_at` (truth source for time), never by `id`.
- **Case** — support ticket on a Site. Status enum: `open / in_progress / resolved / closed`. `closed` is final, enforced by a state-machine trigger. Append-only `notes` text field. Boolean `escalated_to_maverick` is **one-way set**: only a Maverick session can flip it back to false, enforced by a Postgres trigger.
- **Audit Log** — immutable record of Site config changes. Plan A audits `gateway_ip`, `device_credentials_encrypted`, `polling_interval_seconds`. Insert-only.

## Identity & Scope

- **Effective Tenant** — the tenant whose lens the current request is running under: the impersonated id if a Maverick is in view-as mode, otherwise the requesting user's own tenant.
- **Effective Logo** — the logo URL rendered in the sidebar for the current request: the *Effective Tenant*'s `branding_config.logo_url`, falling back to its parent Partner's logo for Customers, falling back to the Maverick default.
- **View-As** — Maverick-only mode that swaps the *Effective Tenant* for the duration of subsequent requests. Read-only by **UI affordance only** (banner copy + hidden write CTAs); RLS remains the only enforcement layer, so a deliberate write that RLS allows will succeed. Used for support/debugging — daily cross-tenant work happens through ordinary navigation since RLS already permits it.
- **Navigation vs View-As** — clicking a Partner card (as Maverick) or a Customer card (as Partner) is *navigation*: the user keeps their own chrome and writes are permitted (case notes, etc.). View-As is a separate explicit toggle near the user avatar that swaps the chrome and applies the read-only UI affordance.

## Security Primitives

- **`app.can_see(target_path)`** — the single authorization function. The only function in the system that decides whether a row is visible. All RLS policies reduce to a call against this. NULL-safe by explicit `CASE` branches.
- **GUCs** (per-request session variables): `app.user_id`, `app.org_id`, `app.is_maverick`, `app.mode`, `app.impersonated_org_id`. Set in the request transaction by `ApplicationController#with_rls_context`, cleared automatically when the connection returns to the pool.
- **`app_user`** role — the Postgres role every request runs as via `SET LOCAL ROLE app_user`. RLS is `FORCE`d on every tenant table when this role connects.
- **`org_path`** — denormalized ltree column on every tenant-bearing table. `NOT NULL` at the column level; populated by per-table BEFORE INSERT/UPDATE triggers from `organizations.path`. RLS predicates compare `target_path <@ effective_org_path()` for O(GiST) lookup with no recursive subquery.

## Trigger Taxonomy

Triggers in this system fall into exactly one of two categories.

- **Integrity trigger** (allowed) — enforces domain rules about *what may change*: state-machine transitions, lifecycle rules, immutability rules, path denormalization. May read session state when the integrity rule itself depends on identity (e.g., the case-escalation immutability trigger reading `app.is_maverick()`). Not authorization; it never decides whether a row is visible.
- **Authorization decision** (forbidden in triggers) — only RLS / `can_see` decides who can read/write which rows. If you write `IF NOT app.can_see(...) THEN RAISE` in a trigger, you have introduced a second enforcement path. Don't.
