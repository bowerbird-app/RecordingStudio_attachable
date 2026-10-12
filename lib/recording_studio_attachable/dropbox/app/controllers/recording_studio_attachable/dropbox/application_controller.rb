# frozen_string_literal: true

require "securerandom"

module RecordingStudioAttachable
  module Dropbox
    # rubocop:disable Metrics/MethodLength
    class ApplicationController < RecordingStudioAttachable::ApplicationController
      private

      def dropbox_configuration
        RecordingStudioAttachable.configuration.dropbox
      end

      def ensure_dropbox_enabled!
        unless dropbox_configuration.enabled?
          raise RecordingStudioAttachable::DependencyUnavailableError,
                "Dropbox addon is not enabled"
        end
        return if dropbox_configuration.configured?

        raise RecordingStudioAttachable::DependencyUnavailableError,
              "Dropbox addon is missing client credentials or redirect URI"
      end

      def authorize_dropbox_upload!
        @recording = find_recording
        authorize_attachment_action!(:upload, @recording, capability_options: capability_options_for(@recording))
      end

      def dropbox_tokens
        dropbox_session.fetch("tokens", {})
      end

      def store_dropbox_tokens!(tokens)
        dropbox_session["tokens"] = dropbox_tokens.merge(tokens.compact.stringify_keys)
      end

      def clear_dropbox_tokens!
        dropbox_session.delete("tokens")
      end

      def store_dropbox_state!(recording_id:, popup: params[:popup].to_s == "1", provider_key: current_upload_provider_key,
                               redirect_params: attachment_redirect_params)
        state = SecureRandom.hex(24)
        code_verifier = RecordingStudioAttachable::Dropbox::OAuthClient.generate_code_verifier
        dropbox_session["oauth_state"] = {
          "value" => state,
          "code_verifier" => code_verifier,
          "recording_id" => recording_id.to_s,
          "provider_modal_id" => current_upload_provider_modal_id,
          "embedded" => embedded_upload_provider_request?,
          "popup" => popup,
          "provider_key" => provider_key
        }.merge(redirect_params.stringify_keys)
        [state, code_verifier]
      end

      def consume_dropbox_state!(state)
        saved = dropbox_session.delete("oauth_state") || {}
        expected = saved["value"].to_s
        actual = state.to_s

        return saved if expected.present? && actual.present? && ActiveSupport::SecurityUtils.secure_compare(expected, actual)

        raise RecordingStudioAttachable::Error, "Dropbox authorization state did not match"
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
        session["recording_studio_attachable_dropbox"] ||= {}
      end
    end
    # rubocop:enable Metrics/MethodLength
  end
end
