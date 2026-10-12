# frozen_string_literal: true

module RecordingStudioAttachable
  module Dropbox
    class ApplicationController < RecordingStudioAttachable::ApplicationController
      private

      def dropbox_configuration
        RecordingStudioAttachable.configuration.dropbox
      end

      def ensure_dropbox_enabled!
        raise RecordingStudioAttachable::DependencyUnavailableError, "Dropbox addon is not enabled" unless dropbox_configuration.enabled?
        return if dropbox_configuration.configured?

        raise RecordingStudioAttachable::DependencyUnavailableError,
              "Dropbox addon is missing client credentials or redirect URI"
      end

      def authorize_dropbox_upload!
        @recording = find_recording
        authorize_attachment_action!(:upload, @recording, capability_options: capability_options_for(@recording))
      end

      def dropbox_tokens
        dropbox_oauth_session.tokens
      end

      def store_dropbox_tokens!(tokens)
        dropbox_oauth_session.store_tokens!(tokens)
      end

      def clear_dropbox_tokens!
        dropbox_oauth_session.clear_tokens!
      end

      def store_dropbox_state!(recording_id:, popup: params[:popup].to_s == "1", provider_key: current_upload_provider_key,
                               redirect_params: attachment_redirect_params)
        verifier = RecordingStudioAttachable::Dropbox::OAuthClient.generate_code_verifier
        state = dropbox_oauth_session.store_state!(
          recording_id: recording_id,
          extra: pkce_state_extra(verifier, popup:, provider_key:),
          redirect_params: redirect_params
        )
        [state, verifier]
      end

      def pkce_state_extra(verifier, popup:, provider_key:)
        {
          "code_verifier" => verifier,
          "provider_modal_id" => current_upload_provider_modal_id,
          "embedded" => embedded_upload_provider_request?,
          "popup" => popup,
          "provider_key" => provider_key
        }
      end

      def consume_dropbox_state!(state)
        dropbox_oauth_session.consume_state!(state)
      end

      def current_dropbox_access_token
        RecordingStudioAttachable::Dropbox::SessionAccessToken.fetch(
          session: session,
          configuration: dropbox_configuration,
          oauth_client: oauth_client
        )
      end

      def oauth_client
        @oauth_client ||= RecordingStudioAttachable::Dropbox::OAuthClient.new(configuration: dropbox_configuration)
      end

      def dropbox_session
        dropbox_oauth_session.storage
      end

      def dropbox_oauth_session
        @dropbox_oauth_session ||= RecordingStudioAttachable::Adapter::Session.new(
          session,
          key: "recording_studio_attachable_dropbox",
          provider_name: "Dropbox"
        )
      end
    end
  end
end
