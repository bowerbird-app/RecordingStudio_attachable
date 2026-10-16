# frozen_string_literal: true

require "test_helper"
require_relative "../../app/services/recording_studio_attachable/services/application_service"
require_relative "../../app/services/recording_studio_attachable/services/record_attachment_upload"
require_relative "../../app/services/recording_studio_attachable/services/record_attachment_uploads"
require_relative "../../app/services/recording_studio_attachable/services/import_attachment"

class AttachmentActionsTest < Minitest::Test
  FakeContext = Struct.new(:recording, :params, :actor, keyword_init: true)
  FakeRecording = Struct.new(:id, :recordable_type, :root_recording, keyword_init: true)
  FakeBlob = Struct.new(:id, :persisted, :purged, keyword_init: true) do
    def persisted?
      persisted
    end

    def signed_id(purpose: nil, expires_in: nil)
      "signed-#{purpose}-#{expires_in}"
    end

    def service_url_for_direct_upload(expires_in:)
      "https://uploads.example.test/#{expires_in}"
    end

    def service_headers_for_direct_upload
      { "Content-Type" => "image/png", "Content-MD5" => "checksum" }
    end

    def attachments
      nil
    end

    def purge
      self.purged = true
    end
  end

  def setup
    ensure_blob!
    @configuration = RecordingStudioAttachable.configuration
    @original_hosts = @configuration.import_allowed_hosts.dup
    @original_roles = @configuration.auth_roles.dup
    install_api_errors!
    stub_capability_options!
  end

  def teardown
    @configuration.import_allowed_hosts = @original_hosts
    @configuration.auth_roles = @original_roles
    remove_api_errors!
    restore_capability_options!
  end

  def test_register_waits_until_the_api_gem_is_loaded
    hide_api = RecordingStudioApi
    Object.send(:remove_const, :RecordingStudioApi)

    assert_nil RecordingStudioAttachable::Api.register!
  ensure
    Object.const_set(:RecordingStudioApi, hide_api) unless defined?(::RecordingStudioApi)
  end

  def test_import_role_uses_import_when_that_auth_role_exists
    @configuration.auth_roles = @configuration.auth_roles.merge(import: :admin)

    assert_equal :admin, RecordingStudioAttachable::Api.role_for(:import_attachment)
    assert_equal :edit, RecordingStudioAttachable::Api.role_for(:create_upload)
  end

  def test_create_upload_returns_a_direct_upload_ticket
    blob = FakeBlob.new(id: "blob-1", persisted: true, purged: false)
    created = nil

    ActiveStorage::Blob.stub(:create_before_direct_upload!, lambda { |**attributes|
      created = attributes
      blob
    }) do
      RecordingStudioAttachable::StorageLimit.stub(:with_storage_capacity!, ->(_root, _incoming, &block) { block.call }) do
        ticket = create_upload.call(context(content_type: "image/png", byte_size: 12))

        assert_equal "image/png", created[:content_type]
        assert_equal 12, created[:byte_size]
        assert_equal "1", created.dig(:metadata, RecordingStudioAttachable::DirectUpload::TAG)
        assert_equal "parent-1", created.dig(:metadata, "parent_recording_id")
        assert_equal "Symbol", created.dig(:metadata, "actor_type")
        assert_equal "actor", created.dig(:metadata, "actor_id")
        assert_match(/\Asigned-attachable_upload-/, ticket[:signed_blob_id])
        assert_match(%r{\Ahttps://uploads\.example\.test/}, ticket.dig(:upload, :url))
        assert_equal "image/png", ticket.dig(:upload, :headers, "Content-Type")
        assert ticket[:expires_at].present?
        assert_equal false, blob.purged
      end
    end
  end

  def test_create_upload_rejects_a_disallowed_content_type_before_creating_a_blob
    called = false
    ActiveStorage::Blob.stub(:create_before_direct_upload!, ->(**) { called = true }) do
      error = assert_raises(RecordingStudioApi::InvalidActionInputError) do
        create_upload.call(context(content_type: "application/zip", byte_size: 12))
      end

      assert_includes error.message, "application/zip"
      assert_equal false, called
    end
  end

  def test_create_upload_rejects_an_oversized_file_and_a_negative_size
    ActiveStorage::Blob.stub(:create_before_direct_upload!, ->(**) { flunk "created a blob" }) do
      oversized = assert_raises(RecordingStudioApi::InvalidActionInputError) do
        create_upload.call(context(content_type: "image/png", byte_size: 26.megabytes))
      end
      negative = assert_raises(RecordingStudioApi::InvalidActionInputError) do
        create_upload.call(context(content_type: "image/png", byte_size: -1))
      end

      assert_includes oversized.message, "maximum file size"
      assert_includes negative.message, "zero or more"
    end
  end

  def test_create_upload_uses_its_own_expiry_and_rejects_a_full_pending_queue
    blob = FakeBlob.new(id: "blob-1", persisted: true, purged: false)
    @configuration.direct_upload_expires_in = 2.minutes
    @configuration.pending_upload_limit = 1

    ActiveStorage::Blob.stub(:create_before_direct_upload!, blob) do
      RecordingStudioAttachable::StorageLimit.stub(:with_storage_capacity!, ->(_root, _incoming, &block) { block.call }) do
        ticket = create_upload.call(context(content_type: "image/png", byte_size: 12))
        assert_includes ticket.dig(:upload, :url), 2.minutes.to_s
        assert_in_delta 2.minutes.from_now.to_i, Time.iso8601(ticket[:expires_at]).to_i, 2

        RecordingStudioAttachable::DirectUpload.stub(:pending_count, 1) do
          error = assert_raises(RecordingStudioApi::InvalidActionInputError) do
            create_upload.call(context(content_type: "image/png", byte_size: 12))
          end
          assert_includes error.message, "pending"
        end
      end
    end
  end

  def test_create_upload_drops_the_blob_when_storage_capacity_is_refused
    blob = FakeBlob.new(id: "blob-1", persisted: true, purged: false)

    ActiveStorage::Blob.stub(:create_before_direct_upload!, blob) do
      RecordingStudioAttachable::StorageLimit.stub(:with_storage_capacity!, ->(*) { raise RecordingStudioAttachable::StorageLimitError, "Storage is full" }) do
        error = assert_raises(RecordingStudioApi::InvalidActionInputError) do
          create_upload.call(context(content_type: "image/png", byte_size: 12))
        end

        assert_equal "Storage is full", error.message
        assert_equal true, blob.purged
      end
    end
  end

  def test_attach_uses_one_service_for_a_single_file_and_the_batch_service_for_many
    single = nil
    batch = nil
    success = Struct.new(:success?, :value, :error, :errors).new(true, :recording, nil, [])

    RecordingStudioAttachable::Services::RecordAttachmentUpload.stub(:call, lambda { |**kwargs|
      single = kwargs
      success
    }) do
      RecordingStudioAttachable::Api::AttachmentActions::Payload.stub(:one, { id: "child-1" }) do
        result = attach.call(context_for(signed_blob_id: "signed-1", caption: "Door"))
        assert_equal "child-1", result[:id]
      end
    end

    assert_equal "signed-1", single[:signed_blob_id]
    assert_equal "Door", single[:caption]
    assert_equal :actor, single[:actor]

    many = Struct.new(:success?, :value, :error, :errors).new(true, %i[first second], nil, [])
    RecordingStudioAttachable::Services::RecordAttachmentUploads.stub(:call, lambda { |**kwargs|
      batch = kwargs
      many
    }) do
      RecordingStudioAttachable::Api::AttachmentActions::Payload.stub(:many, { attachments: [{ id: "a" }, { id: "b" }] }) do
        result = attach.call(context_for(attachments: [{ signed_blob_id: "one" }, { signed_blob_id: "two", name: "Two" }]))
        assert_equal 2, result[:attachments].size
      end
    end

    signed_ids = batch[:attachments].map { |item| item[:signed_blob_id] }
    assert_equal %w[one two], signed_ids
    assert_equal "Two", batch[:attachments].last[:name]
  end

  def test_attach_maps_validation_failures_and_authorization_failures
    failure = Struct.new(:success?, :value, :error, :errors).new(false, nil, "Blob exceeds maximum file size", [])
    denied = Struct.new(:success?, :value, :error, :errors).new(false, nil, "Not authorized to upload attachments", [])

    RecordingStudioAttachable::Services::RecordAttachmentUpload.stub(:call, failure) do
      assert_raises(RecordingStudioApi::InvalidActionInputError) do
        attach.call(context_for(signed_blob_id: "signed-1"))
      end
    end

    RecordingStudioAttachable::Services::RecordAttachmentUpload.stub(:call, denied) do
      assert_raises(RecordingStudioApi::AuthorizationError) do
        attach.call(context_for(signed_blob_id: "signed-1"))
      end
    end
  end

  def test_import_rejects_a_private_address_and_a_host_outside_the_allowlist
    @configuration.import_allowed_hosts = ["files.example.test"]

    disallowed = assert_raises(RecordingStudioApi::InvalidActionInputError) do
      import.call(context_for(url: "https://evil.example.test/secret.png"))
    end
    assert_includes disallowed.message, "not allowed"

    Resolv.stub(:getaddresses, ->(_host) { ["127.0.0.1"] }) do
      private_host = assert_raises(RecordingStudioApi::InvalidActionInputError) do
        import.call(context_for(url: "https://files.example.test/secret.png"))
      end
      assert_includes private_host.message, "private address"
    end
  end

  private

  def create_upload
    RecordingStudioAttachable::Api::AttachmentActions::CreateUpload
  end

  def attach
    RecordingStudioAttachable::Api::AttachmentActions::Attach
  end

  def import
    RecordingStudioAttachable::Api::AttachmentActions::ImportAttachment
  end

  def context(content_type:, byte_size:)
    root = FakeRecording.new(id: "root-1", recordable_type: "Workspace")
    recording = FakeRecording.new(id: "parent-1", recordable_type: "Workspace", root_recording: root)
    FakeContext.new(
      recording: recording,
      actor: :actor,
      params: { filename: "photo.png", byte_size: byte_size, checksum: "checksum", content_type: content_type }
    )
  end

  def context_for(params)
    root = FakeRecording.new(id: "root-1", recordable_type: "Workspace")
    recording = FakeRecording.new(id: "parent-1", recordable_type: "Workspace", root_recording: root)
    FakeContext.new(recording: recording, actor: :actor, params: params)
  end

  def ensure_blob!
    ActiveStorage.const_set(:Blob, Class.new) unless defined?(ActiveStorage::Blob)
    return if ActiveStorage::Blob.respond_to?(:create_before_direct_upload!)

    ActiveStorage::Blob.define_singleton_method(:create_before_direct_upload!) { |**| raise NotImplementedError }
  end

  def install_api_errors!
    return if defined?(::RecordingStudioApi)

    stub = Module.new
    Object.const_set(:RecordingStudioApi, stub)
    error = Class.new(StandardError)
    stub.const_set(:Error, error)
    invalid = Class.new(error) do
      attr_reader :details

      def initialize(message = "invalid", details: [])
        super(message)
        @details = details
      end
    end
    stub.const_set(:InvalidActionInputError, invalid)
    stub.const_set(:AuthorizationError, Class.new(error))
    @installed_api_errors = true
  end

  def remove_api_errors!
    return unless @installed_api_errors

    Object.send(:remove_const, :RecordingStudioApi)
  end

  def stub_capability_options!
    @studio = RecordingStudio
    singleton = @studio.singleton_class
    @had_capability_options = singleton.method_defined?(:capability_options)
    @original_capability_options = @studio.method(:capability_options) if @had_capability_options
    singleton.send(:remove_method, :capability_options) if @had_capability_options
    @studio.define_singleton_method(:capability_options) { |_name, _for_type: nil, **| {} }
  end

  def restore_capability_options!
    singleton = @studio.singleton_class
    singleton.send(:remove_method, :capability_options) if singleton.method_defined?(:capability_options)
    return unless @had_capability_options

    original = @original_capability_options
    @studio.define_singleton_method(:capability_options) { |*args, **kwargs| original.call(*args, **kwargs) }
  end
end
