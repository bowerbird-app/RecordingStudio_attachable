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
  end

  teardown do
    Current.actor = nil if defined?(Current)
  end

  test "page editor with dropbox enabled renders the gallery modal" do
    page = Page.find_or_create_by!(title: "Home page")
    RecordingStudio::Recording.unscoped.find_or_create_by!(
      root_recording_id: @root.id,
      parent_recording_id: @root.id,
      recordable: page
    )

    with_cloud_adapters_configured do
      get edit_page_path(page)
      assert_response :success
      assert_includes response.body, "recording-studio-attachable--attachment-image-picker"
      assert_includes response.body, "controllers/recording_studio_attachable/dropbox_picker_launcher"
      assert_includes response.body, "attachments/imports"
    end
  end

  test "chat demo with dropbox enabled renders the gallery modal" do
    ChatThread.find_or_create_by!(title: "Workspace conversation")

    with_cloud_adapters_configured do
      get chat_demo_path
      assert_response :success
      assert_includes response.body, "recording-studio-attachable--attachment-image-picker"
      assert_includes response.body, "controllers/recording_studio_attachable/dropbox_picker_launcher"
    end
  end

  test "disconnected dropbox and drive bootstrap leave session state for connect" do
    library = RecordingStudioAttachable.library_for(@root, actor: @user)

    with_cloud_adapters_configured do
      get "/recording_studio_attachable/dropbox/recordings/#{library.id}/bootstrap.json"
      assert_response :success
      dropbox_payload = JSON.parse(response.body)
      assert dropbox_payload["connect_url"].present?
      refute dropbox_payload.key?("auth_url")

      get "/recording_studio_attachable/google_drive/recordings/#{library.id}/bootstrap.json"
      assert_response :success
      drive_payload = JSON.parse(response.body)
      assert drive_payload["connect_url"].present?
      refute drive_payload.key?("auth_url")

      assert_nil session.dig("recording_studio_attachable_dropbox", "oauth_state")
      assert_nil session.dig("recording_studio_attachable_google_drive", "oauth_state")

      get "/recording_studio_attachable/dropbox/recordings/#{library.id}/connect", params: { popup: 1, provider_key: "dropbox" }
      assert_response :redirect
      assert_not_nil session.dig("recording_studio_attachable_dropbox", "oauth_state")
      assert_nil session.dig("recording_studio_attachable_google_drive", "oauth_state")

      get "/recording_studio_attachable/google_drive/recordings/#{library.id}/connect", params: { popup: 1, provider_key: "google_drive" }
      assert_response :redirect
      assert_not_nil session.dig("recording_studio_attachable_dropbox", "oauth_state")
      assert_not_nil session.dig("recording_studio_attachable_google_drive", "oauth_state")
    end
  end

  private

  def with_cloud_adapters_configured
    configuration = RecordingStudioAttachable.configuration
    original_providers = configuration.upload_providers.dup
    original_dropbox = configuration.dropbox.to_h
    original_drive = configuration.google_drive.to_h

    configuration.dropbox.merge!(
      enabled: true,
      client_id: "dropbox-client-id",
      client_secret: "dropbox-client-secret",
      redirect_uri: "http://www.example.com/recording_studio_attachable/dropbox/oauth/callback"
    )
    configuration.google_drive.merge!(
      enabled: true,
      client_id: "google-drive-client-id",
      client_secret: "google-drive-client-secret",
      api_key: "google-drive-api-key",
      app_id: "google-drive-app-id",
      redirect_uri: "http://www.example.com/recording_studio_attachable/google_drive/oauth/callback"
    )

    RecordingStudioAttachable::Dropbox::Engine.send(:register_upload_provider)
    RecordingStudioAttachable::GoogleDrive::Engine.send(:register_upload_provider)

    yield
  ensure
    configuration.dropbox.merge!(original_dropbox)
    configuration.google_drive.merge!(original_drive)
    configuration.instance_variable_set(:@upload_providers, original_providers)
  end

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
