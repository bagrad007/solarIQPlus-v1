# frozen_string_literal: true

require "test_helper"

# The sidebar wordmark is where the user reads the company identity. The
# logo's orange swoosh is mirrored here as a luminous accent bar under
# that wordmark — a single dose of brand color tying the chrome to the logo
# without bleeding orange into nav items, buttons, or content.
#
# `data-testid="brand-accent-stripe"` pins the contract so future markup
# refactors can't silently lose the accent.
class SidebarBrandAccentTest < ActionDispatch::IntegrationTest
  setup do
    build_tenant_tree
  end

  test "sidebar renders a brand-orange accent stripe directly under the wordmark" do
    sign_in_as(@maverick_admin)
    get dashboard_path
    assert_response :success

    assert_select '[data-testid="app-sidebar"] [data-testid="brand-accent-stripe"].sidebar-brand-accent-stripe', count: 1
  end

  test "the accent stripe lives inside the sidebar header, before the nav list" do
    sign_in_as(@maverick_admin)
    get dashboard_path
    assert_response :success

    body = @response.body
    stripe_idx = body.index('data-testid="brand-accent-stripe"')
    nav_idx    = body.index('aria-label="Primary"')
    refute_nil stripe_idx, "Brand accent stripe must be present in the sidebar"
    refute_nil nav_idx,    "Sidebar nav must be present"
    assert stripe_idx < nav_idx,
           "Accent stripe must appear *before* the nav (i.e. directly under the wordmark)"
  end

  # Effective Logo contract: the sidebar renders <img src=...> for the
  # Effective Tenant's logo, walking own → parent → nil exactly as
  # Organization#effective_logo_url does. Pinning this here so the seed
  # change (placeholder URL → /branding/paradise.png) cannot silently
  # regress by, say, a layout refactor that drops the <img>.
  #
  # Single-Site Customers redirect from /dashboard to /sites/:id; we follow
  # the redirect because the Effective Logo contract holds at the destination
  # (the sidebar partial renders on every authenticated page).
  test "Customer user under a logo-bearing Partner sees the Partner's logo in the sidebar" do
    sign_in_as(@northwind_user)
    get dashboard_path
    follow_redirect! if response.redirect?
    assert_response :success

    assert_select '[data-testid="app-sidebar"] img[src=?]', "https://logos/acme.svg", count: 1
  end

  # Alt text reflects the *Effective Tenant* (the Customer the user is in),
  # not the Partner whose logo we happen to be inheriting. The image src is
  # the inherited Partner logo; the alt anchors the screen reader to the
  # page's tenant context.
  test "sidebar img alt names the Effective Tenant, not the inherited Partner" do
    sign_in_as(@northwind_user)
    get dashboard_path
    follow_redirect! if response.redirect?
    assert_response :success

    assert_select '[data-testid="app-sidebar"] img[alt=?]', "Northwind", count: 1
    assert_select '[data-testid="app-sidebar"] .text-headline-md', count: 0
  end

  private

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: "TestPass123!" } }
  end
end
