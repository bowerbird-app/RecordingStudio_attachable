# frozen_string_literal: true

require "test_helper"
require "base64"
require "digest"

class AttachmentMcpTest < ActionDispatch::IntegrationTest
  setup do
    @previous_actor = Current.actor
    @owner = user("mcp-owner")
    @editor = user("mcp-editor")
    @viewer = user("mcp-viewer")
    Current.actor = @owner
    @workspace = Workspace.create!(name: "MCP #{SecureRandom.hex(4)}")
    @root = RecordingStudio.create_root_recording!(@workspace, actor: @owner)
    @owner_access = bootstrap!(@root, @owner)
    @editor_access = grant!(@editor, :edit)
    @viewer_access = grant!(@viewer, :view)
    @editor_token = token_for(@editor_access)
    @viewer_token = token_for(@viewer_access)
  end

  teardown do
    Current.actor = @previous_actor
  end

  test "named tools are listed with id type and action inputs" do
    listed = rpc(@editor_token, "tools/list")
    tools = listed.dig("result", "tools")
    flunk listed.to_json if tools.nil?
    by_name = tools.to_h { |tool| [tool.fetch("name"), tool] }

    RecordingStudioAttachable::McpCopy.tool_names.each do |name|
      assert by_name.key?(name), "missing #{name} in #{by_name.keys.sort}"
    end
    refute by_name.key?("capability_action")
    refute by_name.key?("attachments-storage_used")

    upload = by_name.fetch("create_upload")
    attach = by_name.fetch("attach")
    import = by_name.fetch("import_attachment")
    upload_props = properties(upload)
    attach_props = properties(attach)
    import_props = properties(import)

    %w[id type filename byte_size checksum content_type].each { |key| assert upload_props.key?(key), key }
    %w[id type signed_blob_id attachments name description caption credit alt_text].each do |key|
      assert attach_props.key?(key), key
    end
    %w[id type url name description].each { |key| assert import_props.key?(key), key }
    assert_includes upload.fetch("description"), "create_upload"
    assert_includes attach.fetch("description"), "create_upload"
    refute_match(/\bAccess\b/, upload.fetch("description"))
  end

  test "create_upload through the named tool hits the action and Accessible role" do
    bytes = png_bytes
    created = rpc(
      @editor_token,
      "tools/call",
      name: "create_upload",
      arguments: upload_arguments(bytes)
    )
    refute created.dig("result", "isError"), created.to_json
    ticket = payload(created)
    assert ticket.fetch("signed_blob_id").present?
    assert ticket.dig("upload", "url").present?

    denied = rpc(
      @viewer_token,
      "tools/call",
      name: "create_upload",
      arguments: upload_arguments(bytes)
    )
    assert denied.dig("result", "isError"), denied.to_json
  end

  private

  def properties(tool)
    tool.fetch("inputSchema").fetch("properties").transform_keys(&:to_s)
  end

  def upload_arguments(bytes)
    {
      type: "Workspace",
      id: @root.id.to_s,
      filename: "photo.png",
      byte_size: bytes.bytesize,
      checksum: Base64.strict_encode64(Digest::MD5.digest(bytes)),
      content_type: "image/png"
    }
  end

  def png_bytes
    Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")
  end

  def user(name)
    User.create!(
      email: "#{name}-#{SecureRandom.hex(4)}@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      name: name
    )
  end

  def bootstrap!(recording, actor)
    result = RecordingStudioAccessible.bootstrap_owner_access!(recording: recording, actor: actor)
    raise result.error if result.failure?

    result.value
  end

  def grant!(actor, role)
    result = RecordingStudioAccessible.grant_access(
      recording: @root,
      actor: actor,
      role: role,
      manager_actor: @owner
    )
    raise result.error if result.failure?

    result.value
  end

  def token_for(access_recording)
    provision = RecordingStudioApi::Services::ProvisionApiClient.call(
      access_point_recording: access_recording.parent_recording || access_recording.root_recording,
      manager_actor: @owner,
      role: access_recording.recordable.role,
      name: "MCP #{SecureRandom.hex(3)}"
    )
    raise provision.error unless provision.success?

    issued = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "client_credentials",
      client_id: provision.value.fetch(:credential).oauth_client_id,
      client_secret: provision.value.fetch(:token)
    )
    raise issued.error unless issued.success?

    issued.value.fetch(:access_token)
  end

  def rpc(token, method, **params)
    post "/recording_studio_mcp",
         params: { jsonrpc: "2.0", id: SecureRandom.random_number(1_000), method: method, params: params }.to_json,
         headers: {
           "Content-Type" => "application/json",
           "Accept" => "application/json",
           "Authorization" => "Bearer #{token}"
         }
    assert_response :success, response.body
    JSON.parse(response.body)
  end

  def payload(body)
    structured = body.dig("result", "structuredContent")
    return structured if structured.is_a?(Hash) && structured["signed_blob_id"]

    JSON.parse(body.dig("result", "content", 0, "text").to_s)
  end
end
