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

  test "dummy google drive import stays on drive.readonly scopes" do
    assert_equal ["https://www.googleapis.com/auth/drive.readonly"], RecordingStudioGoogleDrive.configuration.scopes
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

  test "create returns json unauthorized when the Google Drive gem requires reconnect" do
    follow_connect!
    client = Object.new
    client.define_singleton_method(:fetch_file) do |*_args, **|
      raise RecordingStudioGoogleDrive::ReconnectRequired, "Reconnect Google Drive"
    end

    with_drive_client(client) do
      post google_drive_imports_path, params: { file_ids: ["file-1"] }, as: :json
    end

    assert_response :unauthorized
    payload = JSON.parse(response.body)
    assert_equal "Reconnect Google Drive to continue", payload.fetch("error")
    assert_includes payload.fetch("connect_url"), google_drive_connect_path
    assert_nil session["recording_studio_attachable_google_drive"]
  end

  test "bootstrap returns a connect url when the Google Drive gem requires reconnect" do
    follow_connect!
    original_api_key = RecordingStudioAttachable.configuration.google_drive.api_key
    original_app_id = RecordingStudioAttachable.configuration.google_drive.app_id
    RecordingStudioAttachable.configuration.google_drive.api_key = "test-google-drive-api-key"
    RecordingStudioAttachable.configuration.google_drive.app_id = "test-google-drive-app-id"

    with_stub(
      RecordingStudioAttachable::GoogleDrive::Integration,
      :picker_access,
      ->(*) { raise RecordingStudioGoogleDrive::ReconnectRequired, "Reconnect Google Drive" }
    ) do
      get google_drive_bootstrap_path, as: :json
    end

    assert_response :success
    payload = JSON.parse(response.body)
    assert_includes payload.fetch("connect_url"), google_drive_connect_path
    assert_includes payload.fetch("connect_url"), "popup=1"
    refute payload.key?("auth_url")
    assert_nil payload["access_token"]
    assert_nil session["recording_studio_attachable_google_drive"]
  ensure
    RecordingStudioAttachable.configuration.google_drive.api_key = original_api_key
    RecordingStudioAttachable.configuration.google_drive.app_id = original_app_id
  end

  test "disconnect follows oauth delete, revokes the row, and returns to imports" do
    with_forgery_protection do
      follow_connect!
      connection = live_user_connection

      with_drive_client(listing_client) do
        get google_drive_imports_path
        assert_response :success

        delete google_drive_disconnect_path, params: { authenticity_token: authenticity_token },
                                            headers: { "X-CSRF-Token" => authenticity_token }
        assert_response :temporary_redirect
        assert_includes response.redirect_url, oauth_outbound_connection_path(connection)
        follow_redirect!
        follow_redirect!
      end

      assert_response :success
      assert_equal google_drive_imports_path, URI.parse(request.original_url).path
      assert_equal "revoked", connection.reload.status
      assert_includes flash[:notice].to_s, "Disconnected"
      assert_nil flash[:alert]
    end
  end

  test "a viewer cannot disconnect a root-owned google drive connection" do
    viewer = create_viewer
    grant_workspace_access!(@root, actor: viewer, role: :edit)

    with_forgery_protection do
      follow_connect!(owner: "root", root_recording_id: @root.id)
      connection = RecordingStudioOauth::OutboundConnection.find_by!(root_recording_id: @root.id)
      assert_equal "active", connection.status

      sign_in viewer
      Current.actor = viewer

      with_drive_client(listing_client) do
        get google_drive_imports_path
        assert_response :success

        delete google_drive_disconnect_path, params: { authenticity_token: authenticity_token },
                                            headers: { "X-CSRF-Token" => authenticity_token }
        assert_response :temporary_redirect
        assert_includes response.redirect_url, oauth_outbound_connection_path(connection)
        follow_redirect!
        follow_redirect!
      end

      assert_response :success
      assert_equal google_drive_imports_path, URI.parse(request.original_url).path
      assert_equal "active", connection.reload.status
      assert_equal "You can't change this connection.", flash[:alert]
      assert_nil flash[:notice]
    end
  end

  private

  def follow_connect!(owner: "user", root_recording_id: nil, return_to: google_drive_imports_path)
    get google_drive_imports_path
    assert_response :success
    post oauth_outbound_connect_path, params: {
      authenticity_token: authenticity_token,
      owner: owner,
      root_recording_id: root_recording_id,
      return_to: return_to
    }.compact
    assert_response :redirect
    follow_redirect!
    assert_response :redirect
    follow_redirect!
    assert_response :redirect
    follow_redirect!
  end

  def with_drive_client(client, &block)
    with_stub(RecordingStudioAttachable::GoogleDrive::Integration, :client, ->(**) { client }, &block)
  end

  def listing_client
    drive_file = RecordingStudioGoogleDrive::DriveFile.new(
      id: "file-1",
      name: "Brief.pdf",
      mime_type: "application/pdf",
      size: 12,
      modified_at: nil,
      web_view_link: "https://drive.test/file-1",
      resource_key: nil
    )
    client = Object.new
    client.define_singleton_method(:list) do |**|
      RecordingStudioGoogleDrive::Page.new(entries: [drive_file], next_cursor: nil)
    end
    client
  end

  def with_stub(object, name, callable)
    singleton = object.singleton_class
    original = singleton.instance_method(name) if singleton.method_defined?(name) || singleton.private_method_defined?(name)
    singleton.define_method(name, callable)
    yield
  ensure
    if original
      singleton.define_method(name, original)
    elsif singleton.method_defined?(name) || singleton.private_method_defined?(name)
      singleton.remove_method(name)
    end
  end

  def with_forgery_protection
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    yield
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end

  def authenticity_token
    css_select('input[name="authenticity_token"]').first&.[]("value") ||
      css_select('meta[name="csrf-token"]').first&.[]("content")
  end

  def live_user_connection
    RecordingStudioOauth::OutboundConnection.live.find_by!(
      owner_actor_type: @user.class.name,
      owner_actor_id: @user.id
    )
  end

  def create_viewer
    User.create!(
      email: "viewer-#{SecureRandom.hex(4)}@example.com",
      password: "Password",
      password_confirmation: "Password",
      name: "Viewer"
    )
  end

  def oauth_outbound_connect_path
    RecordingStudioOauth::Engine.routes.url_helpers.outbound_connect_path(provider: "google_drive")
  end

  def oauth_outbound_connection_path(connection)
    RecordingStudioOauth::Engine.routes.url_helpers.outbound_connection_path(connection)
  end

  def google_drive_imports_path
    "/recording_studio_attachable/google_drive/recordings/#{@root.id}/imports"
  end

  def google_drive_disconnect_path
    "/recording_studio_attachable/google_drive/recordings/#{@root.id}/connect"
  end

  def google_drive_connect_path
    "/recording_studio_attachable/google_drive/recordings/#{@root.id}/connect"
  end

  def google_drive_bootstrap_path
    "/recording_studio_attachable/google_drive/recordings/#{@root.id}/bootstrap"
  end

  def grant_workspace_access!(root, actor: @user, role: :admin)
    original = RecordingStudioAccessible.configuration.access_management_authorizer
    RecordingStudioAccessible.configuration.access_management_authorizer = ->(**) { true }
    result = RecordingStudioAccessible.grant_access(
      recording: root,
      actor: actor,
      role: role,
      manager_actor: @user
    )
    raise result.error if result.failure?
  ensure
    RecordingStudioAccessible.configuration.access_management_authorizer = original
  end
end
