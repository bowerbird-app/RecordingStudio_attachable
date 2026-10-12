# frozen_string_literal: true

module RecordingStudioAttachable
  module Dropbox
    class BootstrapController < ApplicationController
      def show
        authorize_dropbox_upload!
        ensure_dropbox_enabled!

        render json: bootstrap_payload
      rescue RecordingStudioAttachable::DependencyUnavailableError, RecordingStudioAttachable::Error => e
        render json: { error: e.message }, status: :unprocessable_content
      end

      private

      def bootstrap_payload # rubocop:disable Metrics/MethodLength
        payload = {
          provider_key: "dropbox",
          launcher: "dropbox",
          client_id: dropbox_configuration.client_id,
          import_url: recording_studio_attachable.recording_attachment_imports_path(@recording, format: :json, **attachment_redirect_params)
        }

        current_dropbox_access_token
        payload
      rescue RecordingStudioAttachable::Error
        state, code_verifier = store_dropbox_state!(
          recording_id: @recording.id,
          popup: true,
          provider_key: "dropbox",
          redirect_params: attachment_redirect_params
        )
        payload.merge(
          auth_url: oauth_client.authorization_url(
            state: state,
            code_challenge: RecordingStudioAttachable::Dropbox::OAuthClient.code_challenge(code_verifier)
          )
        )
      end
    end
  end
end
