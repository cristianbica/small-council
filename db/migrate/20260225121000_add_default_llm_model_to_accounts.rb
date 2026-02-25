class AddDefaultLLMModelToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_reference :accounts, :default_llm_model, foreign_key: { to_table: :llm_models }
  end
end
