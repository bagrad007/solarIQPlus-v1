class User < ApplicationRecord
  # Devise provides authentication; role + organization define identity for
  # the RLS layer. The DB trigger validates that role matches org_type.

  devise :database_authenticatable, :recoverable, :rememberable, :validatable

  enum :role, {
    maverick_admin: "maverick_admin",
    partner_user:   "partner_user",
    customer_user:  "customer_user"
  }

  belongs_to :organization

  validates :role, presence: true

  def display_name
    name.presence || email
  end
end
