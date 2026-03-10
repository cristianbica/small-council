require "test_helper"

class FormFillersControllerTest < ActionDispatch::IntegrationTest
  VALID_PROFILE = "advisor_profile".freeze
  COUNCIL_PROFILE = "council_profile".freeze

  setup do
    @account = accounts(:one)
    @user = users(:one)

    sign_in_as(@user)
    set_tenant(@account)
  end

  test "new renders advisor profile modal content without layout and with filler id" do
    get new_form_filler_url, params: { profile: VALID_PROFILE }

    assert_response :success
    assert_includes response.body, "Generate Advisor Profile"
    assert_includes response.body, 'turbo-frame id="form-filler-advisor_profile"'
    assert_includes response.body, 'name="filler_id"'
    assert_match(/value="[0-9a-f\-]{36}" type="hidden" name="filler_id"/, response.body)
    refute_includes response.body, "<html"
  end

  test "new renders council profile modal content without layout and with filler id" do
    get new_form_filler_url, params: { profile: COUNCIL_PROFILE }

    assert_response :success
    assert_includes response.body, "Generate Council"
    assert_includes response.body, 'turbo-frame id="form-filler-council_profile"'
    assert_includes response.body, 'name="filler_id"'
    assert_match(/value="[0-9a-f\-]{36}" type="hidden" name="filler_id"/, response.body)
    refute_includes response.body, "<html"
  end

  test "new rejects unsupported profile" do
    get new_form_filler_url, params: { profile: "unknown" }

    assert_response :unprocessable_entity
    assert_empty response.body
  end

  test "create rejects unsupported profile" do
    post form_filler_url,
      params: { profile: "unknown", filler_id: SecureRandom.uuid, description: "draft this advisor" }

    assert_response :unprocessable_entity
    assert_empty response.body
  end

  test "create rejects missing filler id" do
    post form_filler_url,
      params: { profile: VALID_PROFILE, description: "draft this advisor" }

    assert_response :unprocessable_entity
    assert_empty response.body
  end

  test "create renders panel error for blank description" do
    filler_id = SecureRandom.uuid

    post form_filler_url,
      params: { profile: VALID_PROFILE, filler_id: filler_id, description: "   " }

    assert_response :unprocessable_entity
    assert_includes response.body, "Description can&#39;t be blank"
    assert_includes response.body, "form_filler_panel_#{filler_id}"
  end

  test "create renders pending panel and starts async generation" do
    filler_id = SecureRandom.uuid

    AI.expects(:generate_text).with do |args|
      assert_equal "tasks/advisor_profile", args[:prompt]
      assert_equal :advisor_profile, args[:schema]
      assert_equal "draft this advisor", args[:description]
      assert_equal Current.space, args[:space]
      assert_equal true, args[:async]
      assert_equal({ type: :turbo_form_filler, filler_id: filler_id }, args[:handler])
      true
    end

    post form_filler_url,
      params: { profile: VALID_PROFILE, filler_id: filler_id, description: "  draft this advisor  " }

    assert_response :success
    assert_includes response.body, "Generating Advisor Profile"
    assert_includes response.body, "form_filler_result_#{filler_id}"
  end

  test "create renders pending panel and starts async generation for council profile" do
    filler_id = SecureRandom.uuid

    AI.expects(:generate_text).with do |args|
      assert_equal "tasks/council_profile", args[:prompt]
      assert_equal :council_profile, args[:schema]
      assert_equal "draft this council", args[:description]
      assert_equal Current.space, args[:space]
      assert_equal true, args[:async]
      assert_equal({ type: :turbo_form_filler, filler_id: filler_id }, args[:handler])
      true
    end

    post form_filler_url,
      params: { profile: COUNCIL_PROFILE, filler_id: filler_id, description: "  draft this council  " }

    assert_response :success
    assert_includes response.body, "Generating Council"
    assert_includes response.body, "form_filler_result_#{filler_id}"
  end

  test "create renders error partial for resolution error" do
    filler_id = SecureRandom.uuid
    AI.expects(:generate_text).raises(AI::ResolutionError, "Unknown prompt")

    post form_filler_url,
      params: { profile: VALID_PROFILE, filler_id: filler_id, description: "draft this advisor" }

    assert_response :unprocessable_entity
    assert_includes response.body, "Unknown prompt"
    assert_includes response.body, "form_filler_panel_#{filler_id}"
  end

  test "create renders error partial for client error" do
    filler_id = SecureRandom.uuid
    AI.expects(:generate_text).raises(AI::Client::Error, "AI service error")

    post form_filler_url,
      params: { profile: VALID_PROFILE, filler_id: filler_id, description: "draft this advisor" }

    assert_response :unprocessable_entity
    assert_includes response.body, "AI service error"
    assert_includes response.body, "form_filler_panel_#{filler_id}"
  end
end
