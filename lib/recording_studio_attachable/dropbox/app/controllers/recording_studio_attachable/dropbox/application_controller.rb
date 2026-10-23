# frozen_string_literal: true

module RecordingStudioAttachable
  module Dropbox
    class ApplicationController < RecordingStudioAttachable::ApplicationController
      helper_method :dropbox_connected?, :dropbox_reconnect?,
                    :current_upload_provider_key, :current_upload_provider_modal_id

      private

      def dropbox_configuration
        RecordingStudioAttachable.configuration.dropbox
      end

      def ensure_dropbox_enabled!
        return if dropbox_configuration.enabled? && Integration.gem_loaded?

        raise RecordingStudioAttachable::DependencyUnavailableError,
              Copy.t("dropbox.not_enabled", default: "Dropbox isn't available right now")
      end

      def ensure_dropbox_chooser_configured!
        return if dropbox_configuration.chooser_configured?

        raise RecordingStudioAttachable::DependencyUnavailableError,
              Copy.t("dropbox.chooser_requires_config", default: "Dropbox Chooser needs an app key")
      end

      def authorize_dropbox_upload!
        @recording = find_recording
        authorize_attachment_action!(:upload, @recording, capability_options: capability_options_for(@recording))
      end

      def dropbox_root
        recording = @recording || find_recording
        return recording unless recording.respond_to?(:root_recording)

        recording.root_recording || recording
      end

      def dropbox_client
        Integration.client(root: dropbox_root, actor: current_attachable_actor)
      end

      def dropbox_connection
        Integration.connection(root: dropbox_root, actor: current_attachable_actor)
      end

      def dropbox_connected?
        dropbox_connection.present?
      end

      def dropbox_reconnect?
        Integration.connection_status(root: dropbox_root, actor: current_attachable_actor) == :needs_reconnect
      end

      def dropbox_oauth_connect_path
        return unless Integration.oauth_loaded?

        ::RecordingStudioOauth::Engine.routes.url_helpers.outbound_connect_path(
          provider: Integration.provider_key
        )
      end

      def dropbox_oauth_disconnect_path(connection_id)
        return if connection_id.blank? || !Integration.oauth_loaded?

        ::RecordingStudioOauth::Engine.routes.url_helpers.outbound_connection_path(
          connection_id,
          return_to: dropbox.recording_imports_path(@recording, upload_flow_params)
        )
      end

      def dropbox_popup_connect_url
        recording_connect_path(
          @recording,
          popup: 1,
          provider_key: "dropbox",
          **attachment_redirect_params
        )
      end

      def dropbox_popup_connect_payload
        {
          connect_url: dropbox_popup_connect_url,
          oauth_connect_url: dropbox_oauth_connect_path,
          return_to: dropbox_connect_return_path(popup: true),
          authenticity_token: form_authenticity_token
        }.compact
      end

      def dropbox_connect_return_path(popup:)
        if popup
          dropbox.recording_connected_path(@recording, popup: 1, **upload_flow_params)
        else
          dropbox.recording_imports_path(@recording, **upload_flow_params)
        end
      end

      def dropbox_connect_reload_url
        dropbox.recording_imports_path(
          @recording,
          **upload_flow_params,
          embed: "modal",
          provider_key: "dropbox"
        )
      end

      def disconnect_dropbox
        connection_id = Integration.connection_id_for(root: dropbox_root, actor: current_attachable_actor)
        dropbox_oauth_disconnect_path(connection_id)
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
