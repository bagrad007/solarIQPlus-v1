class Organization < ApplicationRecord
  # Three-tier hierarchy stored as a single self-referential table. Domain
  # language: Maverick / Partner / Customer. See docs/UBIQUITOUS-LANGUAGE.md.
  #
  # `path` is set by a DB trigger; never assign it from Ruby. `parent_id`,
  # `org_type`, and `path` are immutable post-insert (DB enforces).

  enum :org_type, { maverick: "maverick", partner: "partner", customer: "customer" }

  belongs_to :parent, class_name: "Organization", optional: true
  has_many :children, class_name: "Organization", foreign_key: :parent_id, dependent: :restrict_with_exception

  has_many :users, dependent: :restrict_with_exception
  has_many :sites, dependent: :restrict_with_exception
  has_many :cases, dependent: :restrict_with_exception

  validates :name, presence: true
  validates :org_type, presence: true
  validate  :maverick_has_no_parent
  validate  :non_maverick_has_parent_of_correct_tier

  def logo_url
    branding_config["logo_url"].presence
  end

  def effective_logo_url
    own = logo_url
    return own if own
    parent&.logo_url
  end

  private

  def maverick_has_no_parent
    return unless maverick? && parent_id.present?
    errors.add(:parent_id, "must be blank for a Maverick organization")
  end

  def non_maverick_has_parent_of_correct_tier
    return if maverick?
    if parent_id.blank?
      errors.add(:parent_id, "is required for a #{org_type}")
      return
    end
    if partner? && !parent&.maverick?
      errors.add(:parent_id, "must reference a Maverick for a Partner")
    elsif customer? && !parent&.partner?
      errors.add(:parent_id, "must reference a Partner for a Customer")
    end
  end
end
