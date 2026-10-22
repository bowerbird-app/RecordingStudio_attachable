# frozen_string_literal: true

return unless defined?(RecordingStudioSiteSettings)

RecordingStudioSiteSettings.configure do |config|
  config.site_root_types = ["Workspace"]
end
