# frozen_string_literal: true

module RecordingStudioAttachable
  module Dropbox
    class ConnectController < ApplicationController
      def show
        authorize_dropbox_upload!
        ensure_dropbox_enabled!

        @oauth_connect_path = dropbox_oauth_connect_path
        @oauth_return_to = dropbox_connect_return_path(popup: params[:popup].to_s == "1")
        @auto_submit = params[:popup].to_s == "1"
        @reconnect = dropbox_reconnect?
        render :show
      rescue RecordingStudioAttachable::DependencyUnavailableError => e
        dependency_unavailable_alert(e)
      end

      def complete
        authorize_dropbox_upload!
        ensure_dropbox_enabled!
        render_connect_complete
      rescue RecordingStudioAttachable::DependencyUnavailableError => e
        dependency_unavailable_alert(e)
      end

      def destroy
        authorize_dropbox_upload!
        ensure_dropbox_enabled!
        redirect_after_disconnect(disconnect_dropbox)
      rescue RecordingStudioAttachable::DependencyUnavailableError => e
        dependency_unavailable_alert(e)
      end

      private

      def render_connect_complete
        render_upload_provider_modal_event(
          type: "provider-auth-complete",
          provider_key: "dropbox",
          modal_id: current_upload_provider_modal_id,
          reload_url: dropbox_connect_reload_url,
          close_window: true
        )
      end

      def redirect_after_disconnect(oauth_disconnect_path)
        if oauth_disconnect_path.present?
          redirect_to oauth_disconnect_path, status: :temporary_redirect
        else
          redirect_to dropbox.recording_imports_path(@recording, upload_flow_params),
                      alert: Copy.t("dropbox.disconnect_failed", default: "Dropbox isn't connected.")
        end
      end
    end
  end
end
