# frozen_string_literal: true

require "test_helper"

# The Alarms tab must appear in the sidebar for every persona, sandwiched
# immediately above the Cases entry. Position matters: operators expect
# Alarms to surface ABOVE Cases because triage drives most of their work.
class AlarmsSidebarTest < ActionDispatch::IntegrationTest
  setup { build_tenant_tree }

  test "Maverick sidebar lists Alarms immediately before Cases" do
    sign_in_as(@maverick_admin)
    get dashboard_path
    assert_response :success
    assert_alarms_above_cases
  end

  test "Partner sidebar lists Alarms immediately before Cases" do
    sign_in_as(@acme_user)
    get dashboard_path
    assert_response :success
    assert_alarms_above_cases
  end

  test "Customer sidebar lists Alarms immediately before Cases" do
    sign_in_as(@northwind_user)
    get dashboard_path
    follow_redirect! if response.redirect? # single-site customer auto-redirects
    assert_response :success
    assert_alarms_above_cases
  end

  test "every persona's Alarms link points to /alarms" do
    [@maverick_admin, @acme_user, @northwind_user].each do |user|
      sign_in_as(user)
      get dashboard_path
      follow_redirect! if response.redirect?
      assert_response :success
      assert_select '[data-testid="app-sidebar"]' do
        assert_select "a[href=?]", alarms_path, text: /Alarms/, count: 1
      end
    end
  end

  private

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: "TestPass123!" } }
  end

  def assert_alarms_above_cases
    assert_select '[data-testid="app-sidebar"] nav ul' do
      hrefs = css_select("a").map { |a| a["href"] }
      alarms_idx = hrefs.index { |h| h == alarms_path }
      cases_idx  = hrefs.index { |h| h == cases_path }
      assert_not_nil alarms_idx, "Alarms link not present in sidebar"
      assert_not_nil cases_idx,  "Cases link not present in sidebar"
      assert alarms_idx < cases_idx, "Expected Alarms to render above Cases (alarms=#{alarms_idx}, cases=#{cases_idx})"
      assert_equal cases_idx - 1, alarms_idx, "Expected Alarms to be immediately above Cases"
    end
  end
end
