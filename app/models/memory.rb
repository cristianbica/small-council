class Memory < ApplicationRecord
  acts_as_tenant :account

  belongs_to :account
  belongs_to :space
  belongs_to :source, polymorphic: true, optional: true
  belongs_to :created_by, polymorphic: true, optional: true
  belongs_to :updated_by, polymorphic: true, optional: true

  # Version history
  has_many :versions, class_name: "MemoryVersion", dependent: :destroy

  # Encrypt content at rest
  encrypts :content

  # Callbacks for versioning
  after_create :create_initial_version

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
  scope :ordered, -> { order(position: :asc, created_at: :desc) }
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

  # Versioning methods

  # Get the next version number for this memory
  def next_version_number
    (versions.maximum(:version_number) || 0) + 1
  end

  # Get the latest version
  def latest_version
    versions.ordered.first
  end

  # Create a version from current state
  def create_version!(created_by: nil, change_reason: nil)
    versions.create!(
      account: account,
      version_number: next_version_number,
      title: title,
      content: content,
      memory_type: memory_type,
      metadata: metadata || {},
      created_by: created_by,
      change_reason: change_reason
    )
  end

  # List all versions with their info
  def version_history
    versions.ordered.map(&:display_info)
  end

  # Restore to a specific version
  def restore_version!(version_number, restored_by: nil, reason: nil)
    version = versions.find_by(version_number: version_number)
    return nil unless version

    version.restore_to_memory!(restored_by, reason)
  end

  private

  # Create initial version after memory is created
  def create_initial_version
    create_version!(
      created_by: created_by,
      change_reason: "Initial creation"
    )
  rescue => e
    Rails.logger.error "[Memory] Failed to create initial version: #{e.message}"
  end
end
