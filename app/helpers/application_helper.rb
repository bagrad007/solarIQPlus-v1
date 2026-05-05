module ApplicationHelper
  # Persona nav set keyed off Current.effective_organization (so Maverick in
  # view-as sees the impersonated org's nav, not their own).
  def nav_items
    case Current.effective_organization&.org_type
    when "maverick"
      [
        { label: "Dashboard",  path: dashboard_path,  icon: "dashboard" },
        { label: "Cases",      path: cases_path,      icon: "support_agent" },
        { label: "Audit Logs", path: audit_logs_path, icon: "fact_check" }
      ]
    when "partner"
      [
        { label: "Dashboard",        path: dashboard_path,         icon: "dashboard" },
        { label: "Customer Manager", path: customer_manager_path,  icon: "groups" },
        { label: "Cases",            path: cases_path,             icon: "support_agent" }
      ]
    when "customer"
      [
        { label: "Dashboard", path: dashboard_path, icon: "dashboard" },
        { label: "Cases",     path: cases_path,     icon: "support_agent" }
      ]
    else
      []
    end
  end

  # Bottom nav appears only on the three high-traffic touchpoints in the
  # mobile-supported scope (per Plan A: Dashboard/Sites/Cases).
  def mobile_nav_visible?
    [dashboard_path, cases_path].include?(request.path) ||
      request.path.match?(%r{\A/sites(/|\z)})
  end

  def mobile_nav_items
    [
      { label: "Dashboard", path: dashboard_path, icon: "dashboard" },
      { label: "Cases",     path: cases_path,     icon: "support_agent" }
    ]
  end

  # True when the current page is "about" exactly one Customer organization
  # — the AI Energy Analyst widget renders only here. Roll-up pages
  # (Maverick partner list, Partner customer list, plain dashboard index)
  # never have a single Customer in scope, so the widget stays hidden.
  #
  # The widget partial accepts an optional `context_label` local; callers
  # pass the most specific name available (site → customer org name).
  def customer_scope_present?
    if defined?(@site) && @site.respond_to?(:organization) && @site.organization&.customer?
      true
    elsif defined?(@case) && @case&.site&.organization&.customer?
      true
    elsif defined?(@target) && @target.respond_to?(:customer?) && @target.customer?
      true
    elsif defined?(@organization) && @organization.respond_to?(:customer?) && @organization.customer?
      true
    else
      false
    end
  end

  # Best-effort label for the panel header — falls back to a friendly default.
  def customer_scope_label
    return @site.name if defined?(@site) && @site.respond_to?(:name)
    return @case.site&.name if defined?(@case) && @case&.site&.respond_to?(:name)
    return @target.name if defined?(@target) && @target.respond_to?(:name)
    "your fleet"
  end
end
