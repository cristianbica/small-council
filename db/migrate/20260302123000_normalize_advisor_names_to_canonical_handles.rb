class NormalizeAdvisorNamesToCanonicalHandles < ActiveRecord::Migration[8.1]
  NAME_FORMAT = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/

  def up
    advisor_rows = execute("SELECT id, space_id, name FROM advisors ORDER BY id")

    normalized_names_by_id = {}
    invalid_rows = []
    collisions = Hash.new { |hash, key| hash[key] = [] }

    advisor_rows.each do |row|
      advisor_id = row["id"]
      space_id = row["space_id"]
      original_name = row["name"]
      canonical_name = canonicalize_name(original_name)

      if canonical_name.blank? || !NAME_FORMAT.match?(canonical_name)
        invalid_rows << {
          advisor_id: advisor_id,
          space_id: space_id,
          original_name: original_name,
          canonical_name: canonical_name
        }
        next
      end

      normalized_names_by_id[advisor_id] = canonical_name
      collisions[[ space_id, canonical_name ]] << {
        advisor_id: advisor_id,
        original_name: original_name
      }
    end

    colliding_rows = collisions.select { |_key, entries| entries.size > 1 }

    if invalid_rows.any? || colliding_rows.any?
      raise ActiveRecord::MigrationError, <<~MSG
        Cannot normalize advisor names due to invalid canonical values or collisions.
        Invalid rows: #{invalid_rows.map(&:inspect).join("; ")}
        Collisions: #{format_collisions(colliding_rows)}
      MSG
    end

    normalized_names_by_id.each do |advisor_id, canonical_name|
      execute <<~SQL
        UPDATE advisors
        SET name = #{connection.quote(canonical_name)}
        WHERE id = #{advisor_id}
      SQL
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Canonical advisor name normalization is irreversible"
  end

  private

  def canonicalize_name(name)
    name.to_s
      .downcase
      .gsub(/[^a-z0-9-]+/, "-")
      .gsub(/-+/, "-")
      .gsub(/\A-+|-+\z/, "")
  end

  def format_collisions(colliding_rows)
    colliding_rows.map do |(space_id, canonical_name), entries|
      {
        space_id: space_id,
        canonical_name: canonical_name,
        advisors: entries
      }.inspect
    end.join("; ")
  end
end
