# frozen_string_literal: true

require "test_helper"
require_relative "../../app/queries/recording_studio_attachable/queries/with_attachments"

class WithAttachmentsTest < Minitest::Test
  class ScopeDouble
    attr_reader :where_calls

    def initialize
      @where_calls = []
    end

    def where(*args, **kwargs)
      @where_calls << (kwargs.empty? ? args : kwargs)
      self
    end
  end

  class AttachmentRecordingScopeDouble
    attr_reader :where_calls, :select_value

    def initialize
      @where_calls = []
    end

    def where(*args, **kwargs)
      @where_calls << (kwargs.empty? ? args : kwargs)
      self
    end

    def select(value)
      @select_value = value
      self
    end

    def distinct
      :distinct_parent_recording_ids
    end
  end

  class AttachmentIdScopeDouble
    attr_reader :select_value

    def select(value)
      @select_value = value
      :matching_attachment_ids
    end
  end

  def setup
    klass =
      if defined?(RecordingStudio::Recording)
        RecordingStudio::Recording
      else
        RecordingStudio.const_set(:Recording, Class.new)
      end

    return if klass.respond_to?(:unscoped)

    klass.define_singleton_method(:unscoped) do
      raise NotImplementedError
    end

    attachment_class =
      if defined?(RecordingStudioAttachable::Attachment)
        RecordingStudioAttachable::Attachment
      else
        RecordingStudioAttachable.const_set(:Attachment, Class.new)
      end

    return if attachment_class.respond_to?(:where)

    attachment_class.define_singleton_method(:where) do |**_kwargs|
      raise NotImplementedError
    end
  end

  def test_call_filters_active_attachment_recordings_by_parent_ids
    scope = ScopeDouble.new
    attachment_scope = AttachmentRecordingScopeDouble.new

    RecordingStudio::Recording.stub(:unscoped, attachment_scope) do
      RecordingStudioAttachable::Queries::WithAttachments.new(scope: scope).call
    end

    assert_includes attachment_scope.where_calls, { recordable_type: RecordingStudioAttachable::Attachment.name }
    assert_includes attachment_scope.where_calls, { trashed_at: nil }
    assert_equal :parent_recording_id, attachment_scope.select_value
    assert_includes scope.where_calls, { id: :distinct_parent_recording_ids }
  end

  def test_call_filters_by_attachment_kind_when_requested
    scope = ScopeDouble.new
    attachment_scope = AttachmentRecordingScopeDouble.new
    attachment_id_scope = AttachmentIdScopeDouble.new
    captured_attachment_where = nil

    RecordingStudio::Recording.stub(:unscoped, attachment_scope) do
      RecordingStudioAttachable::Attachment.stub(:where, lambda { |**kwargs|
        captured_attachment_where = kwargs
        attachment_id_scope
      }) do
        RecordingStudioAttachable::Queries::WithAttachments.new(scope: scope, kind: :images).call
      end
    end

    assert_equal({ attachment_kind: "image" }, captured_attachment_where)
    assert_equal :id, attachment_id_scope.select_value
    assert_includes attachment_scope.where_calls, { recordable_id: :matching_attachment_ids }
    assert_includes scope.where_calls, { id: :distinct_parent_recording_ids }
  end

  def test_call_filters_parent_scope_by_recordable_type_when_requested
    scope = ScopeDouble.new
    attachment_scope = AttachmentRecordingScopeDouble.new

    RecordingStudio::Recording.stub(:unscoped, attachment_scope) do
      RecordingStudioAttachable::Queries::WithAttachments.new(scope: scope, recordable_type: "Workspace").call
    end

    assert_includes scope.where_calls, { recordable_type: "Workspace" }
    assert_includes scope.where_calls, { id: :distinct_parent_recording_ids }
  end

  def test_call_skips_trashed_filter_when_requested
    scope = ScopeDouble.new
    attachment_scope = AttachmentRecordingScopeDouble.new

    RecordingStudio::Recording.stub(:unscoped, attachment_scope) do
      RecordingStudioAttachable::Queries::WithAttachments.new(scope: scope, include_trashed: true).call
    end

    refute_includes attachment_scope.where_calls, { trashed_at: nil }
  end
end
