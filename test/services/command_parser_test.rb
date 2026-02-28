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

  test "command? returns true for valid commands" do
    assert CommandParser.command?("/invite @advisor")
  end

  test "command? returns false for non-commands" do
    assert_not CommandParser.command?("Hello world")
    assert_not CommandParser.command?("@advisor help")
    assert_not CommandParser.command?("")
    assert_not CommandParser.command?(nil)
  end

  test "command? returns false for unknown commands" do
    assert_not CommandParser.command?("/unknown @advisor")
  end

  test "available_commands returns list of command names" do
    commands = CommandParser.available_commands
    assert_includes commands, "invite"
  end
end
