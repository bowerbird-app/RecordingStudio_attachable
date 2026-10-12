# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require_relative "simplecov_helper"
require "minitest/autorun"
require "minitest/mock"
require "rails"
require "active_storage/engine"
require "i18n"
require "yaml"
require "recording_studio_attachable"

# Do not append gem locales to I18n.load_path here. Rails engines already put
# config/locales on the load path when the dummy boots; an explicit append can
# re-order files so gem English overrides the host. Unit tests (no Rails app)
# seed the backend from en.yml without touching the load path.
I18n.available_locales = Array(I18n.available_locales) | %i[en]
I18n.default_locale = :en
Dir[File.expand_path("../config/locales/*.yml", __dir__)].each do |path|
  tree = YAML.safe_load_file(path, aliases: true).fetch("en")
  I18n.backend.store_translations(:en, tree)
end

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
