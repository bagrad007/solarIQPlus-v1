require "test_helper"

class PrivilegeContainmentTest < ActiveSupport::TestCase
  # Architectural Invariant 3: impersonation only affects scope, never
  # privilege. We bypass the application-layer guard and set GUCs maliciously
  # to prove the SQL layer rejects elevation independently.

  setup { build_tenant_tree }

  test "non-Maverick with impersonated_org_id set in GUCs cannot widen scope" do
    raw_set_gucs(
      user_id:              @acme_user.id,
      org_id:               @acme.id,
      is_maverick:          "false",
      mode:                 "view_as",
      impersonated_org_id:  @maverick.id
    )
    assert_includes  Organization.pluck(:name), "Acme"
    refute_includes  Organization.pluck(:name), "Beta"
    refute_includes  Organization.pluck(:name), "Contoso"
  end

  test "Maverick with mode=normal still has global visibility (impersonation off)" do
    raw_set_gucs(
      user_id:              @maverick_admin.id,
      org_id:               @maverick.id,
      is_maverick:          "true",
      mode:                 "normal",
      impersonated_org_id:  @beta.id
    )
    assert_equal 6, Organization.count
  end

  private

  # Bypass the application-layer privilege guard. Used by privilege containment
  # tests *only*, to prove the SQL layer safeguards work independently.
  def raw_set_gucs(user_id:, org_id:, is_maverick:, mode:, impersonated_org_id:)
    conn = ActiveRecord::Base.connection
    binds = [user_id.to_s, org_id.to_s, is_maverick.to_s, mode.to_s, impersonated_org_id.to_s]
    sql = <<~SQL.squish
      SELECT
        set_config('app.user_id',             $1, true),
        set_config('app.org_id',              $2, true),
        set_config('app.is_maverick',         $3, true),
        set_config('app.mode',                $4, true),
        set_config('app.impersonated_org_id', $5, true)
    SQL
    conn.execute("SET LOCAL ROLE app_user")
    conn.exec_query(sql, "RLS-test-raw", binds)
  end
end
