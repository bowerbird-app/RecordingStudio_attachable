# frozen_string_literal: true

RecordingStudio.configure do |config|
  config.recordable_types = [ "Workspace", "Page", "RecordingStudioAttachable::Attachment" ]
  config.actor = -> { Current.actor }
  config.event_notifications_enabled = true
  config.idempotency_mode = :return_existing
  config.recordable_dup_strategy = :dup
end
