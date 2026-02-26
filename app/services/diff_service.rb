# Service to generate highlighted diffs between text versions
class DiffService
  class << self
    # Generate a side-by-side diff with HTML highlighting
    # Returns a hash with :left (old) and :right (new) HTML
    def side_by_side_diff(old_text, new_text)
      return { left: "", right: new_text } if old_text.blank?
      return { left: old_text, right: "" } if new_text.blank?
      return { left: old_text, right: new_text } if old_text == new_text

      # Use diffy to get the diff
      diff = Diffy::Diff.new(old_text, new_text, context: nil)

      # Parse the diff and create side-by-side HTML
      left_html = []
      right_html = []

      diff.each do |line|
        # Skip the "No newline at end of file" messages
        next if line.include?("No newline at end of file")
        next if line.include?("\\ No newline")

        if line.start_with?("-")
          # Removed line - goes to left only
          content = escape_html(line[1..-1])
          left_html << %(<div class="diff-line diff-removed">#{content}</div>) unless content.blank?
        elsif line.start_with?("+")
          # Added line - goes to right only
          content = escape_html(line[1..-1])
          right_html << %(<div class="diff-line diff-added">#{content}</div>) unless content.blank?
        else
          # Unchanged line - goes to both
          content = escape_html(line)
          left_html << %(<div class="diff-line diff-unchanged">#{content}</div>) unless content.blank?
          right_html << %(<div class="diff-line diff-unchanged">#{content}</div>) unless content.blank?
        end
      end

      {
        left: left_html.join(""),
        right: right_html.join("")
      }
    end

    # Simple inline diff (for backwards compatibility)
    def diff(old_text, new_text)
      return new_text if old_text.blank?
      return "" if new_text.blank?

      diff = Diffy::Diff.new(old_text, new_text, context: 3, include_plus_and_minus_in_html: false)
      diff.to_s(:html)
    end

    private

    def escape_html(text)
      text.gsub("&", "&amp;")
          .gsub("<", "&lt;")
          .gsub(">", "&gt;")
          .rstrip  # Remove trailing whitespace
    end
  end
end
