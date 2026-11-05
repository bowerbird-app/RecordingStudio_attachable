# frozen_string_literal: true

return unless defined?(RecordingStudioAdmin)

RecordingStudioAdmin.configure do |config|
  config.authentication_method = :authenticate_user!
  config.current_actor_method = :current_user
  resolver = lambda do |_context|
    workspace = Workspace.find_by(name: "Studio Workspace") || Workspace.first
    RecordingStudio.root_recording_for(workspace) if workspace
  end
  config.access_recording_resolver = resolver
  config.site_admin_recording_resolver = resolver
end
