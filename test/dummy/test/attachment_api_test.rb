# frozen_string_literal: true

require "test_helper"
require "base64"
require "digest"
require "net/http"

class AttachmentApiTest < ActionDispatch::IntegrationTest
  BASE = "/recording_studio_api/api/v1"

  setup do
    @previous_actor = Current.actor
    @owner = user("owner")
    @editor = user("editor")
    @viewer = user("viewer")
    Current.actor = @owner
    @workspace = Workspace.create!(name: "API #{SecureRandom.hex(4)}")
    @root = RecordingStudio.root_recording_for(@workspace)
    @owner_access = bootstrap!(@root, @owner)
    @editor_access = grant!(@editor, :edit)
    @viewer_access = grant!(@viewer, :view)
    @editor_token = token_for(@editor_access)
    @viewer_token = token_for(@viewer_access)
    @page = @root.record(Page, actor: @owner) { |page| page.title = "Notes" }
    @hosts = RecordingStudioAttachable.configuration.import_allowed_hosts.dup
    RecordingStudioAttachable.configuration.import_allowed_hosts = ["files.example.test"]
  end

  teardown do
    Current.actor = @previous_actor
    RecordingStudioAttachable.configuration.import_allowed_hosts = @hosts
  end

  test "create_upload put and attach records a child and an attachment_uploaded event" do
    bytes = png_bytes
    created = upload_ticket("photo.png", "image/png", bytes)
    assert_response :success, response.body
    put_upload(created, bytes)

    attached = call(:post, "/workspaces/#{@root.id}/actions/attach", @editor_token, signed_blob_id: created.fetch("signed_blob_id"), name: "Door", caption: "Front")
    assert_response :success, response.body
    assert_equal "image", attached.fetch("kind")
    assert_equal "Door", attached.fetch("name")
    assert attached.dig("urls", "file").present?

    child = RecordingStudio::Recording.find(attached.fetch("id"))
    assert_equal @root.id, child.parent_recording_id
    assert_equal "RecordingStudioAttachable::Attachment", child.recordable_type
    assert_equal "Front", child.recordable.caption
    assert child.events.exists?(action: "attachment_uploaded")
  end

  test "attach accepts a batch of uploaded files" do
    first = upload_ticket("one.png", "image/png", png_bytes)
    put_upload(first, png_bytes)
    second = upload_ticket("two.txt", "text/plain", "notes")
    put_upload(second, "notes")

    attached = call(:post, "/workspaces/#{@root.id}/actions/attach", @editor_token, attachments: [
      { signed_blob_id: first.fetch("signed_blob_id"), name: "One" },
      { signed_blob_id: second.fetch("signed_blob_id"), name: "Two", description: "Notes" }
    ])
    assert_response :success, response.body
    names = attached.fetch("attachments").map { |row| row.fetch("name") }
    assert_equal %w[One Two], names
    assert_equal 2, @root.child_recordings.where(recordable_type: "RecordingStudioAttachable::Attachment").count
  end

  test "import_attachment fetches an allowed url and rejects a private or disallowed host" do
    body = png_bytes
    with_fetch(body, content_type: "image/png") do
      imported = call(:post, "/workspaces/#{@root.id}/actions/import_attachment", @editor_token, url: "https://files.example.test/door.png", name: "Door")
      assert_response :success, response.body
      assert_equal "Door", imported.fetch("name")
      assert_equal "image", imported.fetch("kind")
    end

    with_fetch(body, content_type: "image/png", addresses: ["127.0.0.1"]) do
      call(:post, "/workspaces/#{@root.id}/actions/import_attachment", @editor_token, url: "https://files.example.test/local.png")
      assert_response :unprocessable_entity
      assert_equal "invalid_input", json.dig("error", "code")
      assert_includes json.dig("error", "message"), "private address"
    end

    call(:post, "/workspaces/#{@root.id}/actions/import_attachment", @editor_token, url: "https://evil.example.test/secret.png")
    assert_response :unprocessable_entity
    assert_includes json.dig("error", "message"), "not allowed"
  end

  test "create_upload rejects a bad content type, an oversized file, and a full storage limit" do
    before = ActiveStorage::Blob.count

    call(:post, "/workspaces/#{@root.id}/actions/create_upload", @editor_token, upload_params("virus.exe", "application/zip", "nope"))
    assert_response :unprocessable_entity
    assert_equal "invalid_input", json.dig("error", "code")
    assert_includes json.dig("error", "message"), "application/zip"

    call(:post, "/workspaces/#{@root.id}/actions/create_upload", @editor_token, upload_params("big.png", "image/png", "x", byte_size: 26.megabytes))
    assert_response :unprocessable_entity
    assert_includes json.dig("error", "message"), "maximum file size"
    assert_equal before, ActiveStorage::Blob.count

    with_stub(RecordingStudioAttachable::StorageLimit, :with_storage_capacity!, ->(*) { raise RecordingStudioAttachable::StorageLimitError, "Storage is full" }) do
      call(:post, "/workspaces/#{@root.id}/actions/create_upload", @editor_token, upload_params("photo.png", "image/png", "tiny"))
    end
    assert_response :unprocessable_entity
    assert_equal "Storage is full", json.dig("error", "message")
    assert_equal before, ActiveStorage::Blob.count
  end

  test "attach rejects a forged or expired signed blob id" do
    call(:post, "/workspaces/#{@root.id}/actions/attach", @editor_token, signed_blob_id: "forged")
    assert_response :unprocessable_entity
    assert_equal "invalid_input", json.dig("error", "code")

    blob = ActiveStorage::Blob.create_before_direct_upload!(**upload_params("photo.png", "image/png", "bytes").slice(:filename, :byte_size, :checksum, :content_type))
    expired = blob.signed_id(expires_in: 1.minute)
    travel 2.minutes do
      call(:post, "/workspaces/#{@root.id}/actions/attach", @editor_token, signed_blob_id: expired)
      assert_response :unprocessable_entity
      assert_equal "invalid_input", json.dig("error", "code")
    end
  end

  test "attach rejects a reused blob, another actor, and bytes that do not match the declared type" do
    created = upload_ticket("photo.png", "image/png", png_bytes)
    put_upload(created, png_bytes)
    signed_id = created.fetch("signed_blob_id")
    call(:post, "/workspaces/#{@root.id}/actions/attach", @editor_token, signed_blob_id: signed_id, name: "Door")
    assert_response :success

    call(:post, "/workspaces/#{@root.id}/actions/attach", @editor_token, signed_blob_id: signed_id, name: "Again")
    assert_response :unprocessable_entity
    assert_includes json.dig("error", "message"), "already attached"

    other = user("other-editor")
    other_token = token_for(grant!(other, :edit))
    ticket = upload_ticket("second.png", "image/png", png_bytes)
    put_upload(ticket, png_bytes)
    call(:post, "/workspaces/#{@root.id}/actions/attach", other_token, signed_blob_id: ticket.fetch("signed_blob_id"))
    assert_response :unprocessable_entity
    assert_includes json.dig("error", "message"), "actor"

    mismatch = upload_ticket("fake.png", "image/png", "not-a-png")
    put_upload(mismatch, "not-a-png")
    call(:post, "/workspaces/#{@root.id}/actions/attach", @editor_token, signed_blob_id: mismatch.fetch("signed_blob_id"))
    assert_response :unprocessable_entity
    assert_includes json.dig("error", "message"), "does not match"
  end

  test "create_upload caps pending uploads" do
    previous = RecordingStudioAttachable.configuration.pending_upload_limit
    RecordingStudioAttachable.configuration.pending_upload_limit = 1
    upload_ticket("one.png", "image/png", png_bytes)
    assert_response :success
    call(:post, "/workspaces/#{@root.id}/actions/create_upload", @editor_token, upload_params("two.png", "image/png", png_bytes))
    assert_response :unprocessable_entity
    assert_includes json.dig("error", "message"), "pending"
  ensure
    RecordingStudioAttachable.configuration.pending_upload_limit = previous
  end

  test "import rejects a sniffed type mismatch and an svg content type" do
    with_fetch("not-a-png", content_type: "image/png") do
      call(:post, "/workspaces/#{@root.id}/actions/import_attachment", @editor_token, url: "https://files.example.test/fake.png")
      assert_response :unprocessable_entity
      assert_includes json.dig("error", "message"), "does not match"
    end

    with_fetch(png_bytes, content_type: "image/svg+xml") do
      call(:post, "/workspaces/#{@root.id}/actions/import_attachment", @editor_token, url: "https://files.example.test/icon.svg")
      assert_response :unprocessable_entity
      assert_includes json.dig("error", "message"), "not allowed"
    end
  end

  test "a viewer cannot upload and a type that does not allow the action is omitted" do
    call(:post, "/workspaces/#{@root.id}/actions/create_upload", @viewer_token, upload_params("photo.png", "image/png", "x"))
    assert_response :forbidden
    assert_equal "forbidden", json.dig("error", "code")

    call(:post, "/pages/#{@page.id}/actions/create_upload", @editor_token, upload_params("photo.png", "image/png", "x"))
    assert_response :unprocessable_entity
    assert_equal "unsupported_action", json.dig("error", "code")

    call(:post, "/missing_types/#{@root.id}/actions/create_upload", @editor_token, upload_params("photo.png", "image/png", "x"))
    assert_response :not_found

    get "/APIdocs/v1/openapi.json"
    assert_response :success
    paths = JSON.parse(response.body).fetch("paths").keys
    assert paths.any? { |path| path.include?("/workspaces/") && path.include?("create_upload") }
    assert paths.any? { |path| path.include?("/workspaces/") && path.include?("import_attachment") }
    refute paths.any? { |path| path.include?("/pages/") && path.include?("create_upload") }
    refute paths.any? { |path| path.include?("/pages/") && path.include?("attach") }
  end

  test "the actions are registered on the public and operations APIs" do
    %i[public operations].each do |api|
      action = RecordingStudioApi.capability_action(:create_upload, api: api)
      assert_equal :attachable, action.capability
      assert_equal :member, action.scope
      assert_equal :edit, action.required_role
      assert RecordingStudioApi.capability_action(:attach, api: api)
      assert RecordingStudioApi.capability_action(:import_attachment, api: api)
    end
  end

  private

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
      name: "Client #{SecureRandom.hex(3)}"
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

  def headers(token)
    { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }
  end

  def call(method, path, token, params = {})
    send(method, "#{BASE}#{path}", params: params, headers: headers(token), as: :json)
    response.media_type.to_s.include?("json") ? JSON.parse(response.body) : {}
  rescue JSON::ParserError
    {}
  end

  def json
    JSON.parse(response.body)
  end

  def png_bytes
    Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")
  end

  def upload_params(filename, content_type, bytes, byte_size: bytes.bytesize)
    {
      filename: filename,
      byte_size: byte_size,
      checksum: Base64.strict_encode64(Digest::MD5.digest(bytes)),
      content_type: content_type
    }
  end

  def upload_ticket(filename, content_type, bytes)
    call(:post, "/workspaces/#{@root.id}/actions/create_upload", @editor_token, upload_params(filename, content_type, bytes))
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
