# frozen_string_literal: true

module RecordingStudioAttachable
  module GoogleDrive
    class OauthController < ApplicationController
      def new
        authorize_google_drive_upload!
        ensure_google_drive_enabled!

        redirect_to oauth_client.authorization_url(
          state: store_google_drive_state!(recording_id: @recording.id, redirect_params: attachment_redirect_params)
        ), allow_other_host: true
      rescue RecordingStudioAttachable::DependencyUnavailableError => e
        dependency_unavailable_alert(e)
      end

      def callback
        ensure_google_drive_enabled!
        recording_id = google_drive_session.dig("oauth_state", "recording_id")
        state = consume_google_drive_state!(params[:state])
        tokens = oauth_client.exchange_code(code: params[:code])
        store_google_drive_tokens!(tokens.slice("access_token", "refresh_token", "expires_at"))

        if state["popup"]
          payload = {
            type: "provider-auth-complete",
            provider_key: state["provider_key"] || "google_drive",
            modal_id: state["provider_modal_id"],
            close_window: true
          }
          if state["provider_modal_id"].present?
            payload[:reload_url] = google_drive.recording_imports_path(
              state.fetch("recording_id"),
              embed: (state["embedded"] ? "modal" : nil),
              provider_modal_id: state["provider_modal_id"],
              redirect_mode: state["redirect_mode"],
              return_to: state["return_to"]
            )
          end

          return render_upload_provider_modal_event(
            **payload
          )
        end

        redirect_to google_drive.recording_imports_path(
          state.fetch("recording_id"),
          embed: (state["embedded"] ? "modal" : nil),
          provider_modal_id: state["provider_modal_id"],
          redirect_mode: state["redirect_mode"],
          return_to: state["return_to"]
        ), notice: t("recording_studio_attachable.google_drive.connected", default: "Connected Google Drive.")
      rescue RecordingStudioAttachable::Error, RecordingStudioAttachable::GoogleDrive::OAuthClient::Error => e
        recording_id ||= params[:recording_id]
        if recording_id.present?
          redirect_to google_drive.recording_imports_path(recording_id, **attachment_redirect_params), alert: e.message
        else
          redirect_to main_app.root_path, alert: e.message
        end
      end

      def destroy
        authorize_google_drive_upload!
        clear_google_drive_tokens!

        redirect_to google_drive.recording_imports_path(
          @recording,
          upload_flow_params
        ), notice: t("recording_studio_attachable.google_drive.disconnected", default: "Disconnected Google Drive.")
      end
    end
  end
end
