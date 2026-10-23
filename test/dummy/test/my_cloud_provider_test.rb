# frozen_string_literal: true

require "test_helper"

class MyCloudProviderTest < ActionDispatch::IntegrationTest
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

  test "my_cloud is registered and mounts under the attachable engine" do
    provider = RecordingStudioAttachable.configuration.upload_provider(:my_cloud)
    assert_equal "My Cloud", provider.label
    assert_equal :client_picker, provider.strategy
    assert Rails.application.routes.recognize_path(
      "/recording_studio_attachable/my_cloud/recordings/#{@root.id}/bootstrap",
      method: :get
    )
  end

  test "browse page uses the generic remote file browser" do
    MyCloud.connect!(@user)
    get "/recording_studio_attachable/my_cloud/recordings/#{@root.id}/imports"
    assert_response :success
    assert_includes response.body, "Cloud brief.png"
    assert_includes response.body, "Import selected"
  end

  test "connect then import copies a remote file" do
    post "/recording_studio_attachable/my_cloud/recordings/#{@root.id}/connect"
    assert_response :redirect

    post "/recording_studio_attachable/my_cloud/recordings/#{@root.id}/imports",
         params: { file_ids: ["file-1"] }
    assert_response :redirect
    follow_redirect!
    assert_response :success
  end

  test "remote import reconnect maps through the shared imports endpoint" do
    MyCloud.connect!(@user)
    MyCloud.force_reconnect!

    post recording_studio_attachable.recording_attachment_imports_path(@root),
         params: {
           attachment_import: {
             provider_key: "my_cloud",
             attachments: [{ provider_payload: { id: "file-1" } }]
           }
         },
         as: :json

    assert_response :unprocessable_entity
    payload = JSON.parse(response.body)
    assert_includes payload.fetch("error"), "Reconnect"
    assert payload.dig("errors", "url").present?
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
