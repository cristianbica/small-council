class AddRulesOfEngagementToConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :conversations, :rules_of_engagement, :string, default: "round_robin"
    add_index :conversations, :rules_of_engagement
  end
end
