ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

ActiveJob::Base.queue_adapter = :test

# Rails dumps structure.sql with `pg_dump -x`, which strips privileges. The
# GRANTs from migration #2 therefore aren't in db/structure.sql, so the test DB
# (loaded from that dump by db:test:prepare) starts with the right schema but
# no app_user grants. Re-apply them once per test process from the same file
# the dev DB uses (db/grants.sql).
ActiveRecord::Base.connection.execute(Rails.root.join("db", "grants.sql").read)

module RlsTestHelpers
  # Run a block with the request-scoped RLS context the controller would set
  # up (SET LOCAL ROLE app_user + the five GUCs). Inside this block, all
  # ActiveRecord queries are RLS-filtered exactly as in production.
  #
  # Test data is created in `setup` *outside* this block so it lands as the
  # privileged superuser (which bypasses RLS).
  def with_rls(user:, view_as_org_id: nil)
    conn = ActiveRecord::Base.connection
    is_maverick   = user.maverick_admin?
    impersonating = is_maverick && view_as_org_id.present?

    binds = [
      user.id.to_s,
      user.organization_id.to_s,
      is_maverick   ? "true"    : "false",
      impersonating ? "view_as" : "normal",
      impersonating ? view_as_org_id.to_s : ""
    ]
    sql = <<~SQL.squish
      SELECT
        set_config('app.user_id',             $1, true),
        set_config('app.org_id',              $2, true),
        set_config('app.is_maverick',         $3, true),
        set_config('app.mode',                $4, true),
        set_config('app.impersonated_org_id', $5, true)
    SQL
    conn.execute("SET LOCAL ROLE app_user")
    conn.exec_query(sql, "RLS-test", binds)
    yield
  end

  # No-context invocation: SET LOCAL ROLE app_user *without* GUCs. Used by
  # NullSafetyTest to prove can_see() denies access in the absence of identity.
  def with_no_rls_context
    conn = ActiveRecord::Base.connection
    sql = <<~SQL.squish
      SELECT
        set_config('app.user_id',             '', true),
        set_config('app.org_id',              '', true),
        set_config('app.is_maverick',         'false', true),
        set_config('app.mode',                'normal', true),
        set_config('app.impersonated_org_id', '', true)
    SQL
    conn.execute("SET LOCAL ROLE app_user")
    conn.exec_query(sql, "RLS-test-empty")
    yield
  end
end

module TenantBuilder
  # Build the canonical test tree:
  #   maverick (Maverick Dynamics)
  #   ├── acme (Partner; logo: acme.svg)
  #   │   ├── northwind (Customer)
  #   │   │   └── site_a
  #   │   └── fabrikam (Customer; logo: fabrikam.svg)
  #   └── beta (Partner)
  #       └── contoso (Customer)
  #           └── site_b
  def build_tenant_tree
    @maverick = Organization.create!(
      org_type: "maverick", name: "Maverick Dynamics",
      branding_config: { "logo_url" => "https://logos/maverick.svg" }
    )
    @acme = Organization.create!(
      parent: @maverick, org_type: "partner", name: "Acme",
      branding_config: { "logo_url" => "https://logos/acme.svg" }
    )
    @beta = Organization.create!(
      parent: @maverick, org_type: "partner", name: "Beta"
    )
    @northwind = Organization.create!(
      parent: @acme, org_type: "customer", name: "Northwind"
    )
    @fabrikam = Organization.create!(
      parent: @acme, org_type: "customer", name: "Fabrikam",
      branding_config: { "logo_url" => "https://logos/fabrikam.svg" }
    )
    @contoso = Organization.create!(
      parent: @beta, org_type: "customer", name: "Contoso"
    )

    @maverick_admin = create_user(@maverick, "maverick_admin", "admin@maverick.test")
    @acme_user      = create_user(@acme,     "partner_user",   "user@acme.test")
    @beta_user      = create_user(@beta,     "partner_user",   "user@beta.test")
    @northwind_user = create_user(@northwind, "customer_user", "user@northwind.test")
    @fabrikam_user  = create_user(@fabrikam,  "customer_user", "user@fabrikam.test")
    @contoso_user   = create_user(@contoso,   "customer_user", "user@contoso.test")

    @site_a = Site.create!(organization: @northwind, name: "Northwind Roof", polling_interval_seconds: 30)
    @site_b = Site.create!(organization: @contoso,   name: "Contoso Warehouse", polling_interval_seconds: 60)
  end

  def create_user(org, role, email)
    User.create!(
      organization: org,
      role: role,
      email: email,
      password: "TestPass123!",
      name: email.split("@").first
    )
  end
end

module ActiveSupport
  class TestCase
    # Sequential execution. Our tests SET LOCAL ROLE inside the per-test
    # transaction; parallelism's process forks each open their own connection
    # but the test data is also created per-test, so parallelism doesn't help
    # and the seed state needs to be deterministic.
    parallelize(workers: 1)

    # No file fixtures — we build the tenant tree programmatically.
    self.fixture_paths = []

    include RlsTestHelpers
    include TenantBuilder
  end
end
