# frozen_string_literal: true

require "test_helper"

class HostCloudPickerModalTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.find_by(email: "admin@admin.com")
    if @user.blank?
      @user = User.new(
        email: "admin@admin.com",
        password: "Password",
        password_confirmation: "Password",
        name: "Avery"
      )
      @user.save!
    end
    sign_in @user

    @workspace = Workspace.first || Workspace.find_or_create_by!(name: "Studio Workspace")
    Current.actor = @user
    @root = RecordingStudio.root_recording_for(@workspace)
    grant_workspace_access!(@root)
    MyCloud.reset!
  end

  teardown do
    Current.actor = nil if defined?(Current)
    MyCloud.reset!
  end

  test "page editor with my_cloud registered renders the gallery modal" do
    page = Page.find_or_create_by!(title: "Home page")
    RecordingStudio::Recording.unscoped.find_or_create_by!(
      root_recording_id: @root.id,
      parent_recording_id: @root.id,
      recordable: page
    )

    get edit_page_path(page)
    assert_response :success
    assert_includes response.body, "recording-studio-attachable--attachment-image-picker"
    assert_includes response.body, "my_cloud/picker_launcher"
    assert_includes response.body, "attachments/imports"
  end

  test "chat demo with my_cloud registered renders the gallery modal" do
    ChatThread.find_or_create_by!(title: "Workspace conversation")

    get chat_demo_path
    assert_response :success
    assert_includes response.body, "recording-studio-attachable--attachment-image-picker"
    assert_includes response.body, "my_cloud/picker_launcher"
  end

  test "client picker selection imports through the host attachments endpoint" do
    MyCloud.connect!(@user)

    post recording_studio_attachable.recording_attachment_imports_path(@root),
         params: {
           attachment_import: {
             provider_key: "my_cloud",
             attachments: [
               {
                 name: "kiln.jpg",
                 description: "",
                 provider_key: "my_cloud",
                 provider_payload: { id: "file-1" },
                 content_type: ""
               }
             ]
           }
         },
         as: :json

    assert_response :created
  end

  test "disconnected bootstrap returns a generic connect payload" do
    get "/recording_studio_attachable/my_cloud/recordings/#{@root.id}/bootstrap.json"
    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal "my_cloud", payload.fetch("provider_key")
    assert payload.fetch("needs_auth")
    assert payload.dig("connect", "url").present?
    refute payload.key?("auth_url")
    refute payload.key?("connect_url")

    get "/recording_studio_attachable/my_cloud/recordings/#{@root.id}/connect",
        params: { popup: 1, provider_key: "my_cloud" }
    assert_response :success
    assert_includes response.body, "Connect My Cloud"
  end

  private

  def grant_workspace_access!(root)
    original = RecordingStudioAccessible.configuration.access_management_authorizer
    RecordingStudioAccessible.configuration.access_management_authorizer = ->(**) { true }
    result = RecordingStudioAccessible.grant_access(
      recording: root,
      actor: @user,
      role: :admin,
      manager_actor: @user
    )
    raise result.error if result.failure?
  ensure
    RecordingStudioAccessible.configuration.access_management_authorizer = original
  end
end
