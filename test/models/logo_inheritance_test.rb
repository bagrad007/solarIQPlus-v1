require "test_helper"

class LogoInheritanceTest < ActiveSupport::TestCase
  setup { build_tenant_tree }

  test "Customer with no own logo inherits parent Partner's logo" do
    assert_nil    @northwind.logo_url
    assert_equal "https://logos/acme.svg", @northwind.effective_logo_url
  end

  test "Customer with its own logo uses it (does not fall back)" do
    assert_equal "https://logos/fabrikam.svg", @fabrikam.effective_logo_url
  end

  test "Partner uses its own logo" do
    assert_equal "https://logos/acme.svg", @acme.effective_logo_url
  end

  test "Partner without a logo falls back to Maverick's logo" do
    assert_equal "https://logos/maverick.svg", @beta.effective_logo_url
  end

  test "Current.effective_logo_url tracks the impersonated org" do
    Current.user          = @maverick_admin
    Current.session_state = { view_as_org_id: @northwind.id }
    assert_equal "https://logos/acme.svg", Current.effective_logo_url
  ensure
    Current.reset
  end
end
