# frozen_string_literal: true

require "test_helper"
require_relative "../../app/services/recording_studio_attachable/services/application_service"
require_relative "../../app/services/recording_studio_attachable/services/import_attachment"
require_relative "../../app/services/recording_studio_attachable/services/import_attachments"

class ImportAttachmentsTest < Minitest::Test
  FakeRecording = Struct.new(:id, :recordable_type, :root_recording, keyword_init: true)
  FakeBlob = Struct.new(:signed_id, :content_type, :byte_size, :id, :purged, keyword_init: true) do
    def purge
      self.purged = true
    end
  end

  FakeFile = Struct.new(:blob, keyword_init: true)
  FakeAttachment = Struct.new(:file, keyword_init: true)
  FakeCreatedRecording = Struct.new(:recordable, keyword_init: true)

  def setup
    @original_configuration = RecordingStudioAttachable.instance_variable_get(:@configuration)
    RecordingStudioAttachable.instance_variable_set(:@configuration, RecordingStudioAttachable::Configuration.new)
    stub_recording_studio!
  end

  def teardown
    RecordingStudioAttachable.instance_variable_set(:@configuration, @original_configuration)
  end

  def test_import_attachments_batches_imports_and_merges_batch_metadata
    parent = FakeRecording.new(id: "parent-1", recordable_type: "Workspace", root_recording: FakeRecording.new(id: "root-1"))
    attachments = [
      { io: StringIO.new("<svg>1</svg>"), filename: "one.svg", content_type: "image/svg+xml", metadata: { provider: "demo_cloud" } },
      { io: StringIO.new("<svg>2</svg>"), filename: "two.svg", content_type: "image/svg+xml", source: "dropbox" }
    ]
    captured_uploads = []
    captured_creates = []
    blobs = [
      FakeBlob.new(signed_id: "signed-one", content_type: "image/svg+xml", byte_size: 12, id: "blob-one", purged: false),
      FakeBlob.new(signed_id: "signed-two", content_type: "image/svg+xml", byte_size: 18, id: "blob-two", purged: false)
    ]

    ActiveStorage::Blob.stub(:create_and_upload!, lambda { |**kwargs|
      captured_creates << kwargs
      blobs[captured_creates.length - 1]
    }) do
      RecordingStudioAttachable::Services::RecordAttachmentUpload.stub(:call, lambda { |**kwargs|
        captured_uploads << kwargs
        RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: kwargs[:name])
      }) do
        SecureRandom.stub(:uuid, "batch-1") do
          result = RecordingStudioAttachable::Services::ImportAttachments.call(
            parent_recording: parent,
            attachments: attachments,
            actor: :actor,
            source: "demo_cloud"
          )

          assert result.success?
          assert_equal %w[one two], result.value
        end
      end
    end

    assert_equal 2, captured_uploads.length
    assert_equal({ provider: "demo_cloud", source: "demo_cloud", batch_id: "batch-1" }, captured_uploads.first[:metadata])
    assert_equal "signed-one", captured_uploads.first[:signed_blob_id]
    assert_equal({ source: "dropbox", batch_id: "batch-1" }, captured_uploads.last[:metadata])
    assert_equal "dropbox", captured_uploads.last[:metadata][:source]
    assert_equal true, captured_creates.first[:identify]
    assert_equal true, captured_creates.last[:identify]
    assert_equal "one.svg", captured_creates.first[:filename]
    assert_equal "two.svg", captured_creates.last[:filename]
  end

  def test_import_attachments_rejects_batches_larger_than_the_configured_limit
    parent = FakeRecording.new(id: "parent-1", recordable_type: "Workspace", root_recording: FakeRecording.new(id: "root-1"))
    attachments = [
      { io: StringIO.new("1"), filename: "one.svg", content_type: "image/svg+xml" },
      { io: StringIO.new("2"), filename: "two.svg", content_type: "image/svg+xml" }
    ]

    RecordingStudio.stub(:capability_options, { max_file_count: 1 }) do
      result = RecordingStudioAttachable::Services::ImportAttachments.call(parent_recording: parent, attachments: attachments)

      assert result.failure?
      assert_equal "You can import up to 1 file at a time", result.error
    end
  end

  def test_import_attachments_purges_previously_created_blobs_when_a_later_item_fails
    parent = FakeRecording.new(id: "parent-1", recordable_type: "Workspace", root_recording: FakeRecording.new(id: "root-1"))
    first_blob = FakeBlob.new(signed_id: "signed-one", content_type: "image/svg+xml", byte_size: 12, id: "blob-one", purged: false)
    second_blob = FakeBlob.new(signed_id: "signed-two", content_type: "image/svg+xml", byte_size: 18, id: "blob-two", purged: false)
    first_created = FakeCreatedRecording.new(recordable: FakeAttachment.new(file: FakeFile.new(blob: first_blob)))
    success_result = RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: first_created)
    failure_result = RecordingStudioAttachable::Services::BaseService::Result.new(success: false, error: "bad file")
    created = []

    ActiveStorage::Blob.stub(:create_and_upload!, lambda { |**|
      blob = created.empty? ? first_blob : second_blob
      created << blob
      blob
    }) do
      RecordingStudioAttachable::Services::RecordAttachmentUpload.stub(:call, lambda { |**kwargs|
        kwargs[:signed_blob_id] == "signed-one" ? success_result : failure_result
      }) do
        result = RecordingStudioAttachable::Services::ImportAttachments.call(
          parent_recording: parent,
          attachments: [
            { io: StringIO.new("1"), filename: "one.svg", content_type: "image/svg+xml" },
            { io: StringIO.new("2"), filename: "two.svg", content_type: "image/svg+xml" }
          ]
        )

        assert result.failure?
        assert_equal 'Failed to import "two.svg": bad file', result.error
        assert_equal [{ filename: "two.svg", content_type: "image/svg+xml", error: "bad file" }], result.errors
      end
    end

    assert first_blob.purged
    assert second_blob.purged
  end

  def test_import_attachments_uses_underlying_error_when_attachment_label_is_missing
    parent = FakeRecording.new(id: "parent-1", recordable_type: "Workspace", root_recording: FakeRecording.new(id: "root-1"))
    failure_result = RecordingStudioAttachable::Services::BaseService::Result.new(success: false, error: "bad file")
    blob = FakeBlob.new(signed_id: "signed-blank", content_type: "image/svg+xml", byte_size: 4, id: "blob-blank", purged: false)

    ActiveStorage::Blob.stub(:create_and_upload!, blob) do
      RecordingStudioAttachable::Services::RecordAttachmentUpload.stub(:call, failure_result) do
        result = RecordingStudioAttachable::Services::ImportAttachments.call(
          parent_recording: parent,
          attachments: [
            { io: StringIO.new("1"), filename: "", content_type: "image/svg+xml" }
          ]
        )

        assert result.failure?
        assert_equal "bad file", result.error
      end
    end

    assert blob.purged
  end

  private

  def stub_recording_studio!
    studio = defined?(RecordingStudio) ? RecordingStudio : Object.const_set(:RecordingStudio, Module.new)
    studio.singleton_class.send(:remove_method, :capability_options) if studio.singleton_class.method_defined?(:capability_options)
    studio.define_singleton_method(:capability_options) { |_name, _for_type: nil, **| {} }
  end
end
