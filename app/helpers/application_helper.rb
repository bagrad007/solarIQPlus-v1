module ApplicationHelper
  # Persona nav set keyed off Current.effective_organization (so Maverick in
  # view-as sees the impersonated org's nav, not their own).
  def nav_items
    case Current.effective_organization&.org_type
    when "maverick"
      [
        { label: "Dashboard",   path: dashboard_path,   icon: "dashboard" },
        { label: "Diagnostics", path: diagnostics_path, icon: "monitoring" },
        { label: "Reports",     path: reports_path,     icon: "assessment" },
        { label: "Alarms",      path: alarms_path,      icon: "notifications_active" },
        { label: "Cases",       path: cases_path,       icon: "support_agent" },
        { label: "Audit Logs",  path: audit_logs_path,  icon: "fact_check" }
      ]
    when "partner"
      [
        { label: "Dashboard",        path: dashboard_path,         icon: "dashboard" },
        { label: "Diagnostics",      path: diagnostics_path,       icon: "monitoring" },
        { label: "Reports",          path: reports_path,           icon: "assessment" },
        { label: "Customer Manager", path: customer_manager_path,  icon: "groups" },
        { label: "Alarms",           path: alarms_path,            icon: "notifications_active" },
        { label: "Cases",            path: cases_path,             icon: "support_agent" }
      ]
    when "customer"
      [
        { label: "Dashboard",   path: dashboard_path,   icon: "dashboard" },
        { label: "Diagnostics", path: diagnostics_path, icon: "monitoring" },
        { label: "Reports",     path: reports_path,     icon: "assessment" },
        { label: "Alarms",      path: alarms_path,      icon: "notifications_active" },
        { label: "Cases",       path: cases_path,       icon: "support_agent" }
      ]
    else
      []
    end
  end

  # Sidebar / mobile account: effective tenant name (view-as uses the
  # impersonated org), not individual user names.
  def nav_account_scope_name
    Current.effective_organization&.name.presence \
      || current_user.organization&.name.presence \
      || "SolarIQ+"
  end

  def nav_account_scope_initial
    ch = nav_account_scope_name.to_s.strip[/[[:alnum:]]/u]
    ch&.upcase || "?"
  end

  # True when the current page is "about" exactly one Customer organization
  # — the AI Energy Analyst widget renders here (site dashboard, diagnostics#show,
  # customer org drill-down, case on a customer site). Roll-up pages
  # (Maverick partner list, Partner customer list, plain dashboard index,
  # diagnostics index) never have a single Customer site in scope, so the
  # widget stays hidden.
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
