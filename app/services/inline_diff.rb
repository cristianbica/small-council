# Simple inline diff implementation for views
# Replaces the old DiffService with inline logic
module InlineDiff
  # Simple word-level diff for display
  def self.side_by_side_diff(old_text, new_text)
    return { left: "", right: "" } if old_text.blank? && new_text.blank?
    return { left: "(blank)", right: new_text } if old_text.blank?
    return { left: old_text, right: "(blank)" } if new_text.blank?

    old_words = old_text.to_s.split(/(\s+)/)
    new_words = new_text.to_s.split(/(\s+)/)

    # Simple LCS (Longest Common Subsequence) diff
    lcs = compute_lcs(old_words, new_words)

    left_result = []
    right_result = []

    old_idx = 0
    new_idx = 0
    lcs_idx = 0

    while old_idx < old_words.length || new_idx < new_words.length
      if lcs_idx < lcs.length && old_words[old_idx] == lcs[lcs_idx] && new_words[new_idx] == lcs[lcs_idx]
        # Word is the same in both
        left_result << escape_html(old_words[old_idx])
        right_result << escape_html(new_words[new_idx])
        old_idx += 1
        new_idx += 1
        lcs_idx += 1
      elsif old_idx < old_words.length && (lcs_idx >= lcs.length || old_words[old_idx] != lcs[lcs_idx])
        # Word was removed
        left_result << "<mark class=\"bg-red-200\">#{escape_html(old_words[old_idx])}</mark>"
        old_idx += 1
      elsif new_idx < new_words.length && (lcs_idx >= lcs.length || new_words[new_idx] != lcs[lcs_idx])
        # Word was added
        right_result << "<mark class=\"bg-green-200\">#{escape_html(new_words[new_idx])}</mark>"
        new_idx += 1
      end
    end

    {
      left: left_result.join,
      right: right_result.join
    }
  end

  private

  def self.escape_html(text)
    text.gsub(/&/, "&amp;")
        .gsub(/</, "&lt;")
        .gsub(/>/, "&gt;")
  end

  def self.compute_lcs(old_words, new_words)
    # Dynamic programming approach for LCS
    m = old_words.length
    n = new_words.length

    # Create DP table
    dp = Array.new(m + 1) { Array.new(n + 1, 0) }

    # Fill DP table
    (1..m).each do |i|
      (1..n).each do |j|
        if old_words[i - 1] == new_words[j - 1]
          dp[i][j] = dp[i - 1][j - 1] + 1
        else
          dp[i][j] = [ dp[i - 1][j], dp[i][j - 1] ].max
        end
      end
    end

    # Backtrack to find LCS
    lcs = []
    i = m
    j = n

    while i > 0 && j > 0
      if old_words[i - 1] == new_words[j - 1]
        lcs.unshift(old_words[i - 1])
        i -= 1
        j -= 1
      elsif dp[i - 1][j] > dp[i][j - 1]
        i -= 1
      else
        j -= 1
      end
    end

    lcs
  end
end
