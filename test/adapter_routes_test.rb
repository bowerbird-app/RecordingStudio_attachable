# frozen_string_literal: true

require "test_helper"

class AdapterRoutesTest < Minitest::Test
  def test_register_adapter_routes_is_keyed_and_raises_on_a_second_registration
    first = proc { "first" }
    second = proc { "second" }
    key = :"fake_cloud_#{object_id}"

    RecordingStudioAttachable.register_adapter_routes(key, &first)
    error = assert_raises(ArgumentError) do
      RecordingStudioAttachable.register_adapter_routes(key, &second)
    end

    assert_match(/already registered/, error.message)
    assert_same first, RecordingStudioAttachable.adapter_route_blocks[key]
  end

  def test_register_adapter_routes_requires_a_key_and_block
    assert_raises(ArgumentError) { RecordingStudioAttachable.register_adapter_routes(nil) { nil } }
    assert_raises(ArgumentError) { RecordingStudioAttachable.register_adapter_routes(:missing_block) }
  end
end
