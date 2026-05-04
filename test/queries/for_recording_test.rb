# frozen_string_literal: true

require "test_helper"

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
end
