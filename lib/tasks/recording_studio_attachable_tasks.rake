# frozen_string_literal: true

namespace :recording_studio_attachable do
  desc "Validate RecordingStudioAttachable installation and runtime dependencies"
  task doctor: :environment do
    result = RecordingStudioAttachable::EnvironmentDoctor.call
    exit(false) unless result.success?
  end
end
