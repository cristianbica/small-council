# Active Record Encryption Configuration
# Encrypts sensitive data at rest

Rails.application.configure do
  if Rails.env.test?
    # Deterministic keys for consistent test behavior
    config.active_record.encryption.primary_key = "test_primary_key_32bytes_long!!"
    config.active_record.encryption.deterministic_key = "test_deterministic_key_32b"
    config.active_record.encryption.key_derivation_salt = "test_key_derivation_salt"
  else
    # Production/Development: Use environment variables or credentials
    config.active_record.encryption.primary_key = ENV["ACTIVE_RECORD_ENCRYPTION_KEY"] || Rails.application.credentials.active_record_encryption&.primary_key
    config.active_record.encryption.deterministic_key = ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"] || Rails.application.credentials.active_record_encryption&.deterministic_key
    config.active_record.encryption.key_derivation_salt = ENV["ACTIVE_RECORD_ENCRYPTION_SALT"] || Rails.application.credentials.active_record_encryption&.key_derivation_salt || "salt_#{Rails.env}"
  end

  # Support unencrypted data during migration
  config.active_record.encryption.support_unencrypted_data = true
end
