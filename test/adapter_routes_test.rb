# frozen_string_literal: true

require "test_helper"

class AdapterRoutesTest < Minitest::Test
  def test_register_adapter_routes_is_keyed_and_first_wins
    first = proc { "first" }
    second = proc { "second" }

    RecordingStudioAttachable.register_adapter_routes(:fake_cloud, &first)
    RecordingStudioAttachable.register_adapter_routes(:fake_cloud, &second)

    assert_same first, RecordingStudioAttachable.adapter_route_blocks[:fake_cloud]
  end

  def test_register_adapter_routes_requires_a_key_and_block
    assert_raises(ArgumentError) { RecordingStudioAttachable.register_adapter_routes(nil) { nil } }
    assert_raises(ArgumentError) { RecordingStudioAttachable.register_adapter_routes(:missing_block) }
  end
end
