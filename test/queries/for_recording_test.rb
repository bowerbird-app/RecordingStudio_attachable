# frozen_string_literal: true

require "test_helper"
require_relative "../../app/queries/recording_studio_attachable/queries/for_recording"

class ForRecordingTest < Minitest::Test
  RecordingDouble = Struct.new(:id) do
    def recordings_query(**kwargs)
      kwargs
    end
  end

  def test_direct_scope_queries_parent_children_with_filters
    query = RecordingStudioAttachable::Queries::ForRecording.new(
      recording: RecordingDouble.new("parent-1"),
      scope: :direct,
      kind: :images,
      include_trashed: false
    )

    result = query.send(:recordable_filters)
    assert_equal({ attachment_kind: "image" }, result)
  end

  def test_normalize_scope_falls_back_to_default_for_unknown_values
    assert_equal :direct, RecordingStudioAttachable::Queries::ForRecording.normalize_scope(:bogus)
  end

  def test_normalize_kind_falls_back_to_default_for_unknown_values
    assert_equal :all, RecordingStudioAttachable::Queries::ForRecording.normalize_kind(:bogus)
  end
end
