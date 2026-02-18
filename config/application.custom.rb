# frozen_string_literal: true

# Custom Application Configuration
# =====================================
#
# Purpose: App-specific overrides that survive Rails upgrades.
#
# This file is loaded AFTER config/application.rb but BEFORE initializers.
# Use it to add custom initializers or override Rails defaults without
# touching generated files.
#
# Load Order:
#   1. config/application.rb (Rails generated)
#   2. config/application.custom.rb (this file)
#   3. config/environments/#{Rails.env}.rb (Rails generated)
#   4. config/environments/#{Rails.env}.custom.rb (via initializer below, if exists)
#   5. config/initializers/* (via load_config_initializers)
#   6. config/initializers/*.custom.rb (if added here)
#
# Why This Helps:
#   Running `rails app:update` overwrites Rails-generated files but preserves
#   files it doesn't know about. By keeping overrides in .custom.rb files,
#   you avoid 3-way merge hell during upgrades.
#
# Idempotency Warning:
#   This file runs on EVERY boot. All code here must be idempotent
#   (safe to run multiple times without side effects).

module SmallCouncil
  class Application < Rails::Application
    # Load environment-specific custom overrides
    # This initializer runs after load_config_initializers but before other app initializers
    initializer :load_custom_environment_config, after: :load_config_initializers do
      custom_file = Rails.root.join("config/environments", "#{Rails.env}.custom.rb")
      if custom_file.exist?
        Rails.logger.debug { "Loading custom environment config: #{custom_file}" }
        load custom_file
      end
    end

    # Example: Load custom initializers
    # Uncomment to enable loading of custom initializer files
    # initializer :load_custom_initializers, before: :load_config_initializers do
    #   Dir[Rails.root.join("config/initializers/*.custom.rb")].each do |file|
    #     Rails.logger.debug { "Loading custom initializer: #{file}" }
    #     load file
    #   end
    # end
  end
end
