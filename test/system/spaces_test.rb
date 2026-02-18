require "application_system_test_case"

class SpacesTest < ApplicationSystemTestCase
  def setup
    @account = accounts(:one)
    @user = users(:one)
    # Ensure account has a space
    @space = @account.spaces.first || @account.spaces.create!(name: "General")
  end

  test "visiting the spaces index" do
    sign_in_as(@user)
    visit spaces_url
    assert_selector "h1", text: "Spaces"
  end

  test "creating a space" do
    sign_in_as(@user)
    visit spaces_url
    click_on "New Space"

    fill_in "Name", with: "Product Team"
    fill_in "Description", with: "For product-related councils"
    click_on "Create Space"

    assert_text "Space created successfully"
    assert_selector "h1", text: "Councils"
    assert_text "in Product Team"
  end

  test "switching spaces via link" do
    space1 = @account.spaces.create!(name: "Space One")
    space2 = @account.spaces.create!(name: "Space Two")

    sign_in_as(@user)
    visit spaces_url
    click_on "Switch to Space", match: :first

    # Should redirect to councils for that space
    assert_selector "h1", text: "Councils"
  end

  test "creating council in specific space" do
    space = @account.spaces.create!(name: "Dev Space")

    sign_in_as(@user)
    visit space_councils_path(space)

    click_on "New Council"
    fill_in "Name", with: "Engineering Council"
    click_on "Create Council"

    assert_text "Council created successfully"
    council = Council.last
    assert_equal space.id, council.space_id
  end

  test "space indicator shown in councils list" do
    sign_in_as(@user)
    visit space_councils_path(@space)

    assert_text "in #{@space.name}"
    assert_link "(switch)"
  end

  test "space switcher dropdown in navbar" do
    space2 = @account.spaces.create!(name: "Another Space")

    sign_in_as(@user)
    visit root_path

    # Click space switcher to open dropdown
    find("label", text: @space.name).click

    assert_text "Manage Spaces"
    assert_text "Another Space"
  end
end
