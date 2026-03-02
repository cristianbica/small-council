# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_03_02_110000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "accounts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "default_llm_model_id"
    t.string "name", null: false
    t.jsonb "settings", default: {}
    t.string "slug", null: false
    t.datetime "trial_ends_at"
    t.datetime "updated_at", null: false
    t.index ["default_llm_model_id"], name: "index_accounts_on_default_llm_model_id"
    t.index ["settings"], name: "index_accounts_on_settings", using: :gin
    t.index ["slug"], name: "index_accounts_on_slug", unique: true
  end

  create_table "action_text_rich_texts", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.datetime "updated_at", null: false
    t.index ["record_type", "record_id", "name"], name: "index_action_text_rich_texts_uniqueness", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "advisors", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.boolean "global", default: false
    t.boolean "is_scribe", default: false
    t.bigint "llm_model_id"
    t.jsonb "metadata", default: {}
    t.jsonb "model_config", default: {}
    t.string "name", null: false
    t.text "short_description"
    t.bigint "space_id"
    t.text "system_prompt", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "space_id"], name: "index_advisors_on_account_id_and_space_id"
    t.index ["account_id"], name: "index_advisors_on_account_id"
    t.index ["is_scribe"], name: "index_advisors_on_is_scribe"
    t.index ["llm_model_id"], name: "index_advisors_on_llm_model_id"
    t.index ["metadata"], name: "index_advisors_on_metadata", using: :gin
    t.index ["model_config"], name: "index_advisors_on_model_config", using: :gin
    t.index ["space_id", "name"], name: "index_advisors_on_space_id_and_name"
    t.index ["space_id"], name: "index_advisors_on_space_id"
  end

  create_table "conversation_participants", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "advisor_id", null: false
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.integer "position", default: 0
    t.string "role", default: "advisor", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_conversation_participants_on_account_id"
    t.index ["advisor_id"], name: "index_conversation_participants_on_advisor_id"
    t.index ["conversation_id", "advisor_id"], name: "index_conversation_participants_unique", unique: true
    t.index ["conversation_id"], name: "index_conversation_participants_on_conversation_id"
  end

  create_table "conversations", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.jsonb "context", default: {}
    t.string "conversation_type", default: "council_meeting", null: false
    t.bigint "council_id"
    t.datetime "created_at", null: false
    t.text "draft_memory"
    t.datetime "last_message_at"
    t.text "memory"
    t.string "roe_type", default: "open", null: false
    t.string "rules_of_engagement", default: "round_robin"
    t.integer "scribe_initiated_count", default: 0
    t.bigint "space_id", null: false
    t.string "status", default: "active"
    t.string "title"
    t.boolean "title_locked", default: false, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["account_id", "last_message_at"], name: "index_conversations_on_account_id_and_last_message_at"
    t.index ["account_id"], name: "index_conversations_on_account_id"
    t.index ["context"], name: "index_conversations_on_context", using: :gin
    t.index ["conversation_type"], name: "index_conversations_on_conversation_type"
    t.index ["council_id"], name: "index_conversations_on_council_id"
    t.index ["roe_type"], name: "index_conversations_on_roe_type"
    t.index ["rules_of_engagement"], name: "index_conversations_on_rules_of_engagement"
    t.index ["space_id"], name: "index_conversations_on_space_id"
    t.index ["user_id"], name: "index_conversations_on_user_id"
  end

  create_table "council_advisors", force: :cascade do |t|
    t.bigint "advisor_id", null: false
    t.bigint "council_id", null: false
    t.datetime "created_at", null: false
    t.jsonb "custom_prompt_override", default: {}
    t.integer "position", default: 0
    t.datetime "updated_at", null: false
    t.index ["advisor_id"], name: "index_council_advisors_on_advisor_id"
    t.index ["council_id", "advisor_id"], name: "index_council_advisors_on_council_id_and_advisor_id", unique: true
    t.index ["council_id"], name: "index_council_advisors_on_council_id"
  end

  create_table "councils", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.jsonb "configuration", default: {}
    t.datetime "created_at", null: false
    t.text "description"
    t.text "memory"
    t.string "name", null: false
    t.bigint "space_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.string "visibility", default: "private"
    t.index ["account_id", "name"], name: "index_councils_on_account_id_and_name"
    t.index ["account_id"], name: "index_councils_on_account_id"
    t.index ["configuration"], name: "index_councils_on_configuration", using: :gin
    t.index ["space_id", "created_at"], name: "index_councils_on_space_id_and_created_at"
    t.index ["space_id"], name: "index_councils_on_space_id"
    t.index ["user_id"], name: "index_councils_on_user_id"
  end

  create_table "llm_models", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.jsonb "capabilities", default: {}, null: false
    t.integer "context_window"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.boolean "deprecated", default: false
    t.boolean "enabled", default: true
    t.boolean "free", default: false, null: false
    t.string "identifier", null: false
    t.jsonb "metadata", default: {}
    t.string "name", null: false
    t.bigint "provider_id", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_llm_models_on_account_id"
    t.index ["capabilities"], name: "index_llm_models_on_capabilities", using: :gin
    t.index ["context_window"], name: "index_llm_models_on_context_window"
    t.index ["deleted_at"], name: "index_llm_models_on_deleted_at"
    t.index ["free"], name: "index_llm_models_on_free"
    t.index ["metadata"], name: "index_llm_models_on_metadata", using: :gin
    t.index ["provider_id", "identifier"], name: "index_llm_models_on_provider_id_and_identifier", unique: true
    t.index ["provider_id"], name: "index_llm_models_on_provider_id"
  end

  create_table "memories", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.string "created_by_type"
    t.string "memory_type", default: "knowledge", null: false
    t.jsonb "metadata", default: {}
    t.integer "position", default: 0
    t.bigint "source_id"
    t.string "source_type"
    t.bigint "space_id", null: false
    t.string "status", default: "active"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.bigint "updated_by_id"
    t.string "updated_by_type"
    t.index ["account_id", "created_at"], name: "index_memories_on_account_id_and_created_at"
    t.index ["account_id"], name: "index_memories_on_account_id"
    t.index ["created_by_type", "created_by_id"], name: "index_memories_on_created_by"
    t.index ["metadata"], name: "index_memories_on_metadata", using: :gin
    t.index ["source_type", "source_id"], name: "index_memories_on_source"
    t.index ["space_id", "memory_type"], name: "index_memories_on_space_id_and_memory_type"
    t.index ["space_id", "position"], name: "index_memories_on_space_id_and_position"
    t.index ["space_id", "status"], name: "index_memories_on_space_id_and_status"
    t.index ["space_id"], name: "index_memories_on_space_id"
    t.index ["updated_by_type", "updated_by_id"], name: "index_memories_on_updated_by"
  end

  create_table "memory_versions", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.text "change_reason"
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.string "created_by_type"
    t.bigint "memory_id", null: false
    t.string "memory_type", null: false
    t.jsonb "metadata", default: {}
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "version_number", null: false
    t.index ["account_id"], name: "index_memory_versions_on_account_id"
    t.index ["created_by_type", "created_by_id"], name: "index_memory_versions_on_created_by"
    t.index ["memory_id", "created_at"], name: "index_memory_versions_on_memory_id_and_created_at"
    t.index ["memory_id", "version_number"], name: "index_memory_versions_on_memory_id_and_version_number", unique: true
    t.index ["memory_id"], name: "index_memory_versions_on_memory_id"
  end

  create_table "messages", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.text "content"
    t.jsonb "content_blocks", default: []
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.jsonb "debug_data", default: {}
    t.bigint "in_reply_to_id"
    t.jsonb "metadata", default: {}
    t.jsonb "pending_advisor_ids", default: []
    t.text "prompt_text"
    t.string "role", null: false
    t.bigint "sender_id", null: false
    t.string "sender_type", null: false
    t.string "status", default: "complete"
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_messages_on_account_id"
    t.index ["conversation_id", "created_at"], name: "index_messages_on_conversation_id_and_created_at"
    t.index ["conversation_id"], name: "index_messages_on_conversation_id"
    t.index ["debug_data"], name: "index_messages_on_debug_data", using: :gin
    t.index ["in_reply_to_id"], name: "index_messages_on_in_reply_to_id"
    t.index ["metadata"], name: "index_messages_on_metadata", using: :gin
    t.index ["pending_advisor_ids"], name: "index_messages_on_pending_advisor_ids", using: :gin
    t.index ["sender_type", "sender_id"], name: "index_messages_on_sender"
  end

  create_table "model_interactions", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.float "duration_ms"
    t.integer "input_tokens", default: 0
    t.string "interaction_type", default: "chat", null: false
    t.bigint "message_id", null: false
    t.string "model_identifier"
    t.integer "output_tokens", default: 0
    t.jsonb "request_payload", default: {}, null: false
    t.jsonb "response_payload", default: {}, null: false
    t.integer "sequence", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_model_interactions_on_account_id"
    t.index ["interaction_type"], name: "index_model_interactions_on_interaction_type"
    t.index ["message_id", "sequence"], name: "index_model_interactions_on_message_id_and_sequence"
    t.index ["message_id"], name: "index_model_interactions_on_message_id"
    t.index ["request_payload"], name: "index_model_interactions_on_request_payload", using: :gin
    t.index ["response_payload"], name: "index_model_interactions_on_response_payload", using: :gin
  end

  create_table "providers", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.jsonb "credentials", default: {}
    t.boolean "enabled", default: true
    t.string "name", null: false
    t.string "provider_type", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "name"], name: "index_providers_on_account_id_and_name", unique: true
    t.index ["account_id"], name: "index_providers_on_account_id"
    t.index ["credentials"], name: "index_providers_on_credentials", using: :gin
  end

  create_table "scribe_chat_messages", force: :cascade do |t|
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}
    t.string "role", null: false
    t.bigint "space_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["space_id", "user_id", "created_at"], name: "idx_on_space_id_user_id_created_at_55079c19f6"
    t.index ["space_id"], name: "index_scribe_chat_messages_on_space_id"
    t.index ["user_id"], name: "index_scribe_chat_messages_on_user_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "spaces", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.text "memory"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "name"], name: "index_spaces_on_account_id_and_name", unique: true
    t.index ["account_id"], name: "index_spaces_on_account_id"
  end

  create_table "usage_records", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.integer "cost_cents", default: 0
    t.datetime "created_at", null: false
    t.integer "input_tokens", default: 0
    t.bigint "message_id"
    t.string "model", null: false
    t.integer "output_tokens", default: 0
    t.string "provider", null: false
    t.datetime "recorded_at"
    t.datetime "updated_at", null: false
    t.index ["account_id", "recorded_at"], name: "index_usage_records_on_account_id_and_recorded_at"
    t.index ["account_id"], name: "index_usage_records_on_account_id"
    t.index ["message_id"], name: "index_usage_records_on_message_id"
  end

  create_table "users", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "password_digest"
    t.jsonb "preferences", default: {}
    t.string "role", default: "member"
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_users_on_account_id"
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "accounts", "llm_models", column: "default_llm_model_id"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "advisors", "accounts"
  add_foreign_key "advisors", "llm_models"
  add_foreign_key "advisors", "spaces"
  add_foreign_key "conversation_participants", "accounts"
  add_foreign_key "conversation_participants", "advisors"
  add_foreign_key "conversation_participants", "conversations"
  add_foreign_key "conversations", "accounts"
  add_foreign_key "conversations", "councils"
  add_foreign_key "conversations", "spaces"
  add_foreign_key "conversations", "users"
  add_foreign_key "council_advisors", "advisors"
  add_foreign_key "council_advisors", "councils"
  add_foreign_key "councils", "accounts"
  add_foreign_key "councils", "spaces"
  add_foreign_key "councils", "users"
  add_foreign_key "llm_models", "accounts"
  add_foreign_key "llm_models", "providers"
  add_foreign_key "memories", "accounts"
  add_foreign_key "memories", "spaces"
  add_foreign_key "memory_versions", "accounts"
  add_foreign_key "memory_versions", "memories"
  add_foreign_key "messages", "accounts"
  add_foreign_key "messages", "conversations"
  add_foreign_key "messages", "messages", column: "in_reply_to_id"
  add_foreign_key "model_interactions", "accounts"
  add_foreign_key "model_interactions", "messages"
  add_foreign_key "providers", "accounts"
  add_foreign_key "scribe_chat_messages", "spaces"
  add_foreign_key "scribe_chat_messages", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "spaces", "accounts"
  add_foreign_key "usage_records", "accounts"
  add_foreign_key "usage_records", "messages"
  add_foreign_key "users", "accounts"
end
