class MemoryVersion < ApplicationRecord
  acts_as_tenant :account

  belongs_to :memory
  belongs_to :created_by, polymorphic: true, optional: true

  # Encrypt content at rest
  encrypts :content

  # Validations
  validates :memory, presence: true
  validates :version_number, presence: true, numericality: { greater_than: 0 }
  validates :title, presence: true
  validates :content, presence: true
  validates :memory_type, presence: true
  validates :version_number, uniqueness: { scope: :memory_id }

  # Scopes
  scope :ordered, -> { order(version_number: :desc) }
  scope :recent, -> { order(created_at: :desc) }

  # Get display info for the version
  def display_info
    {
      version: version_number,
      title: title,
      type: memory_type,
      created_at: created_at.strftime("%Y-%m-%d %H:%M"),
      created_by: created_by_display,
      change_reason: change_reason,
      preview: content.truncate(100)
    }
  end

  # Creator display name
  def created_by_display
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

  # Restore this version to the memory
  def restore_to_memory!(restored_by = nil, reason = nil)
    memory.update!(
      title: title,
      content: content,
      memory_type: memory_type,
      metadata: metadata || {},
      updated_by: restored_by
    )

    # Create a new version tracking the restore
    memory.versions.create!(
      version_number: memory.next_version_number,
      title: title,
      content: content,
      memory_type: memory_type,
      metadata: metadata || {},
      created_by: restored_by,
      change_reason: "Restored from version #{version_number}#{reason.present? ? ": #{reason}" : ""}"
    )
  end
end
