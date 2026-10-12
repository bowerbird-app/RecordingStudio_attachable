# frozen_string_literal: true

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
                Copy.t("google_drive.not_enabled", default: "Google Drive addon is not enabled")
        end
        return if google_drive_configuration.configured?

        raise RecordingStudioAttachable::DependencyUnavailableError,
              Copy.t(
                "google_drive.missing_credentials",
                default: "Google Drive addon is missing client credentials or redirect URI"
              )
      end

      def ensure_google_drive_picker_configured!
        return if google_drive_configuration.picker_configured?

        raise RecordingStudioAttachable::DependencyUnavailableError,
              Copy.t(
                "google_drive.picker_requires_config",
                default: "Google Drive picker requires api_key and app_id configuration"
              )
      end

      def authorize_google_drive_upload!
        @recording = find_recording
        authorize_attachment_action!(:upload, @recording, capability_options: capability_options_for(@recording))
      end

      def google_drive_connected?
        google_drive_tokens["access_token"].present?
      end

      def google_drive_tokens
        google_drive_oauth_session.tokens
      end

      def store_google_drive_tokens!(tokens)
        google_drive_oauth_session.store_tokens!(tokens)
      end

      def clear_google_drive_tokens!
        google_drive_oauth_session.clear_tokens!
      end

      def store_google_drive_state!(recording_id:, popup: params[:popup].to_s == "1",
                                    provider_key: current_upload_provider_key,
                                    redirect_params: attachment_redirect_params)
        google_drive_oauth_session.store_state!(
          recording_id: recording_id,
          extra: drive_state_extra(popup:, provider_key:),
          redirect_params: redirect_params
        )
      end

      def drive_state_extra(popup:, provider_key:)
        {
          "provider_modal_id" => current_upload_provider_modal_id,
          "embedded" => embedded_upload_provider_request?,
          "popup" => popup,
          "provider_key" => provider_key
        }
      end

      def consume_google_drive_state!(state)
        google_drive_oauth_session.consume_state!(state)
      rescue RecordingStudioAttachable::Error
        raise RecordingStudioAttachable::Error,
              Copy.t("google_drive.state_mismatch", default: "Google Drive authorization state did not match")
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
        google_drive_oauth_session.storage
      end

      def google_drive_oauth_session
        @google_drive_oauth_session ||= RecordingStudioAttachable::Adapter::Session.new(
          session,
          key: "recording_studio_attachable_google_drive",
          provider_name: "Google Drive"
        )
      end

      def dependency_unavailable_alert(error)
        redirect_to recording_studio_attachable.recording_attachment_upload_path(
          @recording || find_recording,
          attachment_redirect_params
        ), alert: error.message
      end
    end
  end
end
