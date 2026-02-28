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
end
