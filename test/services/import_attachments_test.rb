# frozen_string_literal: true

require "test_helper"
require_relative "../../app/services/recording_studio_attachable/services/application_service"
require_relative "../../app/services/recording_studio_attachable/services/import_attachment"
require_relative "../../app/services/recording_studio_attachable/services/import_attachments"

class ImportAttachmentsTest < Minitest::Test
  FakeRecording = Struct.new(:id, :recordable_type, :root_recording, keyword_init: true)
  FakeBlob = Struct.new(:purged, keyword_init: true) do
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
    captured_calls = []

    RecordingStudioAttachable::Services::ImportAttachment.stub(:call, lambda { |**kwargs|
      captured_calls << kwargs
      RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: kwargs[:filename])
    }) do
      SecureRandom.stub(:uuid, "batch-1") do
        result = RecordingStudioAttachable::Services::ImportAttachments.call(
          parent_recording: parent,
          attachments: attachments,
          actor: :actor,
          source: "demo_cloud"
        )

        assert result.success?
        assert_equal %w[one.svg two.svg], result.value
      end
    end

    assert_equal 2, captured_calls.length
    assert_equal({ provider: "demo_cloud", batch_id: "batch-1" }, captured_calls.first[:metadata])
    assert_equal "demo_cloud", captured_calls.first[:source]
    assert_equal({ batch_id: "batch-1" }, captured_calls.last[:metadata])
    assert_equal "dropbox", captured_calls.last[:source]
    assert_equal true, captured_calls.first[:identify]
    assert_equal true, captured_calls.last[:identify]
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
    first_blob = FakeBlob.new(purged: false)
    first_created = FakeCreatedRecording.new(recordable: FakeAttachment.new(file: FakeFile.new(blob: first_blob)))
    success_result = RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: first_created)
    failure_result = RecordingStudioAttachable::Services::BaseService::Result.new(success: false, error: "bad file")
    calls = 0

    RecordingStudioAttachable::Services::ImportAttachment.stub(:call, lambda { |**|
      calls += 1
      calls == 1 ? success_result : failure_result
    }) do
      result = RecordingStudioAttachable::Services::ImportAttachments.call(
        parent_recording: parent,
        attachments: [
          { io: StringIO.new("1"), filename: "one.svg", content_type: "image/svg+xml" },
          { io: StringIO.new("2"), filename: "two.svg", content_type: "image/svg+xml" }
        ]
      )

      assert result.failure?
      assert_equal "One or more attachments failed to import", result.error
    end

    assert first_blob.purged
  end

  private

  def stub_recording_studio!
    studio = defined?(RecordingStudio) ? RecordingStudio : Object.const_set(:RecordingStudio, Module.new)
    studio.singleton_class.send(:remove_method, :capability_options) if studio.singleton_class.method_defined?(:capability_options)
    studio.define_singleton_method(:capability_options) { |_name, _for_type: nil, **| {} }
  end
end
