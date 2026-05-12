# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require_relative "simplecov_helper"
require "minitest/autorun"
require "rails"
require "active_storage/engine"
require "recording_studio_attachable"

module Minitest
  module Assertions
    def assert_not(value, message = nil)
      refute(value, message)
    end

    def assert_not_includes(collection, object, message = nil)
      refute_includes(collection, object, message)
    end

    def assert_not_nil(value, message = nil)
      refute_nil(value, message)
    end

    def assert_no_match(matcher, value, message = nil)
      refute_match(matcher, value, message)
    end
  end
end
