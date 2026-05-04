require "test_helper"

class CaseLifecycleTest < ActiveSupport::TestCase
  setup do
    build_tenant_tree
    @case = Case.create!(
      site:              @site_a,
      organization:      @northwind,
      opened_by:         @acme_user,
      subject:           "Inverter intermittent fault"
    )
  end

  test "status freely transitions among open / in_progress / resolved" do
    @case.update!(status: "in_progress")
    assert_equal "in_progress", @case.reload.status
    @case.update!(status: "resolved")
    assert_equal "resolved", @case.reload.status
    @case.update!(status: "open")
    assert_equal "open", @case.reload.status
  end

  test "closing the case stamps closed_at automatically" do
    @case.update!(status: "closed")
    assert_not_nil @case.reload.closed_at
  end

  test "closed is terminal — cannot transition back" do
    @case.update!(status: "closed")
    assert_raises(ActiveRecord::StatementInvalid) do
      @case.update!(status: "open")
    end
  end

  test "notes are append-only — cannot rewrite earlier content" do
    @case.update!(notes: "first entry\n")
    assert_raises(ActiveRecord::StatementInvalid) do
      @case.update!(notes: "different first entry\n")
    end
  end

  test "notes accept appended content" do
    @case.update!(notes: "first\n")
    @case.update!(notes: "first\nsecond\n")
    assert_match(/first.*second/m, @case.reload.notes)
  end
end
