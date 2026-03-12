class RecordVersion < ApplicationRecord
  belongs_to :versionable, polymorphic: true
  belongs_to :whodunnit, polymorphic: true, optional: true
  belongs_to :previous_version, class_name: "RecordVersion", optional: true
  has_one :next_version, class_name: "RecordVersion", foreign_key: :previous_version_id, dependent: nil

  validates :versionable, presence: true
  validates :version_number, presence: true, numericality: { greater_than: 0 }
  validates :version_number, uniqueness: { scope: [ :versionable_type, :versionable_id ] }

  scope :ordered, -> { order(version_number: :desc) }
  scope :chronological, -> { order(version_number: :asc) }

  # Get the "current" state that this version represents
  # (previous version's data = state before this change)
  def attribute_value(attr)
    object_data[attr.to_s]
  end

  # Get attribute values as a hash (convenience)
  def to_model_attributes
    object_data.with_indifferent_access
  end

  # Display name for who made the change
  def whodunnit_display
    return "Unknown" unless whodunnit.present?
    case whodunnit
    when User then whodunnit.email
    when Advisor then whodunnit.name
    else whodunnit.to_s
    end
  end

  def next_version
    super || begin
      version = RecordVersion.new
      version.object_data = versionable.attributes.slice(*versionable.versioned_attributes)
      version
    end
  end
end
