module Versionable
  extend ActiveSupport::Concern

  included do
    has_many :versions, class_name: "RecordVersion", as: :versionable, dependent: :destroy

    # Attributes to track for versioning (override in model)
    class_attribute :versioned_attributes, default: []
    class_attribute :version_skip_attributes, default: %w[id created_at updated_at]

    before_commit :create_version_on_update, on: :update, if: :versioning_enabled?
  end

  class_methods do
    def track_versions(*attrs)
      self.versioned_attributes = attrs.map(&:to_s)
    end

    def skip_version_attributes(*attrs)
      self.version_skip_attributes = attrs.map(&:to_s)
    end
  end

  # Get next version number
  def next_version_number
    (versions.maximum(:version_number) || 0) + 1
  end

  # Latest version (most recent change)
  def latest_version
    versions.ordered.first
  end

  # First version (initial state)
  def first_version
    versions.chronological.first
  end

  # Get version at specific number
  def version_at(version_number)
    versions.find_by(version_number: version_number)
  end

  # Get all versions as linked list
  def version_chain
    versions.chronological.to_a
  end

  # Restore to a specific version
  # Restores the object_data from that version (previous state)
  def restore_version!(version_number, restored_by: nil)
    version = version_at(version_number)
    return nil unless version

    # Store restore context temporarily
    Current.version_whodunnit = restored_by if restored_by
    Current.version_metadata = { restore: true, from_version: version_number }

    # Update current record with version's stored data (previous state)
    attrs_to_restore = version.to_model_attributes.slice(*versionable_attributes)
    update!(attrs_to_restore)

    # Clear context
    Current.version_metadata = nil

    # Return the new version created by this restore
    latest_version
  end

  # Check if versioning is enabled (can override per model)
  def versioning_enabled?
    true
  end

  # Get previous state of versioned attributes (before the current change)
  def previous_versionable_state
    versionable_attributes.index_with { |attr| saved_changes[attr]&.first || send(attr) }
  end

  # Get attributes we care about versioning
  def versionable_attributes
    if versioned_attributes.any?
      versioned_attributes
    else
      attribute_names - version_skip_attributes
    end
  end

  # Check if version-worthy changes occurred
  def has_versionable_changes?
    return false unless saved_changes?

    versionable_attributes.any? { |attr| saved_changes.key?(attr) }
  end

  private

  def create_version_on_update
    return unless has_versionable_changes?

    # Get previous version for linking
    prev_version = latest_version

    # Store PREVIOUS (pre-change) state in the version
    # This represents "what the record looked like before this update"
    versions.create!(
      version_number: next_version_number,
      previous_version: prev_version,
      whodunnit: Current.version_whodunnit,
      object_data: previous_versionable_state,  # PREVIOUS values from saved_changes
      metadata: Current.version_metadata || {}
    )
  end
end
