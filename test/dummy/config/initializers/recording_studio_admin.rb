# frozen_string_literal: true

return unless defined?(RecordingStudioAdmin)

workspace_root = lambda do
  workspace = Workspace.find_by(name: "Studio Workspace") || Workspace.first
  next unless workspace

  RecordingStudio.root_recording_for(workspace)
end

RecordingStudioAccessible.configure do |config|
  config.admin_root_resolver = workspace_root
end

RecordingStudioAdmin.configure do |config|
  config.authentication_method = :authenticate_user!
  config.current_actor_method = :current_user
  config.access_recording_resolver = lambda do |_context|
    RecordingStudioAccessible.admin_root
  end
end
