# frozen_string_literal: true

class AddEncryptedMemoryToConversations < ActiveRecord::Migration[8.1]
  def change
    # Add columns for encrypted memory storage
    # Rails Active Record Encryption will automatically encrypt/decrypt
    add_column :conversations, :memory, :text
    add_column :conversations, :draft_memory, :text
  end
end
