class EnforceCanonicalAdvisorNames < ActiveRecord::Migration[8.1]
  def up
    remove_index :advisors, name: "index_advisors_on_space_id_and_name"

    add_index :advisors,
      "space_id, lower(name)",
      unique: true,
      name: "index_advisors_on_space_id_and_lower_name_unique"

    add_check_constraint :advisors,
      "name ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'",
      name: "advisors_name_canonical_format"
  end

  def down
    remove_check_constraint :advisors, name: "advisors_name_canonical_format"

    remove_index :advisors, name: "index_advisors_on_space_id_and_lower_name_unique"

    add_index :advisors, [ :space_id, :name ], name: "index_advisors_on_space_id_and_name"
  end
end
