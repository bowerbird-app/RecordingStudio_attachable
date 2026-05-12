# frozen_string_literal: true

require "test_helper"
require_relative "../../app/services/recording_studio_attachable/services/application_service"
require_relative "../../app/services/recording_studio_attachable/services/remove_attachment"

class RemoveAttachmentTest < Minitest::Test
  AttachmentDouble = Struct.new(
    :id,
    :attachment_kind,
    :name,
    :original_filename,
    :content_type,
    :byte_size,
    keyword_init: true
  )

  class TrashableAttachmentRecording
    attr_reader :id, :recordable_type, :parent_recording, :parent_recording_id, :recordable, :root_recording, :events,
                :trashed_with

    def initialize(id:, parent_recording:, recordable:, root_recording: nil)
      @id = id
      @recordable_type = "RecordingStudioAttachable::Attachment"
      @parent_recording = parent_recording
      @parent_recording_id = parent_recording.id
      @recordable = recordable
      @root_recording = root_recording
      @events = []
    end

    def log_event!(**kwargs)
      @events << kwargs
    end

    def recording_studio_trashable_trash!(actor:, impersonator:)
      @trashed_with = [actor, impersonator]
    end
  end

  class DestroyOnlyAttachmentRecording
    attr_reader :id, :recordable_type, :parent_recording, :parent_recording_id, :recordable, :root_recording
    attr_accessor :destroyed

    def initialize(id:, parent_recording:, recordable:)
      @id = id
      @recordable_type = "RecordingStudioAttachable::Attachment"
      @parent_recording = parent_recording
      @parent_recording_id = parent_recording.id
      @recordable = recordable
      @root_recording = nil
      @destroyed = false
    end

    def destroy!
      self.destroyed = true
    end
  end

  RecordingDouble = Struct.new(:id, :recordable_type, :root_recording, keyword_init: true)

  def setup
    stub_recording_studio!
  end

  def test_trashable_attachments_log_an_event_and_trash_the_recording
    parent = RecordingDouble.new(id: "parent-1", recordable_type: "Workspace")
    root = RecordingDouble.new(id: "root-1", recordable_type: "Workspace")
    attachment = AttachmentDouble.new(
      id: "attachment-1",
      attachment_kind: "image",
      name: "Photo",
      original_filename: "photo.png",
      content_type: "image/png",
      byte_size: 1024
    )
    attachment_recording = TrashableAttachmentRecording.new(
      id: "recording-1",
      parent_recording: parent,
      recordable: attachment,
      root_recording: root
    )

    result = with_authorized_removal do
      RecordingStudioAttachable::Services::RemoveAttachment.call(
        attachment_recording: attachment_recording,
        actor: :actor,
        impersonator: :impersonator,
        metadata: { reason: "cleanup" }
      )
    end

    assert result.success?
    assert_equal attachment_recording, result.value
    assert_equal %i[actor impersonator], attachment_recording.trashed_with
    assert_equal 1, attachment_recording.events.length

    event = attachment_recording.events.first
    assert_equal "attachment_removed", event[:action]
    assert_equal :actor, event[:actor]
    assert_equal :impersonator, event[:impersonator]
    assert_equal(
      {
        attachment_recording_id: "recording-1",
        parent_recording_id: "parent-1",
        root_recording_id: "root-1",
        attachment_recordable_id: "attachment-1",
        attachment_kind: "image",
        name: "Photo",
        original_filename: "photo.png",
        content_type: "image/png",
        byte_size: 1024,
        source: "trash"
      },
      event[:metadata]
    )
  end

  def test_non_trashable_attachments_are_destroyed
    parent = RecordingDouble.new(id: "parent-1", recordable_type: "Workspace")
    attachment = AttachmentDouble.new(
      id: "attachment-2",
      attachment_kind: "file",
      name: "Notes",
      original_filename: "notes.txt",
      content_type: "text/plain",
      byte_size: 512
    )
    attachment_recording = DestroyOnlyAttachmentRecording.new(
      id: "recording-2",
      parent_recording: parent,
      recordable: attachment
    )

    result = with_authorized_removal do
      RecordingStudioAttachable::Services::RemoveAttachment.call(
        attachment_recording: attachment_recording,
        actor: :actor
      )
    end

    assert result.success?
    assert_equal attachment_recording, result.value
    assert attachment_recording.destroyed
  end

  private

  def with_authorized_removal(&)
    RecordingStudioAttachable::Authorization.stub(:authorize!, true, &)
  end

  def stub_recording_studio!
    studio = defined?(RecordingStudio) ? RecordingStudio : Object.const_set(:RecordingStudio, Module.new)
    studio.singleton_class.send(:remove_method, :capability_options) if studio.singleton_class.method_defined?(:capability_options)
    studio.define_singleton_method(:capability_options) { |_name, _for_type: nil, **| {} }
  end
end
