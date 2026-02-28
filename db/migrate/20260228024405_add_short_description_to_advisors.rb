class AddShortDescriptionToAdvisors < ActiveRecord::Migration[8.1]
  def change
    add_column :advisors, :short_description_ciphertext, :text
  end
end
