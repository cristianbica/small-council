class Memory < ApplicationRecord
  acts_as_tenant :account
  include Versionable

  belongs_to :account
  belongs_to :space
  belongs_to :source, polymorphic: true, optional: true
  belongs_to :created_by, polymorphic: true, optional: true
  belongs_to :updated_by, polymorphic: true, optional: true

  # Track these fields for versioning
  track_versions :title, :content

  # Encrypt content at rest
  encrypts :content

  # Memory types
  MEMORY_TYPES = %w[summary conversation_summary conversation_notes knowledge].freeze

  # Status values
  STATUSES = %w[active archived draft].freeze

  # Validations
  validates :account, presence: true
  validates :space, presence: true
  validates :title, presence: true, length: { maximum: 255 }
  validates :content, presence: true
  validates :memory_type, presence: true, inclusion: { in: MEMORY_TYPES }
  validates :status, presence: true, inclusion: { in: STATUSES }

  # Scopes
  scope :active, -> { where(status: "active") }
  scope :archived, -> { where(status: "archived") }
  scope :draft, -> { where(status: "draft") }
  scope :by_type, ->(type) { type.present? ? where(memory_type: type) : all }
  scope :summary_type, -> { where(memory_type: "summary") }
  scope :conversation_notes, -> { where(memory_type: "conversation_notes") }
  scope :knowledge, -> { where(memory_type: "knowledge") }
  scope :ordered, -> { order(id: :desc) }
  scope :recent, -> { order(updated_at: :desc) }

  # Search scope
  scope :search, ->(query) {
    return all if query.blank?
    where("title ILIKE ? OR content ILIKE ?", "%#{query}%", "%#{query}%")
  }

  # Status predicates
  def active? = status == "active"
  def archived? = status == "archived"
  def draft? = status == "draft"
  def summary? = memory_type == "summary"

  # Archive this memory
  def archive!(updater = nil)
    update!(status: "archived", updated_by: updater)
  end

  # Activate this memory
  def activate!(updater = nil)
    update!(status: "active", updated_by: updater)
  end

  # Get a truncated preview of the content
  def content_preview(length: 200)
    return "" if content.blank?
    content.truncate(length)
  end

  # Memory type display name
  def memory_type_display
    memory_type.humanize
  end

  # Status display name
  def status_display
    status.humanize
  end

  # Source display name (if linked to a conversation or other source)
  def source_display
    return nil unless source.present?
    case source
    when Conversation
      "Conversation: #{source.title}"
    else
      source.to_s
    end
  end

  # Creator display name
  def creator_display
    return "Unknown" unless created_by.present?
    case created_by
    when User
      created_by.email
    when Advisor
      created_by.name
    else
      created_by.to_s
    end
  end
end
