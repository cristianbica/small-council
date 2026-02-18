require "test_helper"

class UserTest < ActiveSupport::TestCase
  def setup
    @account = Account.create!(name: "Test Account", slug: "test-account-users")
  end

  test "valid with email, account, and password" do
    user = @account.users.new(email: "user@example.com", password: "password123")
    assert user.valid?
  end

  test "invalid without email" do
    user = @account.users.new(password: "password123")
    assert_not user.valid?
    assert_includes user.errors[:email], "can't be blank"
  end

  test "invalid without account" do
    user = User.new(email: "orphan@example.com", password: "password123")
    assert_not user.valid?
    assert_includes user.errors[:account], "can't be blank"
  end

  test "invalid without password" do
    user = @account.users.new(email: "user@example.com")
    assert_not user.valid?
    assert_includes user.errors[:password], "can't be blank"
  end

  test "invalid with malformed email" do
    user = @account.users.new(email: "not-an-email", password: "password123")
    assert_not user.valid?
    assert_includes user.errors[:email], "is invalid"
  end

  test "invalid with duplicate email within same account" do
    @account.users.create!(email: "duplicate@example.com", password: "password123")
    user = @account.users.new(email: "duplicate@example.com", password: "password123")
    assert_not user.valid?
    assert_includes user.errors[:email], "has already been taken"
  end

  test "valid with same email in different accounts" do
    @account.users.create!(email: "shared@example.com", password: "password123")
    other_account = Account.create!(name: "Other", slug: "other-account")
    user = other_account.users.new(email: "shared@example.com", password: "password123")
    assert user.valid?
  end

  # Association tests
  test "belongs to account" do
    user = User.new
    assert_respond_to user, :account
  end

  test "has many councils" do
    user = User.new
    assert_respond_to user, :councils
  end

  test "has many conversations" do
    user = User.new
    assert_respond_to user, :conversations
  end

  test "has many messages as sender polymorphic association" do
    user = User.new
    assert_respond_to user, :messages
  end

  test "dependent destroy removes associated councils" do
    user = @account.users.create!(email: "council-owner@example.com", password: "password123")
    user.councils.create!(name: "User Council", account: @account)
    assert_difference("Council.count", -1) do
      user.destroy
    end
  end

  test "dependent destroy removes associated conversations" do
    user = @account.users.create!(email: "conv-owner@example.com", password: "password123")
    council = @account.councils.create!(name: "Test Council", user: user)
    user.conversations.create!(council: council, account: @account)
    assert_difference("Conversation.count", -1) do
      user.destroy
    end
  end

  # Enum tests
  test "defaults to member role" do
    user = @account.users.create!(email: "default-role@example.com", password: "password123")
    assert_equal "member", user.role
    assert user.member?
  end

  test "can be assigned admin role" do
    user = @account.users.create!(email: "admin-role@example.com", password: "password123", role: "admin")
    assert_equal "admin", user.role
    assert user.admin?
  end

  test "role enum methods work" do
    user = @account.users.create!(email: "role-methods@example.com", password: "password123")
    assert user.member?
    assert_not user.admin?

    user.admin!
    assert user.admin?
    assert_not user.member?
  end

  test "invalid role raises ArgumentError" do
    assert_raises(ArgumentError) do
      @account.users.create!(email: "invalid-role@example.com", password: "password123", role: "superuser")
    end
  end

  test "valid roles are member and admin" do
    assert_equal({ "member" => "member", "admin" => "admin" }, User.roles)
  end

  # Authentication tests
  test "should have secure password" do
    user = User.new(email: "test@example.com", account: @account)
    user.password = "password123"
    assert user.save
    assert user.authenticate("password123")
    assert_not user.authenticate("wrongpassword")
  end

  test "should require password on create" do
    user = User.new(email: "test@example.com", account: @account)
    assert_not user.valid?
    assert_includes user.errors[:password], "can't be blank"
  end

  test "has many sessions" do
    user = @account.users.new
    assert_respond_to user, :sessions
  end

  test "sessions are dependent destroyed" do
    user = @account.users.create!(email: "session-test@example.com", password: "password123")
    user.sessions.create!
    assert_difference("Session.count", -1) do
      user.destroy
    end
  end
end
