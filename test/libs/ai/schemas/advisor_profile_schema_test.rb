# frozen_string_literal: true

require "test_helper"

module AI
  module Schemas
    class AdvisorProfileSchemaTest < ActiveSupport::TestCase
      test "to_json_schema returns valid schema structure" do
        schema = AdvisorProfileSchema.new
        json_schema = schema.to_json_schema

        assert_equal "object", json_schema[:type]
        assert json_schema[:properties].key?(:name)
        assert json_schema[:properties].key?(:short_description)
        assert json_schema[:properties].key?(:system_prompt)
      end

      test "schema requires all fields" do
        schema = AdvisorProfileSchema.new
        json_schema = schema.to_json_schema

        required = json_schema[:required]
        assert_includes required, "name"
        assert_includes required, "short_description"
        assert_includes required, "system_prompt"
        assert_equal 3, required.length
      end

      test "schema does not allow additional properties" do
        schema = AdvisorProfileSchema.new
        json_schema = schema.to_json_schema

        assert_equal false, json_schema[:additionalProperties]
      end

      test "name property has correct type and description" do
        schema = AdvisorProfileSchema.new
        json_schema = schema.to_json_schema

        name_prop = json_schema[:properties][:name]
        assert_equal "string", name_prop[:type]
        assert name_prop[:description].include?("name")
      end

      test "short_description property has correct type and description" do
        schema = AdvisorProfileSchema.new
        json_schema = schema.to_json_schema

        desc_prop = json_schema[:properties][:short_description]
        assert_equal "string", desc_prop[:type]
        assert desc_prop[:description].include?("description")
      end

      test "system_prompt property has correct type and description" do
        schema = AdvisorProfileSchema.new
        json_schema = schema.to_json_schema

        prompt_prop = json_schema[:properties][:system_prompt]
        assert_equal "string", prompt_prop[:type]
        assert prompt_prop[:description].include?("prompt")
      end
    end
  end
end
