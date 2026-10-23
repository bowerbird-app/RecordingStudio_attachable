# frozen_string_literal: true

module MyCloud
  class ApplicationController < RecordingStudioAttachable::ProviderController
    self.upload_provider_key = :my_cloud
  end
end
