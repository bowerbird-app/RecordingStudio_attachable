# frozen_string_literal: true

module RecordingStudioAttachable
  class ProviderController < ApplicationController
    class_attribute :upload_provider_key

    helper_method :provider_label, :current_upload_provider_key, :current_upload_provider_modal_id,
                  :upload_flow_params, :provider_csrf_token

    private

    def authorize_provider_upload!
      @recording = find_recording
      authorize_attachment_action!(:upload, @recording, capability_options: capability_options_for(@recording))
    end

    def ensure_provider_available!
      return if current_provider

      raise RecordingStudioAttachable::DependencyUnavailableError,
            Copy.t(
              "providers.not_available",
              provider: provider_label,
              default: "#{provider_label} isn't available right now"
            )
    end

    def provider_connect_payload(needs_auth:, reconnect:, import_url: nil)
      RecordingStudioAttachable::ProviderConnect.payload(
        provider: current_provider,
        recording: @recording,
        context: self,
        needs_auth: needs_auth,
        reconnect: reconnect,
        import_url: import_url
      )
    end

    def render_provider_auth_complete(reload_url: nil)
      render_upload_provider_modal_event(
        type: "provider-auth-complete",
        provider_key: self.class.upload_provider_key.to_s,
        modal_id: current_upload_provider_modal_id,
        reload_url: reload_url,
        close_window: true
      )
    end

    def dependency_unavailable_alert(error)
      redirect_to recording_studio_attachable.recording_attachment_upload_path(
        @recording || find_recording,
        attachment_redirect_params
      ), alert: error.message
    end

    def current_provider
      return if self.class.upload_provider_key.blank?

      RecordingStudioAttachable.configuration.upload_provider(self.class.upload_provider_key)
    end

    def provider_label
      current_provider&.label.presence || self.class.upload_provider_key.to_s.tr("_", " ")
    end
  end
end
