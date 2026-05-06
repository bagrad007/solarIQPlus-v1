# frozen_string_literal: true

# Build a filtered, sorted, searched, paginated relation of Alarms from a
# Hash of (typically URL) params. The single public method is #results,
# which returns a value object the controller and view consume directly.
#
# This service is a deep module: callers only need the params and the
# returned struct. Hidden behind that surface:
#   - the allow-list of filter / sort keys (anything else is ignored)
#   - the search tokenization across alarm.title + alarm_codes.label +
#     sites.name + organizations.name
#   - the default ordering (opened_at DESC) and the show_cleared toggle
#   - pagination math (50 per page, 1-indexed)
#   - case-insensitive ILIKE wrapping
#
# The relation returned is RLS-filtered automatically because the caller
# already holds the request's GUCs (Architectural Invariant 1). The
# service never re-applies tenant scoping itself.
class AlarmFilter
  PER_PAGE = 50

  RESULT = Struct.new(:relation, :total_count, :page, :per_page, :applied, keyword_init: true)

  ALLOWED_SEVERITIES = %w[critical warning cleared].freeze
  ALLOWED_STATUSES   = %w[firing acknowledged cleared].freeze

  # Sort key → SQL ORDER expression. Any other key falls back to the
  # default. We reach into joined tables (alarm_codes, sites, organizations)
  # only for the explicitly-named sort keys; otherwise the query stays on
  # the alarms table.
  SORT_EXPRESSIONS = {
    "opened_at"       => Arel.sql("alarms.opened_at"),
    "acknowledged_at" => Arel.sql("alarms.acknowledged_at NULLS LAST"),
    "status"          => Arel.sql("alarms.status"),
    "severity"        => Arel.sql("CASE alarms.severity WHEN 'critical' THEN 2 WHEN 'warning' THEN 1 WHEN 'cleared' THEN 0 END"),
    "code"            => Arel.sql("alarm_codes.code"),
    "site"            => Arel.sql("sites.name"),
    "customer"        => Arel.sql("organizations.name")
  }.freeze

  DEFAULT_SORT = "opened_at"
  DEFAULT_DIR  = "desc"

  def initialize(params, scope: Alarm.all)
    @params = params || {}
    @scope  = scope
  end

  def results
    relation     = base_scope
    relation     = apply_filters(relation)
    relation     = apply_search(relation)
    relation     = apply_sort(relation)
    total        = relation.count
    paginated    = relation.limit(PER_PAGE).offset((page - 1) * PER_PAGE)

    RESULT.new(
      relation:    paginated,
      total_count: total,
      page:        page,
      per_page:    PER_PAGE,
      applied:     applied_summary
    )
  end

  private

  attr_reader :params, :scope

  def base_scope
    show_cleared? ? scope : scope.where.not(status: "cleared")
  end

  def apply_filters(rel)
    rel = rel.where(severity: severity_filter)               if severity_filter.any?
    rel = rel.where(status:   status_filter)                 if status_filter.any?
    rel = rel.where(site_id:  param(:site_id))               if param(:site_id).present?
    rel = rel.where(code_id:  param(:code_id))               if param(:code_id).present?
    rel = rel.where(organization_id: param(:customer_id))    if param(:customer_id).present?
    rel = rel.joins(organization: :parent).where(organizations: { parent_id: param(:partner_id) }) if param(:partner_id).present?
    rel
  end

  def apply_search(rel)
    needle = param(:q).to_s.strip
    return rel if needle.blank?

    pattern = "%#{sanitize_like(needle)}%"
    rel.joins(:code, :site, :organization)
       .where(<<~SQL.squish, pattern, pattern, pattern, pattern)
         alarms.title ILIKE ?
         OR alarm_codes.label ILIKE ?
         OR sites.name ILIKE ?
         OR organizations.name ILIKE ?
       SQL
  end

  def apply_sort(rel)
    expr = SORT_EXPRESSIONS[sort_key]
    rel = rel.joins(:code) if sort_key == "code"
    rel = rel.joins(:site) if sort_key == "site"
    rel = rel.joins(:organization) if sort_key == "customer"
    rel.order(Arel.sql("#{expr} #{sort_direction}"))
  end

  def applied_summary
    {
      severity:    severity_filter,
      status:      status_filter,
      site_id:     param(:site_id).presence,
      code_id:     param(:code_id).presence,
      customer_id: param(:customer_id).presence,
      partner_id:  param(:partner_id).presence,
      q:           param(:q).presence,
      sort:        sort_key,
      dir:         sort_direction.downcase,
      show_cleared: show_cleared?,
      page:        page
    }.compact
  end

  def severity_filter
    Array(param(:severity)).map(&:to_s) & ALLOWED_SEVERITIES
  end

  def status_filter
    Array(param(:status)).map(&:to_s) & ALLOWED_STATUSES
  end

  def show_cleared?
    %w[1 true on yes].include?(param(:show_cleared).to_s)
  end

  def sort_key
    key = param(:sort).to_s
    SORT_EXPRESSIONS.key?(key) ? key : DEFAULT_SORT
  end

  # When the sort key falls back to the default we also reset the direction
  # so callers cannot smuggle an unexpected ordering through an unknown
  # sort param.
  def sort_direction
    return DEFAULT_DIR.upcase unless SORT_EXPRESSIONS.key?(param(:sort).to_s)
    (param(:dir).to_s.downcase == "asc") ? "ASC" : "DESC"
  end

  def page
    [param(:page).to_i, 1].max
  end

  def param(key)
    params[key] || params[key.to_s] || params[key.to_sym]
  end

  def sanitize_like(value)
    value.gsub(/[\\%_]/) { |ch| "\\#{ch}" }
  end
end
