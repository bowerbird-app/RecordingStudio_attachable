# frozen_string_literal: true

require "test_helper"

class GoogleDriveImportTest < ActionDispatch::IntegrationTest
  setup do
    FakeOauth.reset!
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
    FakeOauth.reset!
  end

  test "imports index shows connect when there is no Google Drive connection" do
    get google_drive_imports_path

    assert_response :success
    assert_includes response.body, "Connect Google Drive"
    assert_includes response.body, oauth_outbound_connect_path
    refute_includes response.body, "fake-access-"
    assert_nil session["recording_studio_attachable_google_drive"]
    assert_nil session["access_token"]
  end

  test "connected import lists files and copies a selected file into storage" do
    follow_connect!

    drive_file = RecordingStudioGoogleDrive::DriveFile.new(
      id: "file-1",
      name: "Brief.pdf",
      mime_type: "application/pdf",
      size: 12,
      modified_at: nil,
      web_view_link: "https://drive.test/file-1",
      resource_key: nil
    )
    downloaded = RecordingStudioGoogleDrive::DownloadedFile.new(
      body: "%PDF-1.4\nbrief",
      filename: "Brief.pdf",
      content_type: "application/pdf"
    )
    client = Object.new
    client.define_singleton_method(:list) do |**|
      RecordingStudioGoogleDrive::Page.new(entries: [drive_file], next_cursor: nil)
    end
    client.define_singleton_method(:fetch_file) { |_id, resource_key: nil| drive_file }
    client.define_singleton_method(:download) { |_id, resource_key: nil| downloaded }

    with_drive_client(client) do
      get google_drive_imports_path
      assert_response :success
      assert_includes response.body, "Brief.pdf"
      refute_includes response.body, "Connect Google Drive"

      post google_drive_imports_path, params: { file_ids: ["file-1"] }
    end

    assert_response :redirect
    imported = RecordingStudio::Recording.unscoped.where(
      parent_recording_id: @root.id,
      recordable_type: "RecordingStudioAttachable::Attachment"
    )
    assert imported.any? { |recording| recording.recordable.original_filename == "Brief.pdf" }
    assert_nil session["recording_studio_attachable_google_drive"]
    refute_includes response.body, "fake-access-"
  end

  test "imports index shows reconnect when the Google Drive gem requires it" do
    follow_connect!
    client = Object.new
    client.define_singleton_method(:list) do |**|
      raise RecordingStudioGoogleDrive::ReconnectRequired, "Reconnect Google Drive"
    end

    with_drive_client(client) do
      get google_drive_imports_path
    end

    assert_response :success
    assert_includes response.body, "Reconnect Google Drive"
    assert_includes response.body, oauth_outbound_connect_path
    assert_nil session["recording_studio_attachable_google_drive"]
  end

  private

  def follow_connect!
    post oauth_outbound_connect_path, params: {
      owner: "user",
      return_to: google_drive_imports_path
    }
    assert_response :redirect
    follow_redirect!
    assert_response :redirect
    follow_redirect!
    assert_response :redirect
    follow_redirect!
  end

  def with_drive_client(client)
    original = RecordingStudioGoogleDrive::Client.method(:for)
    RecordingStudioGoogleDrive::Client.define_singleton_method(:for) { |**| client }
    yield
  ensure
    RecordingStudioGoogleDrive::Client.define_singleton_method(:for, original)
  end

  def oauth_outbound_connect_path
    RecordingStudioOauth::Engine.routes.url_helpers.outbound_connect_path(provider: "google_drive")
  end

  def google_drive_imports_path
    "/recording_studio_attachable/google_drive/recordings/#{@root.id}/imports"
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
