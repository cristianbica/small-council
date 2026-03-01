# test/services/command_parser_test.rb
require "test_helper"

class CommandParserTest < ActiveSupport::TestCase
  test "parse returns nil for non-command messages" do
    assert_nil CommandParser.parse("Hello world")
    assert_nil CommandParser.parse("@advisor help")
    assert_nil CommandParser.parse("")
    assert_nil CommandParser.parse(nil)
  end

  test "parse returns command for valid commands" do
    cmd = CommandParser.parse("/invite @advisor")
    assert_instance_of Commands::InviteCommand, cmd
    assert_equal [ "@advisor" ], cmd.args
  end

  test "parse is case-insensitive for command names" do
    cmd = CommandParser.parse("/INVITE @advisor")
    assert_instance_of Commands::InviteCommand, cmd

    cmd = CommandParser.parse("/Invite @advisor")
    assert_instance_of Commands::InviteCommand, cmd
  end

  test "parse handles commands with multiple arguments" do
    cmd = CommandParser.parse("/invite @advisor @other")
    assert_equal [ "@advisor", "@other" ], cmd.args
  end

  test "parse returns nil for unknown commands" do
    assert_nil CommandParser.parse("/unknown @advisor")
    assert_nil CommandParser.parse("/help")
  end
end
