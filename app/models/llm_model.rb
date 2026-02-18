class LlmModel < ApplicationRecord
  acts_as_tenant :account
  belongs_to :account
  belongs_to :provider

  has_many :advisors, dependent: :nullify

  validates :name, presence: true
  validates :identifier, presence: true, uniqueness: { scope: :provider_id }
  validates :provider, presence: true

  # Delegations for convenience
  delegate :provider_type, to: :provider, allow_nil: true

  scope :enabled, -> { where(enabled: true, deprecated: false).where(deleted_at: nil) }
  scope :available, -> { enabled }
  scope :deprecated, -> { where(deprecated: true) }
  scope :soft_deleted, -> { where.not(deleted_at: nil) }

  # Soft delete
  def soft_delete
    update!(deleted_at: Time.current)
  end

  def deleted?
    deleted_at.present?
  end

  # Full API identifier (provider-specific format)
  def full_identifier
    "#{provider.provider_type}/#{identifier}"
  end

  # Display name with provider
  def display_name
    "#{name} (#{provider.name})"
  end
end
