# frozen_string_literal: true

require "test_helper"
require "stringio"
require_relative "../app/services/recording_studio_attachable/services/application_service"
require_relative "../app/services/recording_studio_attachable/services/record_attachment_upload"
require_relative "../app/services/recording_studio_attachable/services/record_attachment_uploads"
require_relative "../app/services/recording_studio_attachable/services/import_attachment"
require_relative "../app/services/recording_studio_attachable/services/import_attachments"
require_relative "../app/services/recording_studio_attachable/services/import_remote_files"
require_relative "../app/services/recording_studio_attachable/services/replace_attachment_file"

class FileSizeLimitTest < Minitest::Test
  CODE_MAX = 10.megabytes
  PLAN_MAX = 5.megabytes
  HIGHER_PLAN = 30.megabytes
  UNDER = 4.megabytes
  OVER_PLAN = 8.megabytes
  OVER_CODE = 12.megabytes
  LIMIT_NAME = :max_file_bytes

  BlobDouble = Struct.new(:id, :byte_size, :content_type, :signed_id, :metadata, :attached, :purged, keyword_init: true) do
    def persisted?
      !id.nil?
    end

    def attachments
      flag = attached
      relation = Object.new
      relation.define_singleton_method(:exists?) { flag }
      relation.define_singleton_method(:blank?) { false }
      relation
    end

    def purge
      self.purged = true
    end

    def signed_id(**)
      self[:signed_id]
    end

    def open
      yield StringIO.new(UploadBlobBytes::PNG)
    end

    def filename
      "photo.png"
    end

    def service_url_for_direct_upload(expires_in:)
      "https://uploads.example.test/#{expires_in}"
    end

    def service_headers_for_direct_upload
      { "Content-Type" => "image/png" }
    end

    def original_url(rails_url:)
      rails_url
    end
  end

  def setup
    ensure_active_storage!
    ensure_attachment_class!
    @configuration = RecordingStudioAttachable.configuration
    @original_limit = @configuration.file_size_limit
    @original_hosts = @configuration.import_allowed_hosts.dup
    @configuration.import_allowed_hosts = ["files.example.test"]
    install_stripe!(ceiling: PLAN_MAX, status: "active")
    @configuration.file_size_limit = LIMIT_NAME
    stub_code_max!(CODE_MAX)
    install_api_errors!
  end

  def teardown
    @configuration.file_size_limit = @original_limit
    @configuration.import_allowed_hosts = @original_hosts
    remove_stripe!
    restore_code_max!
    remove_api_errors!
  end

  def test_under_the_plan_ceiling_is_allowed_on_each_entry_point
    assert_equal UNDER, prepare!(UNDER).byte_size
    assert upload_one(UNDER).success?
    assert upload_many(UNDER).success?
    assert import_attachments(UNDER).success?
    assert import_remote(UNDER).success?
    assert replace_file(UNDER).success?
    assert create_upload(UNDER).fetch(:signed_blob_id).present?
    assert_equal "image", api_attach(UNDER).fetch(:kind)
    assert_equal "image", api_import(UNDER).fetch(:kind)
  end

  def test_over_the_plan_ceiling_is_denied_on_each_entry_point
    assert_plan_denied { prepare!(OVER_PLAN) }
    assert_plan_denied { upload_one(OVER_PLAN) }
    assert_plan_denied { upload_many(OVER_PLAN) }
    assert_plan_denied { import_attachments(OVER_PLAN) }
    assert_plan_denied { import_remote(OVER_PLAN) }
    assert_plan_denied { replace_file(OVER_PLAN) }
    assert_plan_input { create_upload(OVER_PLAN) }
    assert_plan_input { api_attach(OVER_PLAN) }
    assert_plan_input { api_import(OVER_PLAN) }
  end

  def test_plan_ceiling_above_the_code_cap_keeps_the_code_cap
    install_stripe!(ceiling: HIGHER_PLAN, status: "active")

    assert_equal CODE_MAX, RecordingStudioAttachable::FileSizeLimit.effective_max(parent, CODE_MAX)
    assert prepare!(UNDER)
    error = assert_raises(ArgumentError) { prepare!(OVER_CODE) }
    assert_includes error.message, "maximum file size"
    refute_kind_of RecordingStudioStripe::PlanLimitReached, error
  end

  def test_nil_ceiling_uses_the_code_max
    install_stripe!(ceiling: nil, status: "active")

    assert_equal CODE_MAX, RecordingStudioAttachable::FileSizeLimit.effective_max(parent, CODE_MAX)
    assert prepare!(OVER_PLAN)
    error = assert_raises(ArgumentError) { prepare!(OVER_CODE) }
    assert_includes error.message, "maximum file size"
  end

  def test_feature_off_ignores_a_lower_plan_ceiling
    @configuration.file_size_limit = nil

    assert_equal CODE_MAX, RecordingStudioAttachable::FileSizeLimit.effective_max(parent, CODE_MAX)
    assert prepare!(OVER_PLAN)
    error = assert_raises(ArgumentError) { prepare!(OVER_CODE) }
    assert_includes error.message, "maximum file size"
  end

  def test_missing_stripe_constant_ignores_the_setting
    remove_stripe!
    @configuration.file_size_limit = LIMIT_NAME

    refute RecordingStudioAttachable::FileSizeLimit.enabled?
    assert prepare!(OVER_PLAN)
    error = assert_raises(ArgumentError) { prepare!(OVER_CODE) }
    assert_includes error.message, "maximum file size"
  end

  def test_unknown_or_wrong_kind_limit_name_raises
    @configuration.file_size_limit = :missing_limit
    missing = assert_raises(RecordingStudioAttachable::FileSizeLimitUnknown) { prepare!(UNDER) }
    assert_includes missing.message, "missing_limit"

    install_stripe!(ceiling: PLAN_MAX, status: "active", per_item: false)
    @configuration.file_size_limit = LIMIT_NAME
    counted = assert_raises(RecordingStudioAttachable::FileSizeLimitUnknown) { prepare!(UNDER) }
    assert_includes counted.message, "per-item"
  end

  def test_past_due_plan_still_denies_a_file_over_the_ceiling
    install_stripe!(ceiling: PLAN_MAX, status: "past_due")

    assert prepare!(UNDER)
    assert_plan_denied { prepare!(OVER_PLAN) }
    assert_plan_denied { upload_one(OVER_PLAN) }
  end

  def test_uploader_and_picker_show_the_lowered_max
    cap = RecordingStudioAttachable::FileSizeLimit.cap_for(parent, CODE_MAX)
    locals = RecordingStudioAttachable::AttachmentFileButton.configuration_locals(parent)

    assert_equal PLAN_MAX, cap.max_bytes
    assert_equal true, cap.plan_lowered
    assert_equal PLAN_MAX, locals.fetch(:max_file_size)
    assert_equal(
      "This file is too large for your plan.",
      I18n.t("recording_studio.attachable.js.file_exceeds_plan_size")
    )
  end

  def test_attach_over_the_plan_purges_the_unattached_blob
    blob = blob_for(OVER_PLAN)
    assert_plan_denied { upload_one(OVER_PLAN, blob: blob) }
    assert_equal true, blob.purged
  end

  private

  def assert_plan_denied(&)
    error = assert_raises(RecordingStudioStripe::PlanLimitReached, &)
    assert_includes error.message, "plan"
    error
  end

  def assert_plan_input(&)
    error = assert_raises(RecordingStudioApi::InvalidActionInputError, &)
    assert_includes error.message, "plan"
    error
  end

  def prepare!(byte_size)
    created = nil
    ActiveStorage::Blob.stub(:create_before_direct_upload!, lambda { |**|
      created = blob_for(byte_size)
      created
    }) do
      result = RecordingStudioAttachable::DirectUpload.prepare!(
        recording: parent,
        actor: actor,
        filename: "photo.png",
        byte_size: byte_size,
        checksum: "checksum",
        content_type: "image/png"
      )
      assert_same created, result
      result
    end
  end

  def upload_one(byte_size, blob: nil)
    blob ||= blob_for(byte_size)
    with_pipeline(blob) do
      RecordingStudioAttachable::Services::RecordAttachmentUpload.call(
        parent_recording: parent,
        signed_blob_id: blob.signed_id,
        actor: actor,
        name: "Upload"
      )
    end
  end

  def upload_many(byte_size)
    blob = blob_for(byte_size)
    with_pipeline(blob) do
      RecordingStudioAttachable::Services::RecordAttachmentUploads.call(
        parent_recording: parent,
        actor: actor,
        attachments: [{ signed_blob_id: blob.signed_id, name: "Upload" }]
      )
    end
  end

  def import_attachments(byte_size)
    blob = blob_for(byte_size)
    with_pipeline(blob) do
      RecordingStudioAttachable::Services::ImportAttachments.call(
        parent_recording: parent,
        actor: actor,
        attachments: [{ io: StringIO.new(UploadBlobBytes::PNG), filename: "photo.png", content_type: "image/png" }]
      )
    end
  end

  def import_remote(byte_size)
    blob = blob_for(byte_size)
    downloaded = false
    with_pipeline(blob) do
      RecordingStudioAttachable::Services::ImportRemoteFiles.call(
        parent_recording: parent,
        provider_key: :my_cloud,
        actor: actor,
        payloads: [{
          download: lambda {
            downloaded = true
            { io: StringIO.new(UploadBlobBytes::PNG), filename: "photo.png", content_type: "image/png", byte_size: byte_size }
          },
          filename: "photo.png",
          content_type: "image/png",
          byte_size: byte_size
        }]
      )
    end
  ensure
    assert_equal false, downloaded if byte_size > PLAN_MAX && @configuration.file_size_limit.present? && defined?(RecordingStudioStripe)
  end

  def replace_file(byte_size)
    blob = blob_for(byte_size)
    with_pipeline(blob) do
      RecordingStudioAttachable::Services::ReplaceAttachmentFile.call(
        attachment_recording: attachment_recording,
        signed_blob_id: blob.signed_id,
        actor: actor,
        name: "Replacement"
      )
    end
  end

  def create_upload(byte_size)
    ActiveStorage::Blob.stub(:create_before_direct_upload!, blob_for(byte_size)) do
      RecordingStudioAttachable::Api::AttachmentActions::CreateUpload.call(
        api_context(
          filename: "photo.png",
          byte_size: byte_size,
          checksum: "checksum",
          content_type: "image/png"
        )
      )
    end
  end

  def ensure_active_storage!
    ActiveStorage.const_set(:Blob, Class.new) unless defined?(ActiveStorage::Blob)
    blob = ActiveStorage::Blob
    blob.define_singleton_method(:create_before_direct_upload!) { |**| } unless blob.respond_to?(:create_before_direct_upload!)
    blob.define_singleton_method(:create_and_upload!) { |**| } unless blob.respond_to?(:create_and_upload!)
    return if blob.respond_to?(:find_signed!)

    blob.define_singleton_method(:find_signed!) { |*, **| }
  end

  def ensure_attachment_class!
    klass = defined?(RecordingStudioAttachable::Attachment) ? RecordingStudioAttachable::Attachment : nil
    klass ||= RecordingStudioAttachable.const_set(:Attachment, Class.new)
    return if klass.respond_to?(:build_from_blob)

    klass.define_singleton_method(:build_from_blob) { |**| }
  end

  def api_attach(byte_size)
    blob = blob_for(byte_size)
    with_pipeline(blob) do
      RecordingStudioAttachable::Api::AttachmentActions::Attach.call(
        api_context(signed_blob_id: blob.signed_id, name: "Upload")
      )
    end
  end

  def api_import(byte_size)
    blob = blob_for(byte_size)
    RecordingStudioAttachable::SafeRemoteFetch.stub(:call, lambda { |*, max_bytes:|
      raise RecordingStudioAttachable::SafeRemoteFetch::Error, "Remote file exceeds maximum file size" if max_bytes && byte_size > max_bytes

      RecordingStudioAttachable::SafeRemoteFetch::Result.new(
        io: StringIO.new(UploadBlobBytes::PNG),
        content_type: "image/png",
        byte_size: byte_size
      )
    }) do
      with_pipeline(blob) do
        RecordingStudioAttachable::Api::AttachmentActions::ImportAttachment.call(
          api_context(url: "https://files.example.test/photo.png", name: "Photo")
        )
      end
    end
  end

  def with_pipeline(blob, &)
    recorded = Struct.new(:id, :recordable).new("recording-1", attachment_recordable(blob.byte_size))
    RecordingStudioAttachable::Authorization.stub(:authorize!, true) do
      ActiveStorage::Blob.stub(:create_and_upload!, blob) do
        ActiveStorage::Blob.stub(:find_signed!, blob) do
          RecordingStudioAttachable::Attachment.stub(:build_from_blob, attachment_recordable(blob.byte_size)) do
            RecordingStudio.stub(:record!, ->(**) { Struct.new(:recording).new(recorded) }) do
              with_file_route(&)
            end
          end
        end
      end
    end
  end

  def with_file_route
    routes = RecordingStudioAttachable::Engine.routes
    helpers = Object.new
    helpers.define_singleton_method(:attachment_file_path) { |_recording| "/attachments/1/file" }
    original = routes.method(:url_helpers)
    routes.define_singleton_method(:url_helpers) { helpers }
    yield
  ensure
    routes.define_singleton_method(:url_helpers) { original.call }
  end

  def parent
    @parent ||= build_parent
  end

  def build_parent
    test = self
    root = Struct.new(:id).new("root-1")
    root.define_singleton_method(:billing) do
      billing = Object.new
      billing.define_singleton_method(:limit) { |_name| test.instance_variable_get(:@handle) }
      billing
    end
    Struct.new(:id, :recordable_type, :root_recording).new("parent-1", "Workspace", root)
  end

  def attachment_recording
    recordable = attachment_recordable(1)
    Struct.new(:id, :recordable_type, :recordable, :parent_recording, :root_recording, :parent_recording_id).new(
      "attachment-1",
      "RecordingStudioAttachable::Attachment",
      recordable,
      parent,
      parent.root_recording,
      parent.id
    )
  end

  def attachment_recordable(byte_size)
    recordable = Struct.new(:id, :name, :description, :caption, :credit, :alt_text, :attachment_kind, :original_filename, :content_type, :byte_size).new(
      "recordable-1", "Upload", "desc", nil, nil, nil, "image", "photo.png", "image/png", byte_size
    )
    recordable.define_singleton_method(:original_url) { |rails_url:| rails_url }
    recordable
  end

  def actor
    @actor ||= Struct.new(:id).new("actor-1")
  end

  def blob_for(byte_size)
    BlobDouble.new(
      id: "blob-#{byte_size}",
      byte_size: byte_size,
      content_type: "image/png",
      signed_id: "signed-#{byte_size}",
      metadata: RecordingStudioAttachable::DirectUpload.metadata_for(recording: parent, actor: actor),
      attached: false,
      purged: false
    )
  end

  def api_context(params)
    context = Struct.new(:recording, :actor, :params, keyword_init: true)
    context.new(recording: parent, actor: actor, params: params)
  end

  def install_stripe!(ceiling:, status:, per_item: true, no_plan_ceiling: nil)
    remove_stripe!
    stripe = Module.new
    Object.const_set(:RecordingStudioStripe, stripe)
    error_class = Class.new(StandardError)
    plan_class = Class.new(error_class) do
      def initialize(message = "This file is too large for your plan.")
        super
      end
    end
    stripe.const_set(:Error, error_class)
    stripe.const_set(:PlanLimitReached, plan_class)
    definition = Object.new
    definition.define_singleton_method(:per_item?) { per_item }
    limits = Module.new
    limits.define_singleton_method(:known?) { |name| name.to_s == LIMIT_NAME.to_s }
    limits.define_singleton_method(:fetch) do |name|
      raise ArgumentError, "Unknown limit #{name}" unless name.to_s == LIMIT_NAME.to_s

      definition
    end
    stripe.const_set(:Limits, limits)
    @handle = item_handle(ceiling: ceiling, status: status, per_item: per_item, no_plan_ceiling: no_plan_ceiling, plan_class: plan_class)
    @installed_stripe = true
  end

  def item_handle(ceiling:, status:, per_item:, no_plan_ceiling:, plan_class:)
    handle = Object.new
    handle.define_singleton_method(:ceiling) do
      raise ArgumentError, "ceiling is for a per-item ceiling" unless per_item
      return no_plan_ceiling if status.nil? || status == "canceled"
      return ceiling if %w[active trialing past_due].include?(status.to_s)

      nil
    end
    handle.define_singleton_method(:enforce_item!) do |amount|
      raise ArgumentError, "enforce_item! is for a per-item ceiling" unless per_item

      cap = handle.ceiling
      raise plan_class unless cap.nil? || amount <= cap
    end
    handle.define_singleton_method(:per_item?) { per_item }
    handle
  end

  def remove_stripe!
    return unless @installed_stripe && defined?(RecordingStudioStripe)

    Object.send(:remove_const, :RecordingStudioStripe)
    @installed_stripe = false
  end

  def stub_code_max!(bytes)
    @studio = RecordingStudio
    singleton = @studio.singleton_class
    @had_capability_options = singleton.method_defined?(:capability_options)
    @original_capability_options = @studio.method(:capability_options) if @had_capability_options
    singleton.send(:remove_method, :capability_options) if @had_capability_options
    @studio.define_singleton_method(:capability_options) do |_name, _for_type: nil, **|
      { max_file_size: bytes, allowed_content_types: ["image/*"], enabled_attachment_kinds: [:image] }
    end
  end

  def restore_code_max!
    return unless @studio

    singleton = @studio.singleton_class
    singleton.send(:remove_method, :capability_options) if singleton.method_defined?(:capability_options)
    return unless @had_capability_options

    original = @original_capability_options
    @studio.define_singleton_method(:capability_options) { |*args, **kwargs| original.call(*args, **kwargs) }
  end

  def install_api_errors!
    return if defined?(::RecordingStudioApi)

    stub = Module.new
    Object.const_set(:RecordingStudioApi, stub)
    error = Class.new(StandardError)
    stub.const_set(:Error, error)
    invalid = Class.new(error) do
      def initialize(message = "invalid", **)
        super(message)
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
end
