# frozen_string_literal: true

RecordingStudioSiteSettings.configure do |config|
  config.site_root_types = ["Workspace"]
  config.site_root_resolver = lambda do |_context|
    workspace = Workspace.find_by(name: "Studio Workspace") || Workspace.first
    RecordingStudio.root_recording_for(workspace) if workspace
  end
end
