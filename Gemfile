# frozen_string_literal: true

source "https://rubygems.org"

require_relative "test/support/widen_recording_studio_requirement"

# Specify your gem's dependencies in recording_studio_attachable.gemspec
gemspec

gem "flat_pack", github: "bowerbird-app/flatpack", tag: "v0.1.341"
gem "puma", "~> 7.2.1"
gem "recording_studio", github: "bowerbird-app/RecordingStudio", tag: "v6.3.0"
gem "recording_studio_metrics",
    github: "bowerbird-app/RecordingStudio_metrics",
    tag: "v0.7.2"
gem "sprockets-rails"
gem "view_component", "4.19.0"

group :development, :test do
  gem "debug"
  gem "minitest-mock"
  gem "pg", "~> 1.1"
  gem "simplecov", require: false
end

group :development do
  gem "rubocop", require: false
  gem "rubocop-rails", require: false
end
