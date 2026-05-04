require "test_helper"

class ViewAsAffordanceTest < ActionDispatch::IntegrationTest
  # View-as read-only is a UI affordance, not authorization. Banner appears
  # and write CTAs are hidden, but a deliberate write that RLS allows STILL
  # succeeds. This test is the canonical boundary between the architectural
  # invariants ("RLS is the only enforcement") and the UX choices ("hide CTAs
  # while in inspect mode").

  setup { build_tenant_tree }

  test "Maverick in view-as as a Partner sees the view-as banner" do
    sign_in_as(@maverick_admin)
    post admin_view_as_path, params: { org_id: @acme.id }
    follow_redirect!
    assert_select "[class*='Inspecting']", false # plain text — match by content
    assert_match(/Inspecting/, @response.body)
    assert_match(@acme.name, @response.body)
  end

  test "Maverick in view-as does NOT see the New Case CTA on Partner dashboard" do
    sign_in_as(@maverick_admin)
    post admin_view_as_path, params: { org_id: @acme.id }
    follow_redirect!
    refute_match(/New Case/, @response.body)
  end

  test "Maverick in view-as can still write — RLS allows it" do
    sign_in_as(@maverick_admin)
    post admin_view_as_path, params: { org_id: @acme.id }

    assert_difference -> { Case.count }, 1 do
      post site_cases_path(@site_a), params: { case: { site_id: @site_a.id, subject: "Deliberate write while inspecting" } }
    end
  end

  test "Exiting view-as removes the banner" do
    sign_in_as(@maverick_admin)
    post admin_view_as_path, params: { org_id: @acme.id }
    delete admin_view_as_path
    follow_redirect!
    refute_match(/Inspecting/, @response.body)
  end

  private

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: "TestPass123!" } }
  end
end
