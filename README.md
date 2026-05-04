# SolarIQ+

Hierarchical multi-tenant industrial monitoring platform. Maverick Dynamics → Partners → Customers → Sites.

The database is the security boundary: every access decision reduces to PostgreSQL Row-Level Security via `app.can_see(org_path)`. There is no application-level authorization. See [`docs/UBIQUITOUS-LANGUAGE.md`](docs/UBIQUITOUS-LANGUAGE.md) for the domain glossary.

## Stack

| Component   | Version  | Notes                                                                 |
|-------------|----------|-----------------------------------------------------------------------|
| Ruby        | 3.4.9    | Native arm64 build via rbenv on Apple Silicon.                        |
| Rails       | 8.1.3    | 8.1 series receives bug fixes through October 2026.                   |
| PostgreSQL  | 18.3     | `uuidv7()` is a built-in; telemetry uses it for time-local ids. Sort order is still `recorded_at`, never `id` (uuidv7 is per-generator-monotonic only). |
| Devise      | 5.0.3    | Auth.                                                                 |
| Tailwind    | v4.2.4   | CSS-first config in `app/assets/stylesheets/application.tailwind.css`.|
| esbuild     | 0.28+    | JS bundling. Plan B will mount a React island here.                   |
| turbo-rails | 8.0.23   | Hotwire stack.                                                        |
| stimulus-rails | 1.3+   |                                                                       |

## Architectural Invariants (non-negotiable)

1. **RLS is the only access-control mechanism.** No Pundit, no controller `authorize_*` filters that decide visibility, no model `default_scope` for auth.
2. **`organization_id` is always present on every tenant-bearing row.** Plus a denormalized `org_path` (ltree) so RLS is a single `<@` comparison.
3. **Impersonation narrows scope; it never transfers privilege.** A Maverick in view-as is authorized identically to a non-Maverick at the impersonated scope.
4. **No application feature may introduce a second authorization model.** Every access decision reduces to `app.can_see(org_path)`. UX features (template dispatch on role, banners, hidden CTAs) are affordances, not authorization.

## Local development

```bash
brew services start postgresql@18
bundle install
yarn install
bin/rails db:setup
bin/dev
```

## Test suite

```bash
bin/rails test
```

Plan A's Definition of Done is the green test battery in `test/` covering all four invariants.
