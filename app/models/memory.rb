class Memory < ApplicationRecord
  acts_as_tenant :account

  belongs_to :account
  belongs_to :space
  belongs_to :source, polymorphic: true, optional: true
  belongs_to :created_by, polymorphic: true, optional: true
  belongs_to :updated_by, polymorphic: true, optional: true

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
  scope :conversation_summaries, -> { where(memory_type: "conversation_summary") }
  scope :conversation_notes, -> { where(memory_type: "conversation_notes") }
  scope :knowledge, -> { where(memory_type: "knowledge") }
  scope :ordered, -> { order(position: :asc, created_at: :desc) }
  scope :recent, -> { order(updated_at: :desc) }

  # Search scope
  scope :search, ->(query) {
    return all if query.blank?
    where("title ILIKE ? OR content ILIKE ?", "%#{query}%", "%#{query}%")
  }

  # Type predicates
  def summary? = memory_type == "summary"
  def conversation_summary? = memory_type == "conversation_summary"
  def conversation_notes? = memory_type == "conversation_notes"
  def knowledge? = memory_type == "knowledge"

  # Status predicates
  def active? = status == "active"
  def archived? = status == "archived"
  def draft? = status == "draft"

  # Archive this memory
  def archive!(updater = nil)
    update!(status: "archived", updated_by: updater)
  end

  # Activate this memory
  def activate!(updater = nil)
    update!(status: "active", updated_by: updater)
  end

  # Update position in list
  def move_to!(new_position, updater = nil)
    update!(position: new_position, updated_by: updater)
  end

  # Get a truncated preview of the content
  def content_preview(length: 200)
    return "" if content.blank?
    content.truncate(length)
  end

  # Get metadata value with default
  def metadata_value(key, default = nil)
    metadata.fetch(key.to_s, default)
  end

  # Set metadata value
  def set_metadata(key, value, updater = nil)
    new_metadata = metadata.merge(key.to_s => value)
    update!(metadata: new_metadata, updated_by: updater)
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

  # Class method to get the primary summary for a space
  # Only the summary memory type is auto-fed to AI agents
  def self.primary_summary_for(space)
    return nil unless space.present?
    space.memories
         .active
         .summary_type
         .recent
         .first
  end

  # Class method to create a primary summary memory for a space
  def self.create_primary_summary!(space:, title:, content:, creator: nil)
    create!(
      account: space.account,
      space: space,
      title: title,
      content: content,
      memory_type: "summary",
      status: "active",
      position: 0,
      created_by: creator,
      updated_by: creator
    )
  end

  # Class method to create a conversation summary memory
  def self.create_conversation_summary!(conversation:, title:, content:, creator: nil)
    create!(
      account: conversation.account,
      space: conversation.council.space,
      source: conversation,
      title: title,
      content: content,
      memory_type: "conversation_summary",
      status: "active",
      created_by: creator,
      updated_by: creator
    )
  end

  # Class method to create conversation notes memory
  def self.create_conversation_notes!(conversation:, title:, content:, creator: nil)
    create!(
      account: conversation.account,
      space: conversation.council.space,
      source: conversation,
      title: title,
      content: content,
      memory_type: "conversation_notes",
      status: "active",
      created_by: creator,
      updated_by: creator
    )
  end
end
