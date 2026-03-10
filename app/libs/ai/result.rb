# frozen_string_literal: true

module AI
  class Result
    delegate_missing_to :response, allow_nil: true

    attr_accessor :response, :error
    attr_writer :content

    def content
      @content || ("Error: #{error}" if error) || response&.content
    end

    def success?
      !failure?
    end

    def failure?
      error.present? || content.blank?
    end
  end
end
