# frozen_string_literal: true

require "test_helper"
require_relative "../app/queries/recording_studio_attachable/queries/for_recording"
require_relative "../app/services/recording_studio_attachable/services/application_service"
require_relative "../app/services/recording_studio_attachable/services/record_attachment_upload"
require_relative "../app/services/recording_studio_attachable/services/record_attachment_uploads"
require_relative "../app/services/recording_studio_attachable/services/import_attachment"
require_relative "../app/services/recording_studio_attachable/services/import_attachments"
require_relative "../app/services/recording_studio_attachable/services/revise_attachment_metadata"
require_relative "../app/services/recording_studio_attachable/services/replace_attachment_file"
require_relative "../app/services/recording_studio_attachable/services/remove_attachment"
require_relative "../app/services/recording_studio_attachable/services/remove_attachments"
require_relative "../app/services/recording_studio_attachable/services/restore_attachment"

class RecordingMethodsTest < Minitest::Test
  class FakeRecording
    include RecordingStudio::Capabilities::Attachable::RecordingMethods

    attr_reader :recordable_type, :parent_recording, :capability_assertions

    def initialize(recordable_type = "Workspace", parent_recording: nil)
      @recordable_type = recordable_type
      @parent_recording = parent_recording
      @capability_assertions = []
    end

    private

    def assert_capability!(*args, **kwargs)
      @capability_assertions << [args, kwargs]
    end
  end

  def test_attachments_delegates_search_and_pagination_to_the_query
    recording = FakeRecording.new
    fake_query = Minitest::Mock.new
    fake_query.expect(:call, [:attachments])
    captured_kwargs = nil

    RecordingStudioAttachable::Queries::ForRecording.stub(:new, lambda { |**kwargs|
      captured_kwargs = kwargs
      fake_query
    }) do
      result = recording.attachments(search: "brief", page: 3, per_page: 12, scope: :subtree, kind: :files)

      assert_equal [:attachments], result
    end

    fake_query.verify
    assert_equal recording, captured_kwargs[:recording]
    assert_equal "brief", captured_kwargs[:search]
    assert_equal 3, captured_kwargs[:page]
    assert_equal 12, captured_kwargs[:per_page]
    assert_equal :subtree, captured_kwargs[:scope]
    assert_equal :files, captured_kwargs[:kind]
  end

  def test_remove_attachments_delegates_to_bulk_remove_service
    recording = FakeRecording.new
    result = RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: [:removed])
    captured_kwargs = nil

    RecordingStudioAttachable::Services::RemoveAttachments.stub(:call, lambda { |**kwargs|
      captured_kwargs = kwargs
      result
    }) do
      assert_equal [:removed], recording.remove_attachments(attachment_ids: ["att-1"], actor: :user)
    end

    assert_equal recording, captured_kwargs[:parent_recording]
    assert_equal ["att-1"], captured_kwargs[:attachment_ids]
    assert_equal :user, captured_kwargs[:actor]
  end

  def test_images_and_files_delegate_to_attachments_with_expected_filters
    recording = FakeRecording.new
    calls = []
    recording.define_singleton_method(:attachments) do |**kwargs|
      calls << kwargs
      :delegated
    end

    assert_equal :delegated, recording.images(scope: :subtree, include_trashed: true, search: "photo", page: 2, per_page: 4)
    assert_equal :delegated, recording.files(scope: :direct, search: "notes", page: 1, per_page: 8)

    assert_equal(
      {
        scope: :subtree,
        kind: :images,
        include_trashed: true,
        search: "photo",
        page: 2,
        per_page: 4
      },
      calls.first
    )
    assert_equal(
      {
        scope: :direct,
        kind: :files,
        include_trashed: false,
        search: "notes",
        page: 1,
        per_page: 8
      },
      calls.last
    )
  end

  def test_has_attachments_uses_relation_existence_check
    relation = Struct.new(:value) do
      def exists?
        value
      end
    end
    recording = FakeRecording.new
    recording.define_singleton_method(:attachments) { |**| relation.new(true) }

    assert recording.has_attachments?(scope: :subtree, kind: :images, include_trashed: true)
  end

  def test_recording_level_methods_delegate_to_services
    recording = FakeRecording.new
    assertions = [
      [
        :record_attachment_upload,
        RecordingStudioAttachable::Services::RecordAttachmentUpload,
        { signed_blob_id: "blob-1" },
        { parent_recording: recording, signed_blob_id: "blob-1" }
      ],
      [
        :record_attachment_uploads,
        RecordingStudioAttachable::Services::RecordAttachmentUploads,
        { signed_blob_ids: ["blob-1"] },
        { parent_recording: recording, signed_blob_ids: ["blob-1"] }
      ],
      [
        :remove_attachments,
        RecordingStudioAttachable::Services::RemoveAttachments,
        { attachment_ids: ["att-1"] },
        { parent_recording: recording, attachment_ids: ["att-1"] }
      ]
    ]

    assertions.each do |method_name, service_class, options, expected_kwargs|
      result = RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: method_name)
      captured_kwargs = nil

      service_class.stub(:call, lambda { |**kwargs|
        captured_kwargs = kwargs
        result
      }) do
        assert_equal method_name, recording.public_send(method_name, **options)
      end

      assert_equal expected_kwargs, captured_kwargs
    end
  end

  def test_import_attachment_delegates_to_import_service
    recording = FakeRecording.new
    io = StringIO.new("<svg></svg>")
    result = RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: :imported)
    captured_kwargs = nil

    RecordingStudioAttachable::Services::ImportAttachment.stub(:call, lambda { |**kwargs|
      captured_kwargs = kwargs
      result
    }) do
      assert_equal :imported, recording.import_attachment(io: io, filename: "demo.svg", content_type: "image/svg+xml")
    end

    assert_equal recording, captured_kwargs[:parent_recording]
    assert_equal io, captured_kwargs[:io]
    assert_equal "demo.svg", captured_kwargs[:filename]
    assert_equal "image/svg+xml", captured_kwargs[:content_type]
  end

  def test_import_attachments_delegates_to_batch_import_service
    recording = FakeRecording.new
    attachments = [{ filename: "demo.svg", content_type: "image/svg+xml" }]
    result = RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: :imported_batch)
    captured_kwargs = nil

    RecordingStudioAttachable::Services::ImportAttachments.stub(:call, lambda { |**kwargs|
      captured_kwargs = kwargs
      result
    }) do
      assert_equal :imported_batch, recording.import_attachments(attachments: attachments)
    end

    assert_equal recording, captured_kwargs[:parent_recording]
    assert_equal attachments, captured_kwargs[:attachments]
  end

  def test_attachment_recording_methods_delegate_to_services
    recording = FakeRecording.new("RecordingStudioAttachable::Attachment")
    assertions = [
      [
        :revise_attachment_metadata,
        RecordingStudioAttachable::Services::ReviseAttachmentMetadata,
        { name: "Updated" },
        { attachment_recording: recording, name: "Updated" }
      ],
      [
        :replace_attachment_file,
        RecordingStudioAttachable::Services::ReplaceAttachmentFile,
        { signed_blob_id: "blob-2" },
        { attachment_recording: recording, signed_blob_id: "blob-2" }
      ],
      [
        :remove_attachment,
        RecordingStudioAttachable::Services::RemoveAttachment,
        { actor: :user },
        { attachment_recording: recording, actor: :user }
      ],
      [
        :restore_attachment,
        RecordingStudioAttachable::Services::RestoreAttachment,
        { actor: :user },
        { attachment_recording: recording, actor: :user }
      ]
    ]

    assertions.each do |method_name, service_class, options, expected_kwargs|
      result = RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: method_name)
      captured_kwargs = nil

      service_class.stub(:call, lambda { |**kwargs|
        captured_kwargs = kwargs
        result
      }) do
        assert_equal method_name, recording.public_send(method_name, **options)
      end

      assert_equal expected_kwargs, captured_kwargs
    end
  end

  def test_attachment_only_methods_raise_for_non_attachment_recordings
    recording = FakeRecording.new("Workspace")

    %i[revise_attachment_metadata replace_attachment_file remove_attachment restore_attachment].each do |method_name|
      error = assert_raises(ArgumentError) do
        recording.public_send(method_name)
      end

      assert_equal "Recording is not an attachment", error.message
    end
  end

  def test_attachment_recordings_assert_capability_with_parent_recording_type
    parent_recording = FakeRecording.new("Workspace")
    recording = FakeRecording.new("RecordingStudioAttachable::Attachment", parent_recording: parent_recording)
    fake_query = Minitest::Mock.new
    fake_query.expect(:call, [:attachments])

    RecordingStudioAttachable::Queries::ForRecording.stub(:new, lambda { |**|
      fake_query
    }) do
      recording.attachments
    end

    fake_query.verify
    assert_equal [[[:attachable], { for_type: "Workspace" }]], recording.capability_assertions
  end
end
