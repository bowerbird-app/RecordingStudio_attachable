# frozen_string_literal: true

require "test_helper"
require_relative "../../app/services/recording_studio_attachable/services/application_service"
require_relative "../../app/services/recording_studio_attachable/services/record_attachment_upload"
require_relative "../../app/services/recording_studio_attachable/services/import_attachment"

class ImportAttachmentTest < Minitest::Test
  FakeRecording = Struct.new(:id, :recordable_type, :root_recording, keyword_init: true)
  FakeBlob = Struct.new(:signed_id, :content_type, :byte_size, :purged, keyword_init: true) do
    def purge
      self.purged = true
    end
  end

  def setup
    @original_configuration = RecordingStudioAttachable.instance_variable_get(:@configuration)
    RecordingStudioAttachable.instance_variable_set(:@configuration, RecordingStudioAttachable::Configuration.new)
    stub_recording_studio!
    stub_accessible!
    stub_active_storage!
  end

  def teardown
    RecordingStudioAttachable.instance_variable_set(:@configuration, @original_configuration)
  end

  def test_import_attachment_creates_blob_and_delegates_to_finalize_service
    parent = FakeRecording.new(id: "parent-1", recordable_type: "Workspace", root_recording: FakeRecording.new(id: "root-1"))
    blob = FakeBlob.new(signed_id: "signed-blob", content_type: "image/svg+xml", byte_size: 512)
    io = StringIO.new("<svg></svg>")
    captured_blob_kwargs = nil
    captured_upload_kwargs = nil
    finalized = RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: :attachment_recording)

    ActiveStorage::Blob.stub(:create_and_upload!, lambda { |**kwargs|
      captured_blob_kwargs = kwargs
      blob
    }) do
      RecordingStudioAttachable::Services::RecordAttachmentUpload.stub(:call, lambda { |**kwargs|
        captured_upload_kwargs = kwargs
        finalized
      }) do
        result = RecordingStudioAttachable::Services::ImportAttachment.call(
          parent_recording: parent,
          io: io,
          filename: "demo-cloud-import.svg",
          content_type: "image/svg+xml",
          actor: :actor,
          identify: false,
          service_name: :mirror,
          source: "demo_cloud",
          metadata: { provider: "demo_cloud" }
        )

        assert result.success?
        assert_equal :attachment_recording, result.value
      end
    end

    assert_equal io, captured_blob_kwargs[:io]
    assert_equal "demo-cloud-import.svg", captured_blob_kwargs[:filename]
    assert_equal "image/svg+xml", captured_blob_kwargs[:content_type]
    assert_equal false, captured_blob_kwargs[:identify]
    assert_equal :mirror, captured_blob_kwargs[:service_name]

    assert_equal parent, captured_upload_kwargs[:parent_recording]
    assert_equal "signed-blob", captured_upload_kwargs[:signed_blob_id]
    assert_equal "demo-cloud-import", captured_upload_kwargs[:name]
    assert_equal :actor, captured_upload_kwargs[:actor]
    assert_equal({ provider: "demo_cloud", source: "demo_cloud" }, captured_upload_kwargs[:metadata])
    assert_not blob.purged
  end

  def test_import_attachment_identifies_content_by_default
    parent = FakeRecording.new(id: "parent-1", recordable_type: "Workspace", root_recording: FakeRecording.new(id: "root-1"))
    blob = FakeBlob.new(signed_id: "signed-blob", content_type: "image/svg+xml", byte_size: 512)
    captured_blob_kwargs = nil
    finalized = RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: :attachment_recording)

    ActiveStorage::Blob.stub(:create_and_upload!, lambda { |**kwargs|
      captured_blob_kwargs = kwargs
      blob
    }) do
      RecordingStudioAttachable::Services::RecordAttachmentUpload.stub(:call, finalized) do
        result = RecordingStudioAttachable::Services::ImportAttachment.call(
          parent_recording: parent,
          io: StringIO.new("<svg></svg>"),
          filename: "demo-cloud-import.svg",
          content_type: "image/svg+xml",
          actor: :actor
        )

        assert result.success?
      end
    end

    assert_equal true, captured_blob_kwargs[:identify]
  end

  def test_import_attachment_rejects_invalid_content_types_and_purges_blob
    parent = FakeRecording.new(id: "parent-1", recordable_type: "Workspace", root_recording: FakeRecording.new(id: "root-1"))
    blob = FakeBlob.new(signed_id: "signed-blob", content_type: "text/plain", byte_size: 64)

    ActiveStorage::Blob.stub(:create_and_upload!, blob) do
      result = RecordingStudioAttachable::Services::ImportAttachment.call(
        parent_recording: parent,
        io: StringIO.new("hello"),
        filename: "notes.txt",
        content_type: "text/plain",
        actor: :actor
      )

      assert result.failure?
      assert_includes result.error, "is not allowed"
      assert blob.purged
    end
  end

  def test_import_attachment_purges_blob_when_finalize_service_fails
    parent = FakeRecording.new(id: "parent-1", recordable_type: "Workspace", root_recording: FakeRecording.new(id: "root-1"))
    blob = FakeBlob.new(signed_id: "signed-blob", content_type: "image/svg+xml", byte_size: 64)
    failed = RecordingStudioAttachable::Services::BaseService::Result.new(success: false, error: "could not finalize")

    ActiveStorage::Blob.stub(:create_and_upload!, blob) do
      RecordingStudioAttachable::Services::RecordAttachmentUpload.stub(:call, failed) do
        result = RecordingStudioAttachable::Services::ImportAttachment.call(
          parent_recording: parent,
          io: StringIO.new("<svg></svg>"),
          filename: "demo.svg",
          content_type: "image/svg+xml",
          actor: :actor
        )

        assert result.failure?
        assert_equal "could not finalize", result.error
        assert blob.purged
      end
    end
  end

  private

  def stub_recording_studio!
    studio = defined?(RecordingStudio) ? RecordingStudio : Object.const_set(:RecordingStudio, Module.new)
    configuration = Class.new do
      def capability_enabled?(*)
        true
      end
    end.new
    studio.instance_variable_set(:@test_configuration, configuration)
    studio.singleton_class.send(:remove_method, :capability_options) if studio.singleton_class.method_defined?(:capability_options)
    studio.singleton_class.send(:remove_method, :configuration) if studio.singleton_class.method_defined?(:configuration)
    studio.define_singleton_method(:capability_options) { |_name, _for_type: nil, **| {} }
    studio.define_singleton_method(:configuration) { @test_configuration }
  end

  def stub_accessible!
    Object.const_set(:RecordingStudioAccessible, Module.new) unless defined?(RecordingStudioAccessible)
    accessible =
      if defined?(RecordingStudioAccessible::Authorization)
        RecordingStudioAccessible::Authorization
      else
        RecordingStudioAccessible.const_set(:Authorization, Module.new)
      end
    accessible.singleton_class.send(:remove_method, :allowed?) if accessible.singleton_class.method_defined?(:allowed?)
    accessible.define_singleton_method(:allowed?) { |actor:, recording:, role:| actor.present? && recording.present? && role.present? }
  end

  def stub_active_storage!
    unless defined?(ActiveStorage::Blob)
      blob_class = Class.new
      Object.const_set(:ActiveStorage, Module.new) unless defined?(ActiveStorage)
      ActiveStorage.const_set(:Blob, blob_class)
    end

    unless ActiveStorage::Blob.respond_to?(:create_and_upload!)
      ActiveStorage::Blob.define_singleton_method(:create_and_upload!) do |*, **|
        raise NotImplementedError
      end
    end

    return if ActiveStorage::Blob.respond_to?(:find_signed!)

    ActiveStorage::Blob.define_singleton_method(:find_signed!) do |*|
      raise NotImplementedError
    end
  end
end
