require "test_helper"

class MarkdownHelperTest < ActionView::TestCase
  include MarkdownHelper

  test "markdown_to_html returns empty string for blank text" do
    assert_equal "", markdown_to_html(nil)
    assert_equal "", markdown_to_html("")
    assert_equal "", markdown_to_html("   ")
  end

  test "markdown_to_html converts markdown to html for non-blank text" do
    result = markdown_to_html("**bold**")
    assert_includes result, "<strong>bold</strong>"
  end

  test "markdown_to_html converts markdown tables to html" do
    markdown = <<~MD
      | Header 1 | Header 2 |
      |----------|----------|
      | Cell 1   | Cell 2   |
    MD

    result = markdown_to_html(markdown)
    assert_includes result, "<table>"
    assert_includes result, "<thead>"
    assert_includes result, "<tbody>"
    assert_includes result, "<th>Header 1</th>"
    assert_includes result, "<td>Cell 1</td>"
  end
end
