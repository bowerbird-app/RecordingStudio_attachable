# frozen_string_literal: true

module RecordingStudioAttachable
  module Dropbox
    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Layout/LineLength
    class OauthController < ApplicationController
      def new
        authorize_dropbox_upload!
        ensure_dropbox_enabled!

        state, code_verifier = store_dropbox_state!(recording_id: @recording.id, redirect_params: attachment_redirect_params)
        redirect_to oauth_client.authorization_url(
          state: state,
          code_challenge: RecordingStudioAttachable::Dropbox::OAuthClient.code_challenge(code_verifier)
        ), allow_other_host: true
      rescue RecordingStudioAttachable::DependencyUnavailableError => e
        redirect_to recording_studio_attachable.recording_attachment_upload_path(@recording || find_recording, attachment_redirect_params),
                    alert: e.message
      end

      def callback
        ensure_dropbox_enabled!
        recording_id = dropbox_session.dig("oauth_state", "recording_id")
        state = consume_dropbox_state!(params[:state])
        tokens = oauth_client.exchange_code(code: params[:code], code_verifier: state.fetch("code_verifier"))
        store_dropbox_tokens!(tokens.slice("access_token", "refresh_token", "expires_at"))

        if state["popup"]
          return render_upload_provider_modal_event(
            type: "provider-auth-complete",
            provider_key: state["provider_key"] || "dropbox",
            modal_id: state["provider_modal_id"],
            close_window: true
          )
        end

        redirect_to recording_studio_attachable.recording_attachment_upload_path(
          state.fetch("recording_id"),
          redirect_mode: state["redirect_mode"],
          return_to: state["return_to"]
        ), notice: t("recording_studio_attachable.dropbox.connected", default: "Connected Dropbox.")
      rescue RecordingStudioAttachable::Error, RecordingStudioAttachable::Dropbox::OAuthClient::Error => e
        recording_id ||= params[:recording_id]
        if recording_id.present?
          redirect_to recording_studio_attachable.recording_attachment_upload_path(recording_id, **attachment_redirect_params), alert: e.message
        else
          redirect_to main_app.root_path, alert: e.message
        end
      end

      def destroy
        authorize_dropbox_upload!
        clear_dropbox_tokens!

        redirect_to recording_studio_attachable.recording_attachment_upload_path(
          @recording,
          upload_flow_params
        ), notice: t("recording_studio_attachable.dropbox.disconnected", default: "Disconnected Dropbox.")
      end
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Layout/LineLength
  end
end
