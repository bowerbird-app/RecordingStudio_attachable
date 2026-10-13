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

  test "dropbox chooser selection imports through the host attachments endpoint" do
    captured = nil
    imported = RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: [])

    importer = RecordingStudioAttachable::Dropbox::Services::ImportSelectedFiles
    original_importer_call = importer.method(:call)
    original_token_fetch = RecordingStudioAttachable::Dropbox::SessionAccessToken.method(:fetch)

    RecordingStudioAttachable::Dropbox::SessionAccessToken.define_singleton_method(:fetch) { |**_| "dropbox-token" }
    importer.define_singleton_method(:call) do |**kwargs|
      captured = kwargs
      imported
    end

    with_cloud_adapters_configured do
      post recording_studio_attachable.recording_attachment_imports_path(@root),
           params: {
             attachment_import: {
               provider_key: "dropbox",
               attachments: [
                 {
                   name: "kiln.jpg",
                   description: "",
                   provider_key: "dropbox",
                   provider_payload: { id: "id:fia-lKYKs5AAAAAAAAAACw" },
                   content_type: ""
                 }
               ]
             }
           },
           as: :json
    end
  ensure
    RecordingStudioAttachable::Dropbox::SessionAccessToken.define_singleton_method(:fetch, original_token_fetch)
    importer.define_singleton_method(:call, original_importer_call)

    assert_response :created
    selection = captured.fetch(:file_ids).first
    assert_equal "id:fia-lKYKs5AAAAAAAAAACw", selection.fetch("id")
    assert_equal "kiln.jpg", selection.fetch("name")
    assert_equal "dropbox-token", captured.fetch(:access_token)
  end

  test "disconnected dropbox and drive bootstrap leave session state for connect" do
    with_cloud_adapters_configured do
      get "/recording_studio_attachable/dropbox/recordings/#{@root.id}/bootstrap.json"
      assert_response :success
      dropbox_payload = JSON.parse(response.body)
      assert dropbox_payload["connect_url"].present?
      refute dropbox_payload.key?("auth_url")

      get "/recording_studio_attachable/google_drive/recordings/#{@root.id}/bootstrap.json"
      assert_response :success
      drive_payload = JSON.parse(response.body)
      assert drive_payload["connect_url"].present?
      refute drive_payload.key?("auth_url")

      assert_nil session.dig("recording_studio_attachable_dropbox", "oauth_state")
      assert_nil session.dig("recording_studio_attachable_google_drive", "oauth_state")

      get "/recording_studio_attachable/dropbox/recordings/#{@root.id}/connect", params: { popup: 1, provider_key: "dropbox" }
      assert_response :redirect
      assert_not_nil session.dig("recording_studio_attachable_dropbox", "oauth_state")
      assert_nil session.dig("recording_studio_attachable_google_drive", "oauth_state")

      get "/recording_studio_attachable/google_drive/recordings/#{@root.id}/connect", params: { popup: 1, provider_key: "google_drive" }
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
