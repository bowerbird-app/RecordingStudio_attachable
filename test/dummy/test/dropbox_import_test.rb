# frozen_string_literal: true

require "test_helper"

class DropboxImportTest < ActionDispatch::IntegrationTest
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

  test "dummy dropbox oauth uses the fake provider when credentials are absent" do
    provider = dropbox_oauth_provider

    assert_equal "/fake_oauth/authorize", provider.authorize_url
    assert_equal "/fake_oauth/token", provider.token_url
    assert_equal FakeOauth::CLIENT_ID, provider.client_id
    assert_equal FakeOauth, provider.http
    assert_equal "offline", provider.extra_authorize_params.fetch("token_access_type")
  end

  test "imports index shows connect when there is no Dropbox connection" do
    get dropbox_imports_path

    assert_response :success
    assert_includes response.body, "Connect Dropbox"
    assert_includes response.body, oauth_outbound_connect_path
    refute_includes response.body, "fake-access-"
    assert_nil session["recording_studio_attachable_dropbox"]
    assert_nil session["access_token"]
  end

  test "connected import lists files and copies a selected file into storage" do
    follow_connect!

    dropbox_file = RecordingStudioDropbox::Entry.new(
      id: "id:file-1",
      name: "Brief.pdf",
      path: "/Brief.pdf",
      tag: "file",
      size: 12
    )
    downloaded = RecordingStudioDropbox::DownloadedFile.new(
      body: "%PDF-1.4\nbrief",
      filename: "Brief.pdf",
      content_type: nil
    )
    client = Object.new
    client.define_singleton_method(:list) do |**|
      RecordingStudioDropbox::Page.new(entries: [dropbox_file], next_cursor: nil)
    end
    client.define_singleton_method(:fetch_file) { |path:| dropbox_file }
    client.define_singleton_method(:download) { |path:| downloaded }

    with_dropbox_client(client) do
      get dropbox_imports_path
      assert_response :success
      assert_includes response.body, "Brief.pdf"
      refute_includes response.body, "Connect Dropbox"

      post dropbox_imports_path, params: { file_ids: ["id:file-1"] }
    end

    assert_response :redirect
    imported = RecordingStudio::Recording.unscoped.where(
      parent_recording_id: @root.id,
      recordable_type: "RecordingStudioAttachable::Attachment"
    )
    assert imported.any? { |recording| recording.recordable.original_filename == "Brief.pdf" }
    assert_nil session["recording_studio_attachable_dropbox"]
    refute_includes response.body, "fake-access-"
  end

  test "imports index shows reconnect when the Dropbox gem requires it" do
    follow_connect!
    client = Object.new
    client.define_singleton_method(:list) do |**|
      raise RecordingStudioDropbox::ReconnectRequired, "Reconnect Dropbox"
    end

    with_dropbox_client(client) do
      get dropbox_imports_path
    end

    assert_response :success
    assert_includes response.body, "Reconnect Dropbox"
    assert_includes response.body, oauth_outbound_connect_path
    assert_nil session["recording_studio_attachable_dropbox"]
  end

  test "create returns json unauthorized when the Dropbox gem requires reconnect" do
    follow_connect!
    client = Object.new
    client.define_singleton_method(:fetch_file) do |*_args, **|
      raise RecordingStudioDropbox::ReconnectRequired, "Reconnect Dropbox"
    end

    with_dropbox_client(client) do
      post dropbox_imports_path, params: { file_ids: ["file-1"] }, as: :json
    end

    assert_response :unauthorized
    payload = JSON.parse(response.body)
    assert_equal "Reconnect Dropbox to continue", payload.fetch("error")
    assert_includes payload.fetch("connect_url"), dropbox_connect_path
    assert_direct_oauth_connect_payload(payload)
    assert_nil session["recording_studio_attachable_dropbox"]
  end

  test "bootstrap returns a connect url when the Dropbox gem requires reconnect" do
    follow_connect!
    original_client_id = RecordingStudioAttachable.configuration.dropbox.client_id
    RecordingStudioAttachable.configuration.dropbox.client_id = "test-dropbox-client-id"

    with_stub(
      RecordingStudioAttachable::Dropbox::Integration,
      :chooser_access,
      ->(*) { raise RecordingStudioDropbox::ReconnectRequired, "Reconnect Dropbox" }
    ) do
      get dropbox_bootstrap_path, as: :json
    end

    assert_response :success
    payload = JSON.parse(response.body)
    assert_includes payload.fetch("connect_url"), dropbox_connect_path
    assert_includes payload.fetch("connect_url"), "popup=1"
    assert_direct_oauth_connect_payload(payload)
    refute payload.key?("auth_url")
    assert_nil payload["access_token"]
    assert_nil session["recording_studio_attachable_dropbox"]
  ensure
    RecordingStudioAttachable.configuration.dropbox.client_id = original_client_id
  end

  test "disconnect follows oauth delete, revokes the row, and returns to imports" do
    with_forgery_protection do
      follow_connect!
      connection = live_user_connection

      with_dropbox_client(listing_client) do
        get dropbox_imports_path
        assert_response :success
        disconnect_through_oauth!(connection)
      end

      assert_response :success
      assert_equal dropbox_imports_path, URI.parse(request.original_url).path
      assert_equal "revoked", connection.reload.status
      assert_equal "Connection removed.", flash[:notice]
      assert_nil flash[:alert]
    end
  end

  test "a viewer cannot disconnect a root-owned dropbox connection" do
    viewer = create_viewer
    grant_workspace_access!(@root, actor: viewer, role: :edit)

    with_forgery_protection do
      follow_connect!(owner: "root", root_recording_id: @root.id)
      connection = RecordingStudioOauth::OutboundConnection.find_by!(
        provider_key: "dropbox",
        root_recording_id: @root.id
      )
      assert_equal "active", connection.status

      sign_in viewer
      Current.actor = viewer

      with_dropbox_client(listing_client) do
        get dropbox_imports_path
        assert_response :success
        disconnect_through_oauth!(connection)
      end

      assert_response :success
      assert_equal dropbox_imports_path, URI.parse(request.original_url).path
      assert_equal "active", connection.reload.status
      assert_equal "You can't change this connection.", flash[:alert]
      assert_nil flash[:notice]
    end
  end

  private

  def disconnect_through_oauth!(connection)
    token = authenticity_token
    delete dropbox_disconnect_path, params: { authenticity_token: token },
                                    headers: { "X-CSRF-Token" => token }
    assert_response :temporary_redirect
    assert_includes response.redirect_url, oauth_outbound_connection_path(connection)
    follow_redirect!(
      headers: { "X-CSRF-Token" => token },
      params: { authenticity_token: token }
    )
    follow_redirect!
  end

  def follow_connect!(owner: "user", root_recording_id: nil, return_to: dropbox_imports_path)
    get dropbox_imports_path
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

  def with_dropbox_client(client, &block)
    with_stub(RecordingStudioAttachable::Dropbox::Integration, :client, ->(**) { client }, &block)
  end

  def listing_client
    dropbox_file = RecordingStudioDropbox::Entry.new(
      id: "id:file-1",
      name: "Brief.pdf",
      path: "/Brief.pdf",
      tag: "file",
      size: 12
    )
    client = Object.new
    client.define_singleton_method(:list) do |**|
      RecordingStudioDropbox::Page.new(entries: [dropbox_file], next_cursor: nil)
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
      provider_key: "dropbox",
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

  def dropbox_oauth_provider
    RecordingStudioOauth::Outbound.provider(:dropbox)
  end

  def oauth_outbound_connect_path
    RecordingStudioOauth::Engine.routes.url_helpers.outbound_connect_path(provider: "dropbox")
  end

  def oauth_outbound_connection_path(connection)
    RecordingStudioOauth::Engine.routes.url_helpers.outbound_connection_path(connection)
  end

  def dropbox_imports_path
    "/recording_studio_attachable/dropbox/recordings/#{@root.id}/imports"
  end

  def dropbox_disconnect_path
    "/recording_studio_attachable/dropbox/recordings/#{@root.id}/connect"
  end

  def assert_direct_oauth_connect_payload(payload)
    assert_equal oauth_outbound_connect_path, payload.fetch("oauth_connect_url")
    assert_includes payload.fetch("return_to"), dropbox_connected_path
    assert_includes payload.fetch("return_to"), "popup=1"
    assert payload.fetch("authenticity_token").present?
  end

  def dropbox_connected_path
    "/recording_studio_attachable/dropbox/recordings/#{@root.id}/connected"
  end

  def dropbox_connect_path
    "/recording_studio_attachable/dropbox/recordings/#{@root.id}/connect"
  end

  def dropbox_bootstrap_path
    "/recording_studio_attachable/dropbox/recordings/#{@root.id}/bootstrap"
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
