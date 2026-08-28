# Ensure RecordingStudio pages use the shared sidebar-free default layout.
Rails.application.config.to_prepare do
  RecordingStudio::ApplicationController.include(RecordingStudio::UsesDefaultLayout) if defined?(RecordingStudio::ApplicationController)
end
