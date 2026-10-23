# frozen_string_literal: true

module RecordingStudioAttachable
  module Dropbox
    class BootstrapController < ApplicationController
      def show
        authorize_dropbox_upload!
        ensure_dropbox_enabled!
        ensure_dropbox_chooser_configured!

        render json: bootstrap_payload
      rescue RecordingStudioAttachable::DependencyUnavailableError => e
        render json: { error: e.message }, status: :unprocessable_content
      end

      private

      def bootstrap_payload
        payload = chooser_payload
        Integration.chooser_access(root: dropbox_root, actor: current_attachable_actor)
        payload
      rescue StandardError => e
        raise unless Integration.reconnect_required?(e)

        payload.merge(dropbox_popup_connect_payload)
      end

      def chooser_payload
        {
          provider_key: "dropbox",
          launcher: "dropbox",
          client_id: dropbox_configuration.client_id,
          import_url: dropbox.recording_imports_path(@recording, format: :json, **attachment_redirect_params)
        }
      end
    end
  end
end
