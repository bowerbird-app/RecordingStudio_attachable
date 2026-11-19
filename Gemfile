# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in gem_template.gemspec
gemspec

gem "flat_pack", github: "bowerbird-app/flatpack", tag: "v0.1.380"
gem "puma", "~> 8.1"
gem "recording_studio", github: "bowerbird-app/RecordingStudio", tag: "v7.7.2"
gem "recording_studio_accessible", github: "bowerbird-app/RecordingStudio_accessible", tag: "v0.55.0"
gem "recording_studio_api", github: "bowerbird-app/RecordingStudio_api", tag: "v1.19.0"
gem "recording_studio_icons", github: "bowerbird-app/RecordingStudio_icons", tag: "v0.4.2"
gem "recording_studio_logs", github: "bowerbird-app/RecordingStudio_logs", tag: "v0.8.2"
gem "recording_studio_metrics",
    github: "bowerbird-app/RecordingStudio_metrics",
    tag: "v0.9.2"
gem "recording_studio_moveable", github: "bowerbird-app/RecordingStudio_moveable", tag: "v6.0.3"
gem "recording_studio_trashable", github: "bowerbird-app/RecordingStudio_trashable", tag: "v1.2.3"
gem "sprockets-rails"
gem "view_component", "~> 4.19"

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
