# frozen_string_literal: true

require "test_helper"

module AI
  module Schemas
    class CouncilProfileSchemaTest < ActiveSupport::TestCase
      test "to_json_schema returns valid schema structure" do
        schema = CouncilProfileSchema.new
        json_schema = schema.to_json_schema

        assert_equal "object", json_schema[:type]
        assert json_schema[:properties].key?(:name)
        assert json_schema[:properties].key?(:description)
      end

      test "schema requires name and description" do
        schema = CouncilProfileSchema.new
        json_schema = schema.to_json_schema

        required = json_schema[:required]
        assert_includes required, "name"
        assert_includes required, "description"
        assert_equal 2, required.length
      end

      test "schema does not allow additional properties" do
        schema = CouncilProfileSchema.new
        json_schema = schema.to_json_schema

        assert_equal false, json_schema[:additionalProperties]
      end

      test "name property has correct type and description" do
        schema = CouncilProfileSchema.new
        json_schema = schema.to_json_schema

        name_prop = json_schema[:properties][:name]
        assert_equal "string", name_prop[:type]
        assert name_prop[:description].include?("name")
      end

      test "description property has correct type and description" do
        schema = CouncilProfileSchema.new
        json_schema = schema.to_json_schema

        desc_prop = json_schema[:properties][:description]
        assert_equal "string", desc_prop[:type]
        assert desc_prop[:description].include?("description")
      end
    end
  end
end
