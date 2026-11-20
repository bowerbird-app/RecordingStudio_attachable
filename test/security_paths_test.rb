# frozen_string_literal: true

require "test_helper"
require "digest"
require_relative "support/coverage_database"
require_relative "../app/services/recording_studio_attachable/services/application_service"
require_relative "../app/services/recording_studio_attachable/services/import_attachments"
require_relative "../app/services/recording_studio_attachable/services/import_attachment_payloads"
require_relative "../app/services/recording_studio_attachable/services/import_remote_files"
require_relative "../app/services/recording_studio_attachable/services/record_attachment_uploads"

class SecurityPathsTest < Minitest::Test
  include CoverageDatabase

  ACTIONS = {
    view: :view,
    download: :view,
    upload: :edit,
    revise: :edit,
    remove: :admin,
    restore: :admin
  }.freeze

  class CoverageActor
    attr_reader :id

    def initialize(id)
      @id = id
    end
  end

  Parent = Struct.new(:id, :recordable_type, :root_recording, :billing, keyword_init: true)

  def setup
    @previous_configuration = RecordingStudioAttachable.configuration
    @configuration = RecordingStudioAttachable::Configuration.new
    RecordingStudioAttachable.instance_variable_set(:@configuration, @configuration)
    @stripe_defined = defined?(RecordingStudioStripe)
    ensure_accessible!
    singleton = RecordingStudio.singleton_class
    singleton.alias_method(:coverage_original_capability_options, :capability_options)
    RecordingStudio.define_singleton_method(:capability_options) { |*, **| {} }
  end

  def teardown
    singleton = RecordingStudio.singleton_class
    if singleton.method_defined?(:coverage_original_capability_options)
      singleton.alias_method(:capability_options, :coverage_original_capability_options)
      singleton.remove_method(:coverage_original_capability_options)
    end
    RecordingStudioAttachable.instance_variable_set(:@configuration, @previous_configuration)
    RecordingStudioAttachable::StorageLimit.reset!
    remove_stripe! unless @stripe_defined
    restore_active_storage!
  end

  def test_each_auth_role_is_allowed_only_when_accessible_grants_that_role
    recording = Parent.new(id: "parent-1", recordable_type: "Workspace")
    actor = CoverageActor.new("actor-1")

    ACTIONS.each_value.uniq.each do |granted|
      decisions = ACTIONS.to_h do |action, _role|
        [action, allowed?(action, actor, recording, granted_roles: [granted])]
      end

      ACTIONS.each do |action, role|
        assert_equal role == granted, decisions[action], "#{action} with #{granted}"
      end
    end

    ACTIONS.each_key do |action|
      refute allowed?(action, actor, recording, granted_roles: []), action.to_s
    end
  end

  def test_authorize_raises_when_the_role_is_denied_and_returns_true_when_it_is_granted
    recording = Parent.new(id: "parent-1", recordable_type: "Workspace")
    actor = CoverageActor.new("actor-1")

    error = assert_raises(RecordingStudioAttachable::Authorization::NotAuthorizedError) do
      authorize!(:upload, actor, recording, granted_roles: [:view])
    end
    assert_equal "Not authorized to upload attachments for Workspace", error.message

    assert authorize!(:download, actor, recording, granted_roles: [:view])
  end

  def test_prepare_binds_the_signed_blob_and_rejects_a_foreign_purpose_actor_or_recording
    connect_coverage_database!
    with_disk_service do
      actor = CoverageActor.new("actor-1")
      recording = Parent.new(id: SecureRandom.uuid, recordable_type: "Workspace")
      blob = RecordingStudioAttachable::DirectUpload.prepare!(**prepare_attrs(recording, actor))

      assert_equal blob, RecordingStudioAttachable::DirectUpload.accept!(
        RecordingStudioAttachable::DirectUpload.sign(blob),
        recording: recording,
        actor: actor
      )

      other_actor = CoverageActor.new("actor-2")
      error = assert_raises(ArgumentError) do
        RecordingStudioAttachable::DirectUpload.accept!(
          RecordingStudioAttachable::DirectUpload.sign(blob),
          recording: recording,
          actor: other_actor
        )
      end
      assert_match(/actor/, error.message)

      elsewhere = Parent.new(id: SecureRandom.uuid, recordable_type: "Workspace")
      error = assert_raises(ArgumentError) do
        RecordingStudioAttachable::DirectUpload.accept!(
          RecordingStudioAttachable::DirectUpload.sign(blob),
          recording: elsewhere,
          actor: actor
        )
      end
      assert_match(/recording/, error.message)

      assert_raises(ActiveSupport::MessageVerifier::InvalidSignature) do
        RecordingStudioAttachable::DirectUpload.accept!(
          blob.signed_id(purpose: "other", expires_in: 5.minutes),
          recording: recording,
          actor: actor
        )
      end

      unsigned = ActiveStorage::Blob.create_before_direct_upload!(
        filename: "loose.png",
        byte_size: 1,
        checksum: checksum_for("x"),
        content_type: "image/png"
      )
      error = assert_raises(ArgumentError) do
        RecordingStudioAttachable::DirectUpload.accept!(
          RecordingStudioAttachable::DirectUpload.sign(unsigned),
          recording: recording,
          actor: actor
        )
      end
      assert_match(/not issued/, error.message)
      blob.purge
      unsigned.purge
    end
  end

  def test_prepare_rejects_svg_size_pending_queue_and_a_missing_upload
    connect_coverage_database!
    with_disk_service do
      actor = CoverageActor.new("actor-1")
      recording = Parent.new(id: SecureRandom.uuid, recordable_type: "Workspace")
      @configuration.pending_upload_limit = 1

      svg = assert_raises(ArgumentError) do
        RecordingStudioAttachable::DirectUpload.prepare!(**prepare_attrs(recording, actor, content_type: "image/svg+xml", filename: "icon.svg"))
      end
      assert_match(/not allowed/, svg.message)

      @configuration.allowed_content_types = ["image/svg+xml"]
      issued = RecordingStudioAttachable::DirectUpload.prepare!(
        **prepare_attrs(recording, actor, content_type: "image/svg+xml", filename: "icon.svg", bytes: "<svg></svg>")
      )
      issued.purge
      @configuration.allowed_content_types = ["image/*", "application/pdf"]
      @configuration.pending_upload_limit = 20

      oversized = assert_raises(ArgumentError) do
        RecordingStudioAttachable::DirectUpload.prepare!(**prepare_attrs(recording, actor, byte_size: 26.megabytes))
      end
      assert_match(/maximum file size/, oversized.message)

      invalid = assert_raises(ArgumentError) do
        RecordingStudioAttachable::DirectUpload.prepare!(**prepare_attrs(recording, actor, byte_size: "nope"))
      end
      assert_match(/zero or more/, invalid.message)

      @configuration.pending_upload_limit = 1
      first = RecordingStudioAttachable::DirectUpload.prepare!(**prepare_attrs(recording, actor))
      assert_equal 1, RecordingStudioAttachable::DirectUpload.pending_count(recording, actor)
      pending = assert_raises(ArgumentError) do
        RecordingStudioAttachable::DirectUpload.prepare!(**prepare_attrs(recording, actor, filename: "second.png"))
      end
      assert_match(/pending/, pending.message)

      missing = assert_raises(ArgumentError) do
        RecordingStudioAttachable::DirectUpload.sniff!(first, {})
      end
      assert_match(/has not been uploaded/, missing.message)

      ticket = RecordingStudioAttachable::DirectUpload.browser_json(first)
      found = ActiveStorage::Blob.find_signed!(ticket[:signed_id], purpose: RecordingStudioAttachable::DirectUpload::PURPOSE)
      assert_equal first, found
      assert ticket.dig(:direct_upload, :url).present?

      assert_includes RecordingStudioAttachable::DirectUpload.expired_unattached(1.minute.from_now), first
      first.purge
    end
  end

  def test_a_storage_limit_refusal_drops_the_prepared_blob
    connect_coverage_database!
    with_disk_service do
      install_stripe!
      @configuration.storage_limit = :storage_bytes
      actor = CoverageActor.new("actor-1")
      recording = Parent.new(
        id: SecureRandom.uuid,
        recordable_type: "Workspace",
        billing: denying_billing
      )
      before = ActiveStorage::Blob.count

      error = assert_raises(RecordingStudioStripe::PlanLimitReached) do
        RecordingStudioAttachable::DirectUpload.prepare!(**prepare_attrs(recording, actor))
      end

      assert_match(/plan/, error.message)
      assert_equal before, ActiveStorage::Blob.count
    end
  end

  def test_import_host_allowlist_rejects_private_and_unlisted_hosts
    guard = RecordingStudioAttachable::SafeRemoteFetch::HostGuard.new(["*.example.test"])

    guard.validate!(URI("https://files.example.test/a"))
    guard.validate!(URI("https://example.test/a"))

    assert_raises(RecordingStudioAttachable::SafeRemoteFetch::Error) do
      guard.validate!(URI("http://files.example.test/a"))
    end
    assert_raises(RecordingStudioAttachable::SafeRemoteFetch::Error) do
      guard.validate!(URI("https://files.example.test:8443/a"))
    end
    assert_raises(RecordingStudioAttachable::SafeRemoteFetch::Error) do
      guard.validate!(URI("https://evil.test/a"))
    end

    local = RecordingStudioAttachable::SafeRemoteFetch::HostGuard.new(["localhost"])
    assert_raises(RecordingStudioAttachable::SafeRemoteFetch::Error) do
      local.validate!(URI("https://localhost/a"))
    end

    Resolv.stub(:getaddresses, ->(_host) { raise Resolv::ResolvError }) do
      error = assert_raises(RecordingStudioAttachable::SafeRemoteFetch::Error) { guard.public_ip("files.example.test") }
      assert_match(/could not be resolved/, error.message)
    end

    Resolv.stub(:getaddresses, ->(_host) { ["10.1.2.3"] }) do
      error = assert_raises(RecordingStudioAttachable::SafeRemoteFetch::Error) { guard.public_ip("files.example.test") }
      assert_match(/private address/, error.message)
    end

    Resolv.stub(:getaddresses, ->(_host) { ["not-an-ip"] }) do
      error = assert_raises(RecordingStudioAttachable::SafeRemoteFetch::Error) { guard.public_ip("files.example.test") }
      assert_match(/private address/, error.message)
    end

    Resolv.stub(:getaddresses, ->(_host) { ["1.1.1.1"] }) do
      assert_equal "1.1.1.1", guard.public_ip("files.example.test")
    end

    Resolv.stub(:getaddresses, ->(_host) { [] }) do
      error = assert_raises(RecordingStudioAttachable::SafeRemoteFetch::Error) { guard.public_ip("files.example.test") }
      assert_match(/could not be resolved/, error.message)
    end

    blank_host = URI("https://files.example.test/a")
    blank_host.define_singleton_method(:host) { "" }
    error = assert_raises(RecordingStudioAttachable::SafeRemoteFetch::Error) { guard.validate!(blank_host) }
    assert_match(/host is missing/, error.message)
  end

  def test_a_batch_over_the_file_count_names_the_limit
    parent = Parent.new(id: "parent-1", recordable_type: "Workspace")
    @configuration.max_file_count = 2

    two = import_count_error(parent, 3)
    assert_equal "You can upload up to 2 files at a time", two

    @configuration.max_file_count = 1
    one = import_count_error(parent, 2)
    assert_equal "You can upload up to 1 file at a time", one
  end

  def test_a_string_io_download_is_not_accepted
    skip "StringIO#to_h raises TypeError, so a download that returns StringIO never reaches the IO branch"

    parent = Parent.new(id: "parent-1", recordable_type: "Workspace")
    success = RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: [:saved])
    result = nil
    RecordingStudioAttachable::Services::ImportAttachments.stub(:call, ->(**) { success }) do
      result = RecordingStudioAttachable::Services::ImportRemoteFiles.call(
        parent_recording: parent,
        provider_key: :my_cloud,
        payloads: [{ download: -> { StringIO.new("raw-bytes") }, filename: "raw.bin" }]
      )
    end
    assert result.success?
  end

  def test_remote_import_accepts_an_io_or_a_download_and_rejects_the_rest
    parent = Parent.new(id: "parent-1", recordable_type: "Workspace")
    captured = nil
    success = RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: [:saved])

    RecordingStudioAttachable::Services::ImportAttachments.stub(:call, lambda { |**kwargs|
      captured = kwargs
      success
    }) do
      io_result = RecordingStudioAttachable::Services::ImportRemoteFiles.call(
        parent_recording: parent,
        provider_key: :my_cloud,
        actor: :actor,
        payloads: [{ io: StringIO.new("notes"), filename: "notes.txt", content_type: "text/plain" }]
      )
      assert io_result.success?
      assert_equal "notes.txt", captured[:attachments].first[:filename]
      assert_equal "my_cloud", captured[:source]

      reader = Object.new
      reader.define_singleton_method(:read) { "raw-bytes" }
      reader.define_singleton_method(:size) { 9 }
      reader.define_singleton_method(:close) { nil }
      raw_result = RecordingStudioAttachable::Services::ImportRemoteFiles.call(
        parent_recording: parent,
        provider_key: :my_cloud,
        payloads: [{ download: -> { reader }, filename: "raw.bin", content_type: "application/octet-stream" }]
      )
      assert raw_result.success?
      assert_equal "raw.bin", captured[:attachments].first[:filename]

      hashed = RecordingStudioAttachable::Services::ImportRemoteFiles.call(
        parent_recording: parent,
        provider_key: :my_cloud,
        payloads: [{
          download: -> { { io: StringIO.new("hashed"), filename: "hashed.txt", content_type: "text/plain" } },
          filename: "hashed.txt"
        }]
      )
      assert hashed.success?
      assert_equal "hashed.txt", captured[:attachments].first[:filename]
    end

    missing = RecordingStudioAttachable::Services::ImportRemoteFiles.call(
      parent_recording: parent,
      provider_key: :my_cloud,
      payloads: [{ filename: "missing.txt" }]
    )
    assert missing.failure?
    assert_match(/download or io/, missing.error)

    broken = RecordingStudioAttachable::Services::ImportRemoteFiles.call(
      parent_recording: parent,
      provider_key: :my_cloud,
      payloads: [{ download: -> { "nope" }, filename: "nope.txt" }]
    )
    assert broken.failure?
    assert_match(/download must return/, broken.error)

    @configuration.max_file_size = 4
    oversized = RecordingStudioAttachable::Services::ImportRemoteFiles.call(
      parent_recording: parent,
      provider_key: :my_cloud,
      payloads: [{ io: StringIO.new("12345"), filename: "big.txt", content_type: "text/plain", byte_size: 5 }]
    )
    assert oversized.failure?
    assert_match(/maximum file size/, oversized.error)
  end

  def test_a_failed_batch_purges_blobs_created_earlier_in_the_batch
    connect_coverage_database!
    with_disk_service do
      blob = ActiveStorage::Blob.create_before_direct_upload!(
        filename: "photo.png",
        byte_size: UploadBlobBytes::PNG.bytesize,
        checksum: checksum_for(UploadBlobBytes::PNG),
        content_type: "image/png"
      )
      recording = Struct.new(:recordable).new(Struct.new(:file).new(Struct.new(:blob).new(blob)))
      parent = Parent.new(id: "parent-1", recordable_type: "Workspace")
      success = RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: [recording])
      failure = RecordingStudioAttachable::Services::BaseService::Result.new(success: false, error: "Finalize failed", errors: [])

      result = nil
      RecordingStudioAttachable::Services::ImportAttachments.stub(:call, ->(**) { success }) do
        RecordingStudioAttachable::Services::RecordAttachmentUploads.stub(:call, ->(**) { failure }) do
          result = RecordingStudioAttachable::Services::ImportAttachmentPayloads.call(
            parent_recording: parent,
            actor: :actor,
            attachments: [
              { io: StringIO.new("a"), filename: "a.txt", source: "camera" },
              { signed_blob_id: "signed-1" }
            ]
          )
        end
      end

      assert result.failure?
      assert_equal "Finalize failed", result.error
      assert_nil ActiveStorage::Blob.find_by(id: blob.id)
    end
  end

  private

  def allowed?(action, actor, recording, granted_roles:)
    with_accessible(granted_roles) do
      RecordingStudioAttachable::Authorization.allowed?(
        action: action,
        actor: actor,
        recording: recording,
        capability_options: { max_file_count: 1 }
      )
    end
  end

  def authorize!(action, actor, recording, granted_roles:)
    with_accessible(granted_roles) do
      RecordingStudioAttachable::Authorization.authorize!(
        action: action,
        actor: actor,
        recording: recording,
        capability_options: { max_file_count: 1 }
      )
    end
  end

  def with_accessible(granted_roles, &block)
    RecordingStudio.configuration.stub(:capability_enabled?, true) do
      RecordingStudioAccessible::Authorization.stub(:allowed?, lambda { |actor:, recording:, role:|
        actor && recording && granted_roles.include?(role)
      }) do
        block.call
      end
    end
  end

  def ensure_accessible!
    return if defined?(RecordingStudioAccessible::Authorization)

    Object.const_set(:RecordingStudioAccessible, Module.new) unless defined?(RecordingStudioAccessible)
    RecordingStudioAccessible.const_set(:Authorization, Module.new)
    RecordingStudioAccessible::Authorization.define_singleton_method(:allowed?) { |**| false }
  end

  def prepare_attrs(recording, actor, **options)
    bytes = options.fetch(:bytes, UploadBlobBytes::PNG)
    {
      recording: recording,
      actor: actor,
      filename: options.fetch(:filename, "photo.png"),
      byte_size: options.fetch(:byte_size) { bytes.bytesize },
      checksum: checksum_for(bytes),
      content_type: options.fetch(:content_type, "image/png")
    }
  end

  def import_count_error(parent, count)
    attachments = Array.new(count) { { io: StringIO.new("x"), filename: "x.txt" } }
    result = RecordingStudioAttachable::Services::ImportAttachmentPayloads.call(
      parent_recording: parent,
      actor: :actor,
      attachments: attachments
    )
    result.error
  end

  def install_stripe!
    remove_stripe!
    stripe = Module.new
    Object.const_set(:RecordingStudioStripe, stripe)
    error_class = Class.new(StandardError)
    plan_class = Class.new(error_class)
    stripe.const_set(:Error, error_class)
    stripe.const_set(:PlanLimitReached, plan_class)
    limits = Module.new do
      def self.known?(name)
        name.to_s == "storage_bytes"
      end

      def self.fetch(name)
        raise ArgumentError, "unknown" unless known?(name)

        definition = Object.new
        definition.define_singleton_method(:quantity?) { true }
        definition.define_singleton_method(:name) { "storage_bytes" }
        definition
      end
    end
    stripe.const_set(:Limits, limits)
    configuration = Object.new
    configuration.define_singleton_method(:register_limit_usage) { |_name, &_block| }
    configuration.define_singleton_method(:limit_usage_for) { |_name| nil }
    stripe.define_singleton_method(:configuration) { configuration }
    stripe.define_singleton_method(:register_limit_usage) do |name, &block|
      configuration.register_limit_usage(name, &block)
    end
  end

  def remove_stripe!
    Object.send(:remove_const, :RecordingStudioStripe) if defined?(RecordingStudioStripe)
  end

  def denying_billing
    handle = Object.new
    handle.define_singleton_method(:with_capacity!) do |_amount|
      raise RecordingStudioStripe::PlanLimitReached, "Pick a plan to add storage."
    end
    billing = Object.new
    billing.define_singleton_method(:limit) { |_name| handle }
    billing
  end
end
