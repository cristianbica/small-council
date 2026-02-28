class AddShortDescriptionToAdvisorsProperly < ActiveRecord::Migration[8.1]
  def change
    add_column :advisors, :short_description, :text
  end
end
