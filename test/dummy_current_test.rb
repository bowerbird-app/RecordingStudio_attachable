# frozen_string_literal: true

require "test_helper"
require_relative "dummy/app/models/current"

class DummyCurrentTest < Minitest::Test
  def test_dummy_current_exposes_impersonator_attribute
    assert_respond_to Current, :actor
    assert_respond_to Current, :impersonator
  end
end
