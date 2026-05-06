# frozen_string_literal: true

require "test_helper"

# The mobile top app bar (md:hidden) is the only place a phone-sized user
# sees the *Effective Logo*. The desktop sidebar covers ≥ md viewports;
# below md the sidebar is hidden, so without this bar the Partner brand
# would never appear on phones.
#
# Contract pinned by `data-testid="mobile-top-app-bar"` on the <header>
# element so future markup refactors can't silently drop it.
class MobileTopAppBarTest < ActionDispatch::IntegrationTest
  setup { build_tenant_tree }

  test "renders the inherited Effective Logo for a Customer under a logo-bearing Partner" do
    sign_in_as(@northwind_user)
    get dashboard_path
    follow_redirect! if response.redirect?
    assert_response :success

    assert_select '[data-testid="mobile-top-app-bar"] img[src=?]',
                  "https://logos/acme.svg", count: 1
  end

  # @beta has no branding_config of its own and inherits from @maverick. To
  # exercise the bare-fallback branch (no Effective Logo anywhere in the
  # ancestry chain) we explicitly clear @maverick's branding_config first.
  test "falls back to the SolarIQ+ app brand when no Effective Logo exists in the chain" do
    @maverick.update!(branding_config: {})
    sign_in_as(@beta_user)
    get dashboard_path
    assert_response :success

    assert_select '[data-testid="mobile-top-app-bar"] img[alt=?]',
                  "SolarIQ+", count: 1
  end

  test "the avatar trigger is wired into the existing mobile-account-sheet controller" do
    sign_in_as(@acme_user)
    get dashboard_path
    assert_response :success

    assert_select '[data-controller="mobile-account-sheet"]' do
      assert_select '[data-testid="mobile-top-app-bar"] button[data-mobile-account-sheet-target="button"][data-action*="mobile-account-sheet#toggle"]', count: 1
      assert_select '[data-mobile-account-sheet-target="sheet"]', count: 1
    end
  end

  test "the bar is hidden at md and above (encoded in the md:hidden class)" do
    sign_in_as(@acme_user)
    get dashboard_path
    assert_response :success

    assert_select '[data-testid="mobile-top-app-bar"].md\\:hidden', count: 1
  end

  private

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: "TestPass123!" } }
  end
end
