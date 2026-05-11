# frozen_string_literal: true

require "securerandom"

module RecordingStudioAttachable
  module GoogleDrive
    class ApplicationController < RecordingStudioAttachable::ApplicationController
      helper_method :google_drive_connected?

      private

      def google_drive_configuration
        RecordingStudioAttachable.configuration.google_drive
      end

      def ensure_google_drive_enabled!
        unless google_drive_configuration.enabled?
          raise RecordingStudioAttachable::DependencyUnavailableError,
                "Google Drive addon is not enabled"
        end
        return if google_drive_configuration.configured?

        raise RecordingStudioAttachable::DependencyUnavailableError,
              "Google Drive addon is missing client credentials or redirect URI"
      end

      def ensure_google_drive_picker_configured!
        return if google_drive_configuration.picker_configured?

        raise RecordingStudioAttachable::DependencyUnavailableError,
              "Google Drive picker requires api_key and app_id configuration"
      end

      def authorize_google_drive_upload!
        @recording = find_recording
        authorize_attachment_action!(:upload, @recording, capability_options: capability_options_for(@recording))
      end

      def google_drive_connected?
        google_drive_tokens["access_token"].present?
      end

      def google_drive_tokens
        google_drive_session.fetch("tokens", {})
      end

      def store_google_drive_tokens!(tokens)
        google_drive_session["tokens"] = google_drive_tokens.merge(tokens.compact.stringify_keys)
      end

      def clear_google_drive_tokens!
        google_drive_session.delete("tokens")
      end

      def store_google_drive_state!(recording_id:, popup: params[:popup].to_s == "1", provider_key: current_upload_provider_key,
                                    redirect_params: attachment_redirect_params)
        state = SecureRandom.hex(24)
        google_drive_session["oauth_state"] = {
          "value" => state,
          "recording_id" => recording_id.to_s,
          "provider_modal_id" => current_upload_provider_modal_id,
          "embedded" => embedded_upload_provider_request?,
          "popup" => popup,
          "provider_key" => provider_key
        }.merge(redirect_params.stringify_keys)
        state
      end

      def consume_google_drive_state!(state)
        saved = google_drive_session.delete("oauth_state") || {}
        expected = saved["value"].to_s
        actual = state.to_s

        return saved if expected.present? && actual.present? && ActiveSupport::SecurityUtils.secure_compare(expected, actual)

        raise RecordingStudioAttachable::Error, "Google Drive authorization state did not match"
      end

      def current_google_drive_access_token
        RecordingStudioAttachable::GoogleDrive::SessionAccessToken.fetch(
          session: session,
          configuration: google_drive_configuration,
          oauth_client: oauth_client
        )
      end

      def oauth_client
        @oauth_client ||= RecordingStudioAttachable::GoogleDrive::OAuthClient.new(configuration: google_drive_configuration)
      end

      def google_drive_client(access_token: current_google_drive_access_token)
        RecordingStudioAttachable::GoogleDrive::Client.new(access_token: access_token)
      end

      def google_drive_session
        session["recording_studio_attachable_google_drive"] ||= {}
      end

      def dependency_unavailable_alert(error)
        redirect_to recording_studio_attachable.recording_attachment_upload_path(@recording || find_recording, attachment_redirect_params),
                    alert: error.message
      end
    end
  end
end
