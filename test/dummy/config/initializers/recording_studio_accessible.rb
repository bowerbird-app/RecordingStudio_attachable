# frozen_string_literal: true

return unless defined?(RecordingStudioAccessible)

RecordingStudioAccessible.configure do |config|
  config.access_actor_types = ["User"]
end
