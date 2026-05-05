# frozen_string_literal: true

require "test_helper"
require_relative "../../app/queries/recording_studio_attachable/queries/for_recording"

class ForRecordingTest < Minitest::Test
  class RecordingDouble
    attr_reader :id, :last_kwargs

    def initialize(id:, relation:)
      @id = id
      @relation = relation
    end

    def recordings_query(**kwargs)
      @last_kwargs = kwargs
      @relation
    end
  end

  class RelationDouble
    attr_reader :where_calls, :order_calls, :limit_value, :offset_value, :includes_value

    def initialize(count_value:)
      @count_value = count_value
      @where_calls = []
      @order_calls = []
    end

    def where(*args, **kwargs)
      @where_calls << (kwargs.empty? ? args : kwargs)
      self
    end

    def count
      @count_value
    end

    def order(**kwargs)
      @order_calls << kwargs
      self
    end

    def limit(value)
      @limit_value = value
      self
    end

    def offset(value)
      @offset_value = value
      self
    end

    def includes(value)
      @includes_value = value
      self
    end
  end

  class AttachmentScopeDouble
    def initialize(selected_ids)
      @selected_ids = selected_ids
    end

    def select(_column)
      @selected_ids
    end
  end

  def setup
    stub_attachment_class!
  end

  def test_call_builds_direct_scope_query_with_kind_filter
    relation = RelationDouble.new(count_value: 2)
    recording = RecordingDouble.new(id: "parent-1", relation: relation)

    RecordingStudioAttachable::Queries::ForRecording.new(
      recording: recording,
      scope: :direct,
      kind: :images
    ).call

    assert_equal(
      {
        include_children: true,
        type: RecordingStudioAttachable::Attachment.name,
        parent_id: "parent-1",
        recordable_filters: { attachment_kind: "image" }
      },
      recording.last_kwargs
    )
    assert_includes relation.where_calls, { trashed_at: nil }
  end

  def test_call_applies_name_search_and_pagination_metadata
    relation = RelationDouble.new(count_value: 27)
    recording = RecordingDouble.new(id: "parent-1", relation: relation)
    query = RecordingStudioAttachable::Queries::ForRecording.new(
      recording: recording,
      scope: :subtree,
      kind: :all,
      search: "  spec  ",
      page: 2,
      per_page: 10
    )
    captured_search = nil

    RecordingStudioAttachable::Attachment.stub(:where, lambda { |sql, pattern|
      captured_search = [sql, pattern]
      AttachmentScopeDouble.new(%w[a1 a2])
    }) do
      query.call
    end

    assert_equal ["LOWER(name) LIKE ?", "%spec%"], captured_search
    assert_includes relation.where_calls, { recordable_id: %w[a1 a2] }
    assert_equal [{ created_at: :desc, id: :desc }], relation.order_calls
    assert_equal 10, relation.limit_value
    assert_equal 10, relation.offset_value
    assert_equal 27, query.total_count
    assert_equal 3, query.total_pages
    assert_equal 2, query.current_page
    assert_equal({ recordable: [{ file_attachment: :blob }] }, relation.includes_value)
  end

  def test_current_page_is_clamped_to_total_pages
    relation = RelationDouble.new(count_value: 11)
    recording = RecordingDouble.new(id: "parent-1", relation: relation)
    query = RecordingStudioAttachable::Queries::ForRecording.new(
      recording: recording,
      page: 9,
      per_page: 5
    )

    query.call

    assert_equal 3, query.current_page
    assert_equal 10, relation.offset_value
    assert query.previous_page?
    refute query.next_page?
  end

  def test_normalize_scope_falls_back_to_default_for_unknown_values
    assert_equal :direct, RecordingStudioAttachable::Queries::ForRecording.normalize_scope(:bogus)
  end

  def test_normalize_kind_falls_back_to_default_for_unknown_values
    assert_equal :all, RecordingStudioAttachable::Queries::ForRecording.normalize_kind(:bogus)
  end

  def test_normalize_search_and_pagination_inputs
    assert_nil RecordingStudioAttachable::Queries::ForRecording.normalize_search("   ")
    assert_equal "report", RecordingStudioAttachable::Queries::ForRecording.normalize_search("  report ")
    assert_equal 1, RecordingStudioAttachable::Queries::ForRecording.normalize_page(nil)
    assert_equal 24, RecordingStudioAttachable::Queries::ForRecording.normalize_per_page(nil)
    assert_equal 100, RecordingStudioAttachable::Queries::ForRecording.normalize_per_page(250)
  end

  private

  def stub_attachment_class!
    klass =
      if defined?(RecordingStudioAttachable::Attachment)
        RecordingStudioAttachable::Attachment
      else
        RecordingStudioAttachable.const_set(:Attachment, Class.new)
      end

    return if klass.respond_to?(:where)

    klass.define_singleton_method(:where) do |*|
      raise NotImplementedError
    end
  end
end
