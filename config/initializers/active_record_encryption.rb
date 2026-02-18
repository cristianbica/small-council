# Active Record Encryption configuration for tests
# Using deterministic encryption key for consistent test behavior
Rails.application.configure do
  config.active_record.encryption.primary_key = "test_primary_key_32bytes_long!!"
  config.active_record.encryption.deterministic_key = "test_deterministic_key_32b"
  config.active_record.encryption.key_derivation_salt = "test_key_derivation_salt"
end
