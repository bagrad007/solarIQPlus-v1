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
end
