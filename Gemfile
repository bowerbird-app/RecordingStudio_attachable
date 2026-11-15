# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in gem_template.gemspec
gemspec

gem "flat_pack", github: "bowerbird-app/flatpack", tag: "v0.1.376"
gem "puma", "8.1.0"
gem "recording_studio", github: "bowerbird-app/RecordingStudio", tag: "v7.0.0"
gem "recording_studio_accessible", github: "bowerbird-app/RecordingStudio_accessible", tag: "v0.44.0"
gem "recording_studio_api", github: "bowerbird-app/RecordingStudio_api", tag: "v0.24.0"
gem "recording_studio_icons", github: "bowerbird-app/RecordingStudio_icons", tag: "v0.2.1"
gem "recording_studio_logs", github: "bowerbird-app/RecordingStudio_logs", tag: "v0.8.0"
gem "recording_studio_metrics",
    github: "bowerbird-app/RecordingStudio_metrics",
    tag: "v0.9.0"
gem "recording_studio_moveable", github: "bowerbird-app/RecordingStudio_moveable", tag: "v5.0.0"
gem "recording_studio_trashable", github: "bowerbird-app/RecordingStudio_trashable", tag: "v0.17.0"
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
