# frozen_string_literal: true

require "test_helper"
require_relative "../../app/services/recording_studio_attachable/services/application_service"
require_relative "../../app/services/recording_studio_attachable/services/remove_attachment"
require_relative "../../app/services/recording_studio_attachable/services/remove_attachments"

class RemoveAttachmentsTest < Minitest::Test
  RecordingDouble = Struct.new(:id, :recordable_type, :relation)
  AttachmentRecordingDouble = Struct.new(:id, :recordable_type, :parent_recording)

  class RelationDouble
    def initialize(records)
      @records = records
    end

    def where(id:)
      ids = Array(id).map(&:to_s)
      @records.select { |record| ids.include?(record.id.to_s) }
    end
  end

  def setup
    stub_recording_studio!
  end

  def test_removes_selected_attachments_in_order
    parent = RecordingDouble.new("parent-1", "Workspace", nil)
    attachments = [
      AttachmentRecordingDouble.new("att-1", "RecordingStudioAttachable::Attachment", parent),
      AttachmentRecordingDouble.new("att-2", "RecordingStudioAttachable::Attachment", parent)
    ]
    parent.relation = RelationDouble.new(attachments)
    removed_ids = []
    success_result = RecordingStudioAttachable::Services::BaseService::Result.new(success: true, value: :removed)

    parent.define_singleton_method(:recordings_query) { |**| relation }

    RecordingStudioAttachable::Authorization.stub(:authorize!, true) do
      RecordingStudioAttachable::Services::RemoveAttachment.stub(:call, lambda { |**kwargs|
        removed_ids << kwargs[:attachment_recording].id
        success_result
      }) do
        result = RecordingStudioAttachable::Services::RemoveAttachments.call(
          parent_recording: parent,
          attachment_ids: %w[att-2 att-1],
          actor: Object.new
        )

        assert result.success?
        assert_equal %w[att-2 att-1], removed_ids
        assert_equal %i[removed removed], result.value
      end
    end
  end

  def test_returns_failure_when_no_attachments_are_selected
    parent = RecordingDouble.new("parent-1", "Workspace", RelationDouble.new([]))
    parent.define_singleton_method(:recordings_query) { |**| relation }

    RecordingStudioAttachable::Authorization.stub(:authorize!, true) do
      result = RecordingStudioAttachable::Services::RemoveAttachments.call(
        parent_recording: parent,
        attachment_ids: [],
        actor: Object.new
      )

      assert result.failure?
      assert_equal "Select at least one attachment to remove", result.error
    end
  end

  def test_returns_failure_when_attachment_is_outside_the_recording_scope
    parent = RecordingDouble.new("parent-1", "Workspace", RelationDouble.new([]))
    parent.define_singleton_method(:recordings_query) { |**| relation }

    RecordingStudioAttachable::Authorization.stub(:authorize!, true) do
      result = RecordingStudioAttachable::Services::RemoveAttachments.call(
        parent_recording: parent,
        attachment_ids: ["missing-attachment"],
        actor: Object.new
      )

      assert result.failure?
      assert_equal "One or more attachments do not belong to this recording", result.error
    end
  end

  private

  def stub_recording_studio!
    studio = defined?(RecordingStudio) ? RecordingStudio : Object.const_set(:RecordingStudio, Module.new)
    studio.singleton_class.send(:remove_method, :capability_options) if studio.singleton_class.method_defined?(:capability_options)
    studio.define_singleton_method(:capability_options) { |_name, _for_type: nil, **| {} }
  end
end
