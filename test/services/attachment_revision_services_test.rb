# frozen_string_literal: true

require "test_helper"
require_relative "../../app/services/recording_studio_attachable/services/application_service"
require_relative "../../app/services/recording_studio_attachable/services/replace_attachment_file"
require_relative "../../app/services/recording_studio_attachable/services/revise_attachment_metadata"
require_relative "../../app/services/recording_studio_attachable/services/restore_attachment"

class AttachmentRevisionServicesTest < Minitest::Test
  RecordingDouble = Struct.new(:id, :recordable_type, :root_recording, keyword_init: true)
  FakeEvent = Struct.new(:recording)
  BlobDouble = Struct.new(:content_type, :byte_size, :filename)
  FilenameDouble = Struct.new(:value) do
    def to_s
      value
    end

    def base
      File.basename(value, File.extname(value))
    end
  end
  FileDouble = Struct.new(:blob)
  AttachmentDouble = Struct.new(
    :id,
    :name,
    :description,
    :attachment_kind,
    :original_filename,
    :content_type,
    :byte_size,
    :file,
    keyword_init: true
  )

  class AttachmentRecordingDouble
    attr_reader :id, :recordable_type, :parent_recording, :parent_recording_id, :recordable, :root_recording, :events,
                :restored_with

    def initialize(id:, parent_recording:, recordable:, root_recording: nil, trashable: false)
      @id = id
      @recordable_type = "RecordingStudioAttachable::Attachment"
      @parent_recording = parent_recording
      @parent_recording_id = parent_recording.id
      @recordable = recordable
      @root_recording = root_recording
      @events = []

      return unless trashable

      define_singleton_method(:recording_studio_trashable_restore!) do |actor:, impersonator:|
        @restored_with = [actor, impersonator]
      end
    end

    def log_event!(**kwargs)
      @events << kwargs
    end
  end

  def setup
    @original_configuration = RecordingStudioAttachable.instance_variable_get(:@configuration)
    RecordingStudioAttachable.instance_variable_set(:@configuration, RecordingStudioAttachable::Configuration.new)
    stub_recording_studio!
    stub_attachment_class!
    stub_active_storage!
  end

  def teardown
    RecordingStudioAttachable.instance_variable_set(:@configuration, @original_configuration)
  end

  def test_replace_attachment_file_records_replacement_event
    parent = RecordingDouble.new(id: "parent-1", recordable_type: "Workspace")
    root = RecordingDouble.new(id: "root-1", recordable_type: "Workspace")
    current_attachment = AttachmentDouble.new(
      id: "attachment-old",
      name: "Old name",
      description: "Old description",
      attachment_kind: "image",
      original_filename: "old.png",
      content_type: "image/png",
      byte_size: 1024,
      file: nil
    )
    attachment_recording = AttachmentRecordingDouble.new(
      id: "recording-1",
      parent_recording: parent,
      recordable: current_attachment,
      root_recording: root
    )
    replacement = AttachmentDouble.new(
      id: "attachment-new",
      name: "Old name",
      description: "New description",
      attachment_kind: "image",
      original_filename: "new.png",
      content_type: "image/png",
      byte_size: 2048,
      file: nil
    )
    blob = BlobDouble.new("image/png", 2048, FilenameDouble.new("new.png"))
    created_recording = Struct.new(:id).new("recording-1")
    captured_build_kwargs = nil
    captured_event_kwargs = nil

    ActiveStorage::Blob.stub(:find_signed!, blob) do
      RecordingStudioAttachable::Attachment.stub(:build_from_blob, lambda { |**kwargs|
        captured_build_kwargs = kwargs
        replacement
      }) do
        RecordingStudioAttachable::Authorization.stub(:authorize!, true) do
          RecordingStudio.stub(:record!, lambda { |**kwargs|
            captured_event_kwargs = kwargs
            FakeEvent.new(created_recording)
          }) do
            result = RecordingStudioAttachable::Services::ReplaceAttachmentFile.call(
              attachment_recording: attachment_recording,
              signed_blob_id: "signed-blob",
              actor: :actor,
              impersonator: :impersonator,
              description: "New description",
              metadata: { batch_id: "batch-1" }
            )

            assert result.success?
            assert_equal created_recording, result.value
          end
        end
      end
    end

    assert_equal blob, captured_build_kwargs[:blob]
    assert_equal "Old name", captured_build_kwargs[:name]
    assert_equal "New description", captured_build_kwargs[:description]
    assert_equal(
      {
        action: "attachment_file_replaced",
        actor: :actor,
        impersonator: :impersonator
      },
      captured_event_kwargs.slice(:action, :actor, :impersonator)
    )
    assert_equal replacement, captured_event_kwargs[:recordable]
    assert_equal attachment_recording, captured_event_kwargs[:recording]
    assert_equal root, captured_event_kwargs[:root_recording]
    assert_equal(
      {
        attachment_recording_id: "recording-1",
        parent_recording_id: "parent-1",
        root_recording_id: "root-1",
        attachment_recordable_id: "attachment-new",
        previous_attachment_recordable_id: "attachment-old",
        attachment_kind: "image",
        name: "Old name",
        original_filename: "new.png",
        content_type: "image/png",
        byte_size: 2048,
        batch_id: "batch-1",
        source: "file_replacement"
      },
      captured_event_kwargs[:metadata]
    )
  end

  def test_revise_attachment_metadata_records_revision_event
    parent = RecordingDouble.new(id: "parent-1", recordable_type: "Workspace")
    root = RecordingDouble.new(id: "root-1", recordable_type: "Workspace")
    blob = BlobDouble.new("image/png", 1024, FilenameDouble.new("existing.png"))
    current_attachment = AttachmentDouble.new(
      id: "attachment-old",
      name: "Old name",
      description: "Old description",
      attachment_kind: "image",
      original_filename: "existing.png",
      content_type: "image/png",
      byte_size: 1024,
      file: FileDouble.new(blob)
    )
    attachment_recording = AttachmentRecordingDouble.new(
      id: "recording-2",
      parent_recording: parent,
      recordable: current_attachment,
      root_recording: root
    )
    revised_attachment = AttachmentDouble.new(
      id: "attachment-new",
      name: "Renamed",
      description: "Old description",
      attachment_kind: "image",
      original_filename: "existing.png",
      content_type: "image/png",
      byte_size: 1024,
      file: nil
    )
    created_recording = Struct.new(:id).new("recording-2")
    captured_build_kwargs = nil
    captured_event_kwargs = nil

    RecordingStudio.stub(:capability_options, { allowed_content_types: ["image/*"], enabled_attachment_kinds: %i[image] }) do
      RecordingStudioAttachable::Attachment.stub(:build_from_blob, lambda { |**kwargs|
        captured_build_kwargs = kwargs
        revised_attachment
      }) do
        RecordingStudioAttachable::Authorization.stub(:authorize!, true) do
          RecordingStudio.stub(:record!, lambda { |**kwargs|
            captured_event_kwargs = kwargs
            FakeEvent.new(created_recording)
          }) do
            result = RecordingStudioAttachable::Services::ReviseAttachmentMetadata.call(
              attachment_recording: attachment_recording,
              actor: :actor,
              name: "Renamed",
              metadata: { source_system: "ui" }
            )

            assert result.success?
            assert_equal created_recording, result.value
          end
        end
      end
    end

    assert_equal blob, captured_build_kwargs[:blob]
    assert_equal "Renamed", captured_build_kwargs[:name]
    assert_equal "Old description", captured_build_kwargs[:description]
    assert_equal(
      { allowed_content_types: ["image/*"], enabled_attachment_kinds: %i[image] },
      captured_build_kwargs[:validation_options]
    )
    assert_equal "attachment_metadata_revised", captured_event_kwargs[:action]
    assert_equal revised_attachment, captured_event_kwargs[:recordable]
    assert_equal(
      {
        attachment_recording_id: "recording-2",
        parent_recording_id: "parent-1",
        root_recording_id: "root-1",
        attachment_recordable_id: "attachment-new",
        previous_attachment_recordable_id: "attachment-old",
        attachment_kind: "image",
        name: "Renamed",
        original_filename: "existing.png",
        content_type: "image/png",
        byte_size: 1024,
        source: "metadata_revision"
      },
      captured_event_kwargs[:metadata]
    )
  end

  def test_restore_attachment_restores_and_logs_event
    parent = RecordingDouble.new(id: "parent-1", recordable_type: "Workspace")
    root = RecordingDouble.new(id: "root-1", recordable_type: "Workspace")
    attachment = AttachmentDouble.new(
      id: "attachment-restore",
      name: "Restorable",
      description: "Recoverable",
      attachment_kind: "file",
      original_filename: "restore.txt",
      content_type: "text/plain",
      byte_size: 256,
      file: nil
    )
    attachment_recording = AttachmentRecordingDouble.new(
      id: "recording-3",
      parent_recording: parent,
      recordable: attachment,
      root_recording: root,
      trashable: true
    )

    result = with_authorized_access do
      RecordingStudioAttachable::Services::RestoreAttachment.call(
        attachment_recording: attachment_recording,
        actor: :actor,
        impersonator: :impersonator,
        metadata: { batch_id: "batch-restore" }
      )
    end

    assert result.success?
    assert_equal attachment_recording, result.value
    assert_equal %i[actor impersonator], attachment_recording.restored_with
    assert_equal 1, attachment_recording.events.length
    assert_equal(
      {
        attachment_recording_id: "recording-3",
        parent_recording_id: "parent-1",
        root_recording_id: "root-1",
        attachment_recordable_id: "attachment-restore",
        attachment_kind: "file",
        name: "Restorable",
        original_filename: "restore.txt",
        content_type: "text/plain",
        byte_size: 256,
        batch_id: "batch-restore",
        source: "restore"
      },
      attachment_recording.events.first[:metadata]
    )
  end

  def test_restore_attachment_requires_trashable_support
    parent = RecordingDouble.new(id: "parent-1", recordable_type: "Workspace")
    attachment = AttachmentDouble.new(
      id: "attachment-restore",
      name: "Restorable",
      description: "Recoverable",
      attachment_kind: "file",
      original_filename: "restore.txt",
      content_type: "text/plain",
      byte_size: 256,
      file: nil
    )
    attachment_recording = AttachmentRecordingDouble.new(
      id: "recording-4",
      parent_recording: parent,
      recordable: attachment,
      trashable: false
    )

    result = RecordingStudioAttachable::Services::RestoreAttachment.call(
      attachment_recording: attachment_recording,
      actor: :actor
    )

    assert result.failure?
    assert_equal "Restore requires RecordingStudio Trashable", result.error
  end

  private

  def with_authorized_access(&block)
    RecordingStudioAttachable::Authorization.stub(:authorize!, true) do
      block.call
    end
  end

  def stub_recording_studio!
    studio = defined?(RecordingStudio) ? RecordingStudio : Object.const_set(:RecordingStudio, Module.new)
    studio.singleton_class.send(:remove_method, :capability_options) if studio.singleton_class.method_defined?(:capability_options)
    studio.singleton_class.send(:remove_method, :record!) if studio.singleton_class.method_defined?(:record!)
    studio.define_singleton_method(:capability_options) { |_name, _for_type: nil, **| {} }
    studio.define_singleton_method(:record!) { |**| raise NotImplementedError }
  end

  def stub_attachment_class!
    klass =
      if defined?(RecordingStudioAttachable::Attachment)
        RecordingStudioAttachable::Attachment
      else
        RecordingStudioAttachable.const_set(:Attachment, Class.new)
      end

    return if klass.respond_to?(:build_from_blob)

    klass.define_singleton_method(:build_from_blob) do |*|
      raise NotImplementedError
    end
  end

  def stub_active_storage!
    return if defined?(ActiveStorage::Blob)

    Object.const_set(:ActiveStorage, Module.new) unless defined?(ActiveStorage)
    ActiveStorage.const_set(:Blob, Class.new)
    ActiveStorage::Blob.define_singleton_method(:find_signed!) do |*|
      raise NotImplementedError
    end
  end
end
