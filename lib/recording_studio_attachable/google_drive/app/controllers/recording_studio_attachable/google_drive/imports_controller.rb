# frozen_string_literal: true

require_relative "imports_support"

module RecordingStudioAttachable
  module GoogleDrive
    class ImportsController < ApplicationController
      include ImportsSupport

      def index
        authorize_google_drive_upload!
        ensure_google_drive_enabled!

        return render_disconnected unless google_drive_connected?

        load_drive_page
        render :index
      rescue RecordingStudioAttachable::DependencyUnavailableError => e
        dependency_unavailable_alert(e)
      rescue StandardError => e
        handle_index_drive_error(e)
      end

      def create
        authorize_google_drive_upload!
        ensure_google_drive_enabled!

        respond_to_import(
          RecordingStudioAttachable::GoogleDrive::Services::ImportSelectedFiles.call(
            parent_recording: @recording,
            file_ids: selected_file_ids,
            actor: current_attachable_actor,
            impersonator: current_attachable_impersonator
          )
        )
      rescue RecordingStudioAttachable::DependencyUnavailableError => e
        respond_to do |format|
          format.json { render json: { error: e.message }, status: :unprocessable_content }
          format.html { dependency_unavailable_alert(e) }
        end
      rescue StandardError => e
        handle_create_drive_error(e)
      end

      private

      def respond_to_import(result)
        respond_to do |format|
          if result.success?
            format.json { render json: { redirect_path: resolved_attachment_redirect_path(@recording) }, status: :created }
            format.html { respond_to_successful_html_import(result) }
          else
            format.json { render json: { error: result.error }, status: :unprocessable_content }
            format.html do
              redirect_to google_drive.recording_imports_path(@recording, upload_flow_params), alert: result.error
            end
          end
        end
      end

      def respond_to_successful_html_import(result)
        if embedded_upload_provider_request?
          render_upload_provider_modal_event(
            type: "provider-import-complete",
            provider_key: "google_drive",
            modal_id: current_upload_provider_modal_id,
            redirect_path: resolved_attachment_redirect_path(@recording)
          )
        else
          redirect_to resolved_attachment_redirect_path(@recording),
                      notice: Copy.t(
                        "google_drive.imported_count",
                        count: result.value.size,
                        default: "Imported #{result.value.size} Google Drive file(s)."
                      )
        end
      end
    end
  end
end
