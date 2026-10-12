# frozen_string_literal: true

require "test_helper"

class JsonBodyTest < Minitest::Test
  def test_parse_returns_an_object_for_valid_json
    assert_equal({ "ok" => true }, RecordingStudioAttachable::JsonBody.parse('{"ok":true}'))
  end

  def test_parse_returns_an_empty_hash_for_invalid_json
    assert_equal({}, RecordingStudioAttachable::JsonBody.parse("not-json"))
  end
end
