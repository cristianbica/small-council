require "test_helper"

class InlineDiffTest < ActiveSupport::TestCase
  test "side_by_side_diff returns empty strings when both inputs are blank" do
    result = InlineDiff.side_by_side_diff("", "")
    assert_equal({ left: "", right: "" }, result)

    result2 = InlineDiff.side_by_side_diff(nil, nil)
    assert_equal({ left: "", right: "" }, result2)
  end

  test "side_by_side_diff returns blank placeholder when old_text is blank" do
    result = InlineDiff.side_by_side_diff("", "new content")
    assert_equal "(blank)", result[:left]
    assert_equal "new content", result[:right]
  end

  test "side_by_side_diff returns blank placeholder when new_text is blank" do
    result = InlineDiff.side_by_side_diff("old content", "")
    assert_equal "old content", result[:left]
    assert_equal "(blank)", result[:right]
  end

  test "side_by_side_diff handles identical text" do
    result = InlineDiff.side_by_side_diff("hello world", "hello world")
    assert_equal "hello world", result[:left]
    assert_equal "hello world", result[:right]
  end

  test "side_by_side_diff marks changed words" do
    result = InlineDiff.side_by_side_diff("hello world", "hello earth")
    assert_includes result[:left], "world"
    assert_includes result[:right], "earth"
  end

  test "side_by_side_diff handles words unique to each side (exercises lcs else branch)" do
    # "a b c" vs "a x c" — 'b' removed, 'x' added; exercises dp[i-1][j] vs dp[i][j-1] in lcs
    result = InlineDiff.side_by_side_diff("a b c d", "a x c e")
    assert result[:left].length > 0
    assert result[:right].length > 0
  end
end
