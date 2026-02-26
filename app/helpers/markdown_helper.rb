module MarkdownHelper
  def markdown_to_html(text)
    return "" if text.blank?

    Commonmarker.to_html(text, options: {
      parse: {
        smart: true
      },
      render: {
        hardbreaks: false,
        unsafe: false
      }
    }).html_safe
  end
end
