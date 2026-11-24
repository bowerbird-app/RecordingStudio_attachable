# frozen_string_literal: true

require "test_helper"
require "base64"
require "digest"
require "net/http"

class AttachmentMcpTest < ActionDispatch::IntegrationTest
  setup do
    @previous_actor = Current.actor
    @owner = user("mcp-owner")
    @editor = user("mcp-editor")
    @viewer = user("mcp-viewer")
    Current.actor = @owner
    @workspace = Workspace.create!(name: "MCP #{SecureRandom.hex(4)}")
    @root = RecordingStudio.create_root_recording!(@workspace, actor: @owner)
    @page = @root.record(Page, actor: @owner) { |page| page.title = "Notes" }
    @owner_access = bootstrap!(@root, @owner)
    @editor_access = grant!(@editor, :edit)
    @viewer_access = grant!(@viewer, :view)
    @editor_token = token_for(@editor_access)
    @viewer_token = token_for(@viewer_access)
    @hosts = RecordingStudioAttachable.configuration.import_allowed_hosts.dup
    RecordingStudioAttachable.configuration.import_allowed_hosts = ["files.example.test"]
  end

  teardown do
    Current.actor = @previous_actor
    RecordingStudioAttachable.configuration.import_allowed_hosts = @hosts
  end

  test "a type with attach disabled does not register attach and shows a host hint" do
    configuration = RecordingStudio.configuration
    original = configuration.instance_variable_get(:@capabilities).transform_values(&:dup)
    type = "HintSection"
    configuration.enable_capability(:attachable, on: type)
    RecordingStudioApi.register_recordable_type_api(
      type,
      capability_actions: %i[create_upload],
      api: :public
    )
    RecordingStudioAttachable.configuration.mcp_next_step(type, "then call image_section_add")
    RecordingStudioAttachable::McpCopy.register!

    attach_name = RecordingStudioAttachable::McpCopy.tool_name(type, :attach)
    upload = RecordingStudioMcp.configuration.tool(RecordingStudioAttachable::McpCopy.tool_name(type, :create_upload))
    refute RecordingStudioMcp.configuration.tool(attach_name)
    assert upload
    assert_includes upload.description, "then call image_section_add"
    refute_includes upload.description, attach_name
    refute_includes RecordingStudioAttachable::McpCopy.tool_names(api: :public), attach_name
  ensure
    configuration.instance_variable_set(:@capabilities, original) if original
    RecordingStudioAttachable.configuration.mcp_next_steps.delete("HintSection")
  end

  test "tool names registers a type that became attachable after register!" do
    configuration = RecordingStudio.configuration
    original = configuration.instance_variable_get(:@capabilities).transform_values(&:dup)
    type = "LateFileSection"
    configuration.enable_capability(:attachable, on: type)
    RecordingStudioApi.register_recordable_type_api(
      type,
      capability_actions: RecordingStudioAttachable::McpCopy::ACTIONS,
      api: :public
    )

    names = RecordingStudioAttachable::McpCopy.tool_names(api: :public)
    RecordingStudioAttachable::McpCopy::ACTIONS.each do |action|
      name = RecordingStudioAttachable::McpCopy.tool_name(type, action)
      assert_includes names, name
      assert RecordingStudioMcp.configuration.tool(name), "MCP server public includes unknown tool #{name}"
    end
    assert_includes RecordingStudioAttachable::McpCopy.tool_names, "late_file_section_create_upload"
  ensure
    configuration.instance_variable_set(:@capabilities, original) if original
  end

  test "tool names for an api follow that api's registrations" do
    public_names = RecordingStudioAttachable::McpCopy.tool_names(api: :public)
    every_name = RecordingStudioAttachable::McpCopy.tool_names

    RecordingStudioAttachable::McpCopy::ACTIONS.each do |action|
      on_api = RecordingStudioAttachable::McpCopy.tool_name("Workspace", action)
      unsupported = RecordingStudioAttachable::McpCopy.tool_name("Page", action)
      missing = RecordingStudioAttachable::McpCopy.tool_name("RecordingStudioSiteSettings::SiteSetting", action)

      assert_includes public_names, on_api
      refute_includes public_names, unsupported
      refute_includes public_names, missing
      refute_includes every_name, unsupported
      refute_includes every_name, missing
    end
  end

  test "tools list has one upload set per attachable type and no typeless tools" do
    listed = rpc(@editor_token, "tools/list")
    tools = listed.dig("result", "tools")
    flunk listed.to_json if tools.nil?
    by_name = tools.to_h { |tool| [tool.fetch("name"), tool] }

    RecordingStudioAttachable::McpCopy::ACTIONS.each do |action|
      name = RecordingStudioAttachable::McpCopy.tool_name("Workspace", action)
      assert by_name.key?(name), "missing #{name} in #{by_name.keys.sort}"
    end
    RecordingStudioAttachable::McpCopy::ACTIONS.each do |action|
      name = RecordingStudioAttachable::McpCopy.tool_name("Page", action)
      refute_includes RecordingStudioAttachable::McpCopy.tool_names, name
      refute by_name.key?(name), "#{name} is listed though Page does not enable that action"
    end
    site = "RecordingStudioSiteSettings::SiteSetting"
    RecordingStudioAttachable::McpCopy::ACTIONS.each do |action|
      name = RecordingStudioAttachable::McpCopy.tool_name(site, action)
      refute_includes RecordingStudioAttachable::McpCopy.tool_names, name
      refute by_name.key?(name), "#{name} is on the public server, whose API does not register SiteSetting"
    end
    %w[create_upload attach import_attachment].each do |name|
      refute by_name.key?(name), "typeless #{name} is still listed"
    end
    %w[chat_thread_create_upload chat_thread_attach chat_thread_import_attachment].each do |name|
      refute by_name.key?(name), "#{name} is listed for a type without Attachable"
    end
    refute by_name.key?("capability_action")
    refute by_name.key?("attachments-storage_used")

    upload = by_name.fetch("workspace_create_upload")
    attach = by_name.fetch("workspace_attach")
    import = by_name.fetch("workspace_import_attachment")
    upload_props = properties(upload)
    attach_props = properties(attach)
    import_props = properties(import)

    [upload, attach, import].each do |tool|
      schema = tool.fetch("inputSchema")
      refute_empty schema.fetch("properties")
      refute schema.fetch("properties").key?("type"), tool.fetch("name")
      assert schema.fetch("properties").key?("id"), tool.fetch("name")
    end
    %w[id filename byte_size checksum content_type].each { |key| assert upload_props.key?(key), key }
    %w[id signed_blob_id attachments name description caption credit alt_text].each do |key|
      assert attach_props.key?(key), key
    end
    %w[id url name description].each { |key| assert import_props.key?(key), key }
    assert_includes upload.fetch("description"), "workspace_create_upload"
    assert_includes attach.fetch("description"), "workspace_create_upload"
    refute_match(/\bAccess\b/, upload.fetch("description"))
    [upload, attach, import].each do |tool|
      refute_match(/\bconfig\./, tool.fetch("description"))
    end
    assert_includes import.fetch("description"), "host app"

    described = rpc(@editor_token, "tools/call", name: "describe", arguments: { type: "Workspace" })
    refute described.dig("result", "isError"), described.to_json
    body = described.to_json
    %w[workspace_create_upload workspace_attach workspace_import_attachment].each do |name|
      assert_includes body, name
    end
    refute_includes body, "chat_thread_create_upload"
  end

  test "workspace_create_upload hits the action and refuses a viewer or another type" do
    bytes = png_bytes
    created = rpc(@editor_token, "tools/call", name: "workspace_create_upload", arguments: upload_arguments(bytes))
    refute created.dig("result", "isError"), created.to_json
    ticket = payload(created)
    assert ticket.fetch("signed_blob_id").present?
    assert ticket.dig("upload", "url").present?

    denied = rpc(@viewer_token, "tools/call", name: "workspace_create_upload", arguments: upload_arguments(bytes))
    assert denied.dig("result", "isError"), denied.to_json

    other = rpc(
      @editor_token,
      "tools/call",
      name: "workspace_create_upload",
      arguments: upload_arguments(bytes, id: @page.id)
    )
    assert other.dig("result", "isError"), other.to_json
    assert_includes other.to_json, "does not match"
  end

  test "workspace_attach records a child and refuses a viewer or another type" do
    bytes = png_bytes
    created = rpc(@editor_token, "tools/call", name: "workspace_create_upload", arguments: upload_arguments(bytes))
    refute created.dig("result", "isError"), created.to_json
    ticket = payload(created)
    put_upload(ticket, bytes)

    denied = rpc(
      @viewer_token,
      "tools/call",
      name: "workspace_attach",
      arguments: {
        id: @root.id.to_s,
        signed_blob_id: ticket.fetch("signed_blob_id"),
        name: "Nope"
      }
    )
    assert denied.dig("result", "isError"), denied.to_json

    attached = rpc(
      @editor_token,
      "tools/call",
      name: "workspace_attach",
      arguments: {
        id: @root.id.to_s,
        signed_blob_id: ticket.fetch("signed_blob_id"),
        name: "Door"
      }
    )
    refute attached.dig("result", "isError"), attached.to_json
    row = payload(attached)
    assert_equal "Door", row.fetch("name")
    assert_equal "image", row.fetch("kind")
    assert row.dig("urls", "file").present?

    other = rpc(
      @editor_token,
      "tools/call",
      name: "workspace_attach",
      arguments: {
        id: @page.id.to_s,
        signed_blob_id: ticket.fetch("signed_blob_id"),
        name: "Wrong"
      }
    )
    assert other.dig("result", "isError"), other.to_json
    assert_includes other.to_json, "does not match"
  end

  test "workspace_import_attachment fetches a url and refuses a viewer or another type" do
    with_fetch(png_bytes, content_type: "image/png") do
      denied = rpc(
        @viewer_token,
        "tools/call",
        name: "workspace_import_attachment",
        arguments: {
          id: @root.id.to_s,
          url: "https://files.example.test/secret.png",
          name: "Secret"
        }
      )
      assert denied.dig("result", "isError"), denied.to_json

      imported = rpc(
        @editor_token,
        "tools/call",
        name: "workspace_import_attachment",
        arguments: {
          id: @root.id.to_s,
          url: "https://files.example.test/door.png",
          name: "Door"
        }
      )
      refute imported.dig("result", "isError"), imported.to_json
      row = payload(imported)
      assert_equal "Door", row.fetch("name")
      assert_equal "image", row.fetch("kind")

      other = rpc(
        @editor_token,
        "tools/call",
        name: "workspace_import_attachment",
        arguments: {
          id: @page.id.to_s,
          url: "https://files.example.test/other.png",
          name: "Wrong"
        }
      )
      assert other.dig("result", "isError"), other.to_json
      assert_includes other.to_json, "does not match"
    end
  end

  private

  def properties(tool)
    tool.fetch("inputSchema").fetch("properties").transform_keys(&:to_s)
  end

  def upload_arguments(bytes, id: @root.id)
    {
      id: id.to_s,
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
    return structured if structured.is_a?(Hash) && (structured["signed_blob_id"] || structured["id"])

    JSON.parse(body.dig("result", "content", 0, "text").to_s)
  end

  def put_upload(ticket, bytes)
    uri = URI(ticket.dig("upload", "url"))
    put "#{uri.path}?#{uri.query}", params: bytes, headers: ticket.dig("upload", "headers")
    assert_response :no_content, response.body
  end

  def with_fetch(body, content_type:, addresses: ["8.8.8.8"])
    response = Struct.new(:body, :code, :headers, keyword_init: true) do
      def is_a?(klass)
        klass == Net::HTTPSuccess
      end

      def [](header)
        headers[header]
      end

      def read_body
        yield body.to_s if block_given?
        body
      end
    end.new(body: body, code: "200", headers: { "content-type" => content_type })

    with_stub(Resolv, :getaddresses, ->(_host) { addresses }) do
      with_stub(Net::HTTP, :start, lambda { |_host, _port, **_options, &http_block|
        http = Object.new
        http.define_singleton_method(:request) do |_request, &request_block|
          request_block ? request_block.call(response) : response
        end
        http_block.call(http)
      }) do
        yield
      end
    end
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
end
