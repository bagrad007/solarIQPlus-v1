# frozen_string_literal: true

# Builds hierarchy breadcrumbs for Partner and Maverick personas. Maverick
# trails anchor at "Partners" when drilling the org tree; primary sidebar
# destinations (Cases, Audit Logs, Sites index, Customer Manager) omit that
# home crumb so the strip matches the current nav section.
class BreadcrumbTrail
  Segment = Struct.new(:label, :path, keyword_init: true)

  def self.for(controller)
    user = controller.current_user
    return [] unless user&.maverick_admin? || user&.partner_user?

    new(controller).segments
  end

  def initialize(controller)
    @c = controller
  end

  def segments
    return [] if @c.controller_path.start_with?("admin/")

    case @c.controller_name
    when "dashboards" then dashboards_trail
    when "organizations" then organizations_trail
    when "sites" then sites_trail
    when "cases" then cases_trail
    when "customer_manager" then customer_manager_trail
    when "audit_logs" then audit_logs_trail
    else
      []
    end
  end

  private

  def user
    @c.current_user
  end

  def current
    Current
  end

  def eff
    current.effective_organization
  end

  def maverick?
    user.maverick_admin?
  end

  def partner?
    user.partner_user?
  end

  def h
    @c
  end

  def seg(label, path = nil)
    Segment.new(label: label, path: path)
  end

  def maverick_root_only?
    maverick? && eff&.maverick? && @c.controller_name == "dashboards" && @c.action_name == "show"
  end

  def partners_home_link
    seg("Partners", h.dashboard_path)
  end

  def partner_dashboard_link
    seg("Dashboard", h.dashboard_path)
  end

  def dashboards_trail
    if maverick?
      return [seg("Partners", nil)] if maverick_root_only?

      trail = [partners_home_link]
      if eff&.partner?
        trail << seg(eff.name, h.organization_path(eff))
        trail << seg("Dashboard", nil)
      elsif eff&.customer?
        trail << seg(eff.parent.name, h.organization_path(eff.parent)) if eff.parent
        trail << seg(eff.name, h.organization_path(eff))
        trail << seg("Dashboard", nil)
      else
        trail << seg("Dashboard", nil)
      end
      trail
    elsif partner?
      [seg("Dashboard", nil)]
    else
      []
    end
  end

  def organizations_trail
    target = @c.instance_variable_get(:@target)
    return [] unless target.is_a?(Organization)

    if maverick?
      trail = [partners_home_link]
      if target.partner?
        trail << seg(target.name, nil)
      elsif target.customer?
        trail << seg(target.parent.name, h.organization_path(target.parent)) if target.parent
        trail << seg(target.name, nil)
      end
      trail
    elsif partner?
      return [] unless target.customer?

      [partner_dashboard_link, seg(target.name, nil)]
    else
      []
    end
  end

  def sites_trail
    return sites_index_trail if @c.action_name == "index"

    site = @c.instance_variable_get(:@site)
    return [] unless site

    customer = site.organization
    if customer.blank? || !customer.customer?
      return [partners_home_link, seg("New site", nil)] if maverick?
      return [partner_dashboard_link, seg("New site", nil)] if partner?

      return []
    end

    partner_org = customer.parent

    if maverick?
      trail = [partners_home_link]
      trail << seg(partner_org.name, h.organization_path(partner_org)) if partner_org
      trail << seg(customer.name, h.organization_path(customer))
      case @c.action_name
      when "new", "create"
        trail << (site.new_record? ? seg("New site", nil) : seg(site.name, h.site_path(site)))
      when "show", "edit", "update"
        trail << seg(site.name, nil)
      else
        trail << seg(site.name, nil)
      end
      trail
    elsif partner?
      trail = [partner_dashboard_link, seg(customer.name, h.organization_path(customer))]
      case @c.action_name
      when "new", "create"
        trail << (site.new_record? ? seg("New site", nil) : seg(site.name, h.site_path(site)))
      when "show", "edit", "update"
        trail << seg(site.name, nil)
      else
        trail << seg(site.name, nil)
      end
      trail
    else
      []
    end
  end

  def sites_index_trail
    if maverick?
      [seg("Sites", nil)]
    elsif partner?
      [seg("Sites", nil)]
    else
      []
    end
  end

  def cases_trail
    case @c.action_name
    when "index"
      if maverick?
        [seg("Cases", nil)]
      elsif partner?
        [seg("Cases", nil)]
      else
        []
      end
    when "show", "add_note", "escalate"
      kase = @c.instance_variable_get(:@case)
      return sites_index_trail if kase.nil? || !kase.persisted?

      case_show_trail(kase)
    when "new", "create"
      kase = @c.instance_variable_get(:@case)
      site = @c.instance_variable_get(:@site)
      if maverick?
        if site.present?
          trail = [partners_home_link]
          append_site_customer_partner(trail, site)
          trail << seg("New case", nil)
        elsif kase&.site.present?
          trail = [partners_home_link]
          append_site_customer_partner(trail, kase.site)
          trail << seg("New case", nil)
        else
          trail = [seg("Cases", h.cases_path), seg("New case", nil)]
        end
        trail
      elsif partner?
        if site.present?
          trail = [partner_dashboard_link]
          append_site_customer_partner(trail, site)
          trail << seg("New case", nil)
        elsif kase&.site.present?
          trail = [partner_dashboard_link]
          append_site_customer_partner(trail, kase.site)
          trail << seg("New case", nil)
        else
          trail = [seg("Cases", h.cases_path), seg("New case", nil)]
        end
        trail
      else
        []
      end
    else
      []
    end
  end

  def append_site_customer_partner(trail, site)
    customer = site.organization
    return unless customer&.customer?

    partner_org = customer.parent
    trail << seg(partner_org.name, h.organization_path(partner_org)) if maverick? && partner_org
    trail << seg(customer.name, h.organization_path(customer))
    trail << seg(site.name, h.site_path(site))
  end

  def case_show_trail(kase)
    site = kase.site
    return sites_index_trail if site.blank?

    customer = site.organization
    return sites_index_trail unless customer&.customer?

    partner_org = customer.parent
    label = kase.subject.present? ? kase.subject.truncate(48) : "Case ##{kase.id}"

    if maverick?
      trail = [partners_home_link]
      trail << seg(partner_org.name, h.organization_path(partner_org)) if partner_org
      trail << seg(customer.name, h.organization_path(customer))
      trail << seg(site.name, h.site_path(site))
      trail << seg(label, nil)
      trail
    elsif partner?
      [
        partner_dashboard_link,
        seg(customer.name, h.organization_path(customer)),
        seg(site.name, h.site_path(site)),
        seg(label, nil)
      ]
    else
      []
    end
  end

  def customer_manager_trail
    return [] unless eff&.partner?

    if maverick?
      [partners_home_link, seg(eff.name, h.organization_path(eff)), seg("Customer Manager", nil)]
    elsif partner?
      [seg("Customer Manager", nil)]
    else
      []
    end
  end

  def audit_logs_trail
    return [] unless maverick?

    [seg("Audit Logs", nil)]
  end
end
