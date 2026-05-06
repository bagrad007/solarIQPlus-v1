---
name: rails-conventions-mixed-stacks
description: Applies Ruby on Rails conventions and layered architecture with emphasis on "convention over configuration." Covers mixed stacks (React or other JS SPAs/components, Python workers or services): boundaries, asset pipelines, APIs, and avoiding duplicated domain logic. Use when building or refactoring Rails apps, adding features across Ruby and JS, integrating Python services, or when the user mentions Rails conventions, Hotwire, Stimulus, jsbundling, or monolith-plus-frontend patterns.
disable-model-invocation: true
---

# Rails conventions and mixed stacks

## Guiding principle

**Convention over configuration.** Prefer Rails defaults (directory names, RESTful routes, Active Record patterns, Zeitwerk autoloading) before introducing custom layers or frameworks. Custom code should earn its place with a clear boundary and name.

## Rails core practices

- **Respect layer boundaries:** Controllers stay thin (HTTP, auth, params, response). Heavy logic belongs in models (domain that maps cleanly to AR), POROs under `app/models` or `app/services` (or `app/domain` if the team uses that), or jobs for async work. Reuse `app/controllers/concerns` and `app/models/concerns` for shared behavior, not as junk drawers.
- **REST and routes:** Prefer resourceful routes and standard CRUD actions. New collection/member actions need a justified name and should not hide non-REST RPC behind GET.
- **Active Record:** Keep validations and associations in the model; avoid fat callbacks—prefer explicit service objects or jobs when side effects branch or are hard to test. Use transactions where multiple writes must succeed or fail together.
- **Configuration:** Use `config/` and initializers for framework wiring; use credentials / env vars for secrets, never committed literals. Follow Rails 8 defaults where applicable (e.g. Solid Queue/Cache when enabled).
- **Testing:** Mirror `app/` structure under `test/` or `spec/`. Request/system tests for critical user paths; model and service tests for rules and edge cases.

## Frontend: Hotwire-first (Stimulus, Turbo)

When the app uses Stimulus and Turbo (typical Rails 7+ default):

- Colocate Stimulus controllers with clear names matching DOM conventions; keep controllers small and delegate shared behavior to modules or small libs under `app/javascript`.
- Prefer Turbo Frames and Streams for partial updates before reaching for a client-side state library.

## Frontend: React (or similar) inside or beside Rails

Treat the **HTTP boundary** as the contract: JSON shape, status codes, versioning if public APIs grow.

- **Monolith serving React:** Use Rails for HTML shell, auth, and CSRF where forms post to Rails; for JSON APIs use `protect_from_forgery with: :null_session` or token strategy consistently, and document the approach. Keep API controllers in a dedicated namespace (e.g. `Api::V1::`) when the surface grows.
- **Asset pipeline:** Respect the project’s choice (`jsbundling-rails`, Vite, importmaps). Do not fight the pipeline—entry points and build outputs stay where the framework expects them.
- **State and domain:** Do not reimplement business rules in React that already exist in Ruby unless the app is explicitly split; prefer a single source of truth on the server and thin clients for presentation and interaction.
- **Types and contracts:** When TypeScript is present, align DTOs with server responses; consider OpenAPI or a shared schema only if the team already maintains one—avoid duplicate manual maps that drift.

## Python (or other languages) alongside Rails

Assume **separate runtimes** unless proven otherwise.

- **Ownership:** Business invariants live in one place—usually Rails for a Rails-primary app. Python services should orchestrate or compute what they own (ML, ETL, workers) and call Rails via HTTP/message queue with explicit schemas.
- **Contracts:** Use versioned messages or REST/JSON with clear error models; avoid ad-hoc shared databases as the only integration unless operations and migrations are strictly coordinated.
- **Jobs:** Use Active Job for Ruby-side async; Python workers should not silently mutate Rails-owned tables without documented pairing (migrations, locking, idempotency).

## When to break convention

Breaking convention is acceptable when:

- The default pattern obscures behavior or makes tests brittle, and
- The alternative has a **documented home** (directory, naming, one paragraph in README or ADR).

Otherwise default to Rails conventions.

## Quick checklist

- [ ] New code lives under the conventional path for its role (`models`, `controllers`, `jobs`, `services`, `javascript`, etc.).
- [ ] Routes and controller actions read as standard Rails or are intentionally named non-REST with a comment or doc.
- [ ] No duplicated domain rules across Ruby, JS, and Python without an explicit contract and owner.
- [ ] Secrets and environment-specific config are not hardcoded.
- [ ] Mixed-stack boundaries (JSON API, queue, CLI) are explicit and testable.

## Additional resources

For deeper Rails guides, prefer the official [Rails Guides](https://guides.rubyonrails.org/) and the team’s existing ADRs or README over re-deriving framework behavior in chat.
