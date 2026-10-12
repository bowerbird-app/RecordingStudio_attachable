# frozen_string_literal: true

module RecordingStudioAttachable
  module Dropbox
    class BootstrapController < ApplicationController
      def show
        authorize_dropbox_upload!
        ensure_dropbox_enabled!
        render json: bootstrap_payload
      rescue RecordingStudioAttachable::DependencyUnavailableError => e
        render json: { error: e.message }, status: :unprocessable_content
      end

      private

      def bootstrap_payload
        payload = chooser_payload
        current_dropbox_access_token
        payload
      rescue RecordingStudioAttachable::Error
        payload.merge(auth_url: popup_auth_url)
      end

      def chooser_payload
        {
          provider_key: "dropbox",
          launcher: "dropbox",
          client_id: dropbox_configuration.client_id,
          import_url: import_json_url
        }
      end

      def import_json_url
        recording_studio_attachable.recording_attachment_imports_path(
          @recording,
          format: :json,
          **attachment_redirect_params
        )
      end

      def popup_auth_url
        state, verifier = store_dropbox_state!(
          recording_id: @recording.id,
          popup: true,
          provider_key: "dropbox",
          redirect_params: attachment_redirect_params
        )
        oauth_client.authorization_url(
          state: state,
          code_challenge: RecordingStudioAttachable::Dropbox::OAuthClient.code_challenge(verifier)
        )
      end
    end
  end
end
