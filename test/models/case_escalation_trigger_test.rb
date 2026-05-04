require "test_helper"

class CaseEscalationTriggerTest < ActiveSupport::TestCase
  # Architectural Invariant: escalation is one-way set. Anyone with write
  # access may flip false → true; only a Maverick session may flip true → false.
  # The trigger reads app.is_maverick(), which makes it an INTEGRITY trigger
  # (Trigger Taxonomy A), NOT authorization.

  setup do
    build_tenant_tree
    @case = Case.create!(
      site:         @site_a,
      organization: @northwind,
      opened_by:    @acme_user,
      subject:      "Esc test"
    )
  end

  test "escalating stamps escalated_at automatically" do
    @case.update!(escalated_to_maverick: true)
    assert @case.reload.escalated_to_maverick?
    assert_not_nil @case.escalated_at
  end

  test "Partner cannot de-escalate" do
    @case.update!(escalated_to_maverick: true)
    with_rls(user: @acme_user) do
      partner_view = Case.find(@case.id)
      assert_raises(ActiveRecord::StatementInvalid) do
        partner_view.update!(escalated_to_maverick: false)
      end
    end
  end

  test "Maverick can de-escalate" do
    @case.update!(escalated_to_maverick: true)
    with_rls(user: @maverick_admin) do
      maverick_view = Case.find(@case.id)
      maverick_view.update!(escalated_to_maverick: false)
      refute maverick_view.reload.escalated_to_maverick?
    end
  end
end
