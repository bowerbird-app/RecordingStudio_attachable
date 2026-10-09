# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require_relative "simplecov_helper"
require "minitest/autorun"
require "minitest/mock"
require "rails"
require "active_storage/engine"
require "recording_studio_attachable"

Dir[File.expand_path("../config/locales/*.yml", __dir__)].each do |path|
  expanded = File.expand_path(path)
  I18n.load_path << expanded unless I18n.load_path.map { |entry| File.expand_path(entry) }.include?(expanded)
end
I18n.backend.load_translations

Mime::Type.register "text/vnd.turbo-stream.html", :turbo_stream unless Mime::Type.lookup_by_extension(:turbo_stream)

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
