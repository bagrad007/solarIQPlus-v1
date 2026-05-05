require "test_helper"

class Demo::EnergyAnalystControllerTest < ActionDispatch::IntegrationTest
  setup { build_tenant_tree }

  test "POST message returns the chat-turn JSON contract for a customer user" do
    sign_in_as(@northwind_user)
    post demo_energy_analyst_message_path,
         params: { message: "How efficient was my system last 30 days?" }.to_json,
         headers: { "Content-Type" => "application/json", "Accept" => "application/json" }
    assert_response :success
    body = JSON.parse(response.body)
    assert_kind_of String, body["reply_text"]
    assert_kind_of Array, body["visualizations"]
    assert_match(/efficiency|performance/i, body["intent"])
  end

  test "POST message also works for a partner persona" do
    sign_in_as(@acme_user)
    post demo_energy_analyst_message_path,
         params: { message: "fault summary" }.to_json,
         headers: { "Content-Type" => "application/json" }
    assert_response :success
  end

  test "POST message also works for the maverick persona" do
    sign_in_as(@maverick_admin)
    post demo_energy_analyst_message_path,
         params: { message: "maintenance" }.to_json,
         headers: { "Content-Type" => "application/json" }
    assert_response :success
  end

  test "missing message returns 400" do
    sign_in_as(@northwind_user)
    post demo_energy_analyst_message_path,
         params: {}.to_json,
         headers: { "Content-Type" => "application/json" }
    assert_response :bad_request
  end

  test "anonymous request is rejected with 401" do
    # Devise responds with 401 + JSON body for unauthenticated JSON requests
    # (no HTML redirect).
    post demo_energy_analyst_message_path,
         params: { message: "hi" }.to_json,
         headers: { "Content-Type" => "application/json" }
    assert_response :unauthorized
  end

  private

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: "TestPass123!" } }
  end
end
