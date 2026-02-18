class AddCouncilIdToAdvisors < ActiveRecord::Migration[8.1]
  def change
    add_reference :advisors, :council, foreign_key: true, null: true
  end
end
