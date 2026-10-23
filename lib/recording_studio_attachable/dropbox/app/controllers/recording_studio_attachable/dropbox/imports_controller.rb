# frozen_string_literal: true

require_relative "imports_support"

module RecordingStudioAttachable
  module Dropbox
    class ImportsController < ApplicationController
      include ImportsSupport

      def index
        authorize_dropbox_upload!
        ensure_dropbox_enabled!
        render_index_page
      rescue RecordingStudioAttachable::DependencyUnavailableError => e
        dependency_unavailable_alert(e)
      rescue StandardError => e
        handle_index_dropbox_error(e)
      end

      def create
        authorize_dropbox_upload!
        ensure_dropbox_enabled!
        respond_to_import(import_result)
      rescue RecordingStudioAttachable::DependencyUnavailableError => e
        respond_to_dependency_unavailable(e)
      rescue StandardError => e
        handle_create_dropbox_error(e)
      end

      private

      def render_index_page
        return render_disconnected unless dropbox_connected?

        load_dropbox_page
        render :index
      end

      def import_result
        RecordingStudioAttachable::Dropbox::Services::ImportSelectedFiles.call(
          parent_recording: @recording,
          file_ids: selected_file_ids,
          actor: current_attachable_actor,
          impersonator: current_attachable_impersonator
        )
      end

      def respond_to_import(result)
        respond_to do |format|
          if result.success?
            format.json { render json: { redirect_path: resolved_attachment_redirect_path(@recording) }, status: :created }
            format.html { respond_to_successful_html_import(result) }
          else
            respond_to_failed_import(format, result)
          end
        end
      end

      def respond_to_failed_import(format, result)
        format.json { render json: { error: result.error }, status: :unprocessable_content }
        format.html do
          redirect_to dropbox.recording_imports_path(@recording, upload_flow_params), alert: result.error
        end
      end

      def respond_to_successful_html_import(result)
        if embedded_upload_provider_request?
          render_embedded_import_complete
        else
          redirect_to resolved_attachment_redirect_path(@recording),
                      notice: Copy.t(
                        "dropbox.imported_count",
                        count: result.value.size,
                        default: "Imported #{result.value.size} Dropbox file(s)."
                      )
        end
      end

      def render_embedded_import_complete
        render_upload_provider_modal_event(
          type: "provider-import-complete",
          provider_key: "dropbox",
          modal_id: current_upload_provider_modal_id,
          redirect_path: resolved_attachment_redirect_path(@recording)
        )
      end

      def respond_to_dependency_unavailable(error)
        respond_to do |format|
          format.json { render json: { error: error.message }, status: :unprocessable_content }
          format.html { dependency_unavailable_alert(error) }
        end
      end
    end
  end
end
