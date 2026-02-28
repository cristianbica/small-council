class RemoveShortDescriptionCiphertextFromAdvisors < ActiveRecord::Migration[8.1]
  def change
    remove_column :advisors, :short_description_ciphertext, :text if column_exists?(:advisors, :short_description_ciphertext)
  end
end
