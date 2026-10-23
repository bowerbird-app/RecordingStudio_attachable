# frozen_string_literal: true

module MyCloud
  class BootstrapController < ApplicationController
    def show
      authorize_provider_upload!
      ensure_provider_available!
      render json: bootstrap_payload
    rescue RecordingStudioAttachable::DependencyUnavailableError => e
      render json: { error: e.message }, status: :unprocessable_content
    end

    private

    def bootstrap_payload
      needs_auth = !MyCloud.connected?(current_attachable_actor) || MyCloud.reconnect_required?
      provider_connect_payload(
        needs_auth: needs_auth,
        reconnect: MyCloud.reconnect_required?,
        import_url: my_cloud.recording_imports_path(@recording, format: :json, **attachment_redirect_params)
      )
    end
  end
end
