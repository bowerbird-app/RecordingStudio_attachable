# frozen_string_literal: true

module RecordingStudioAttachable
  module GoogleDrive
    class ImportsController < ApplicationController
      def index
        authorize_google_drive_upload!
        ensure_google_drive_enabled!

        return render_disconnected unless google_drive_connected?

        load_drive_page
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

      def load_drive_page
        @query = params[:query].to_s.strip
        page = drive_listing_page
        @files = listed_files(page)
        @next_page_token = page.next_cursor
      end

      def drive_listing_page
        client = google_drive_client
        cursor = params[:page_token]
        page_size = google_drive_configuration.page_size
        if @query.present?
          client.search(query: @query, cursor: cursor, page_size: page_size)
        else
          client.list(cursor: cursor, page_size: page_size)
        end
      end

      def listed_files(page)
        Array(page.entries).filter_map do |file|
          next if file.respond_to?(:folder?) && file.folder?

          {
            "id" => file.id,
            "name" => file.name,
            "mimeType" => file.mime_type,
            "webViewLink" => file.web_view_link
          }
        end
      end

      def handle_index_drive_error(error)
        return render_disconnected(reconnect: true) if Integration.reconnect_required?(error)
        raise unless Integration.request_error?(error)

        @query = params[:query].to_s.strip
        @files = []
        @next_page_token = nil
        flash.now[:alert] = error.message
        render :index, status: :bad_gateway
      end

      def handle_create_drive_error(error)
        if Integration.reconnect_required?(error)
          message = Copy.t("google_drive.reconnect_to_continue", default: "Reconnect Google Drive to continue")
          respond_to do |format|
            format.json { render json: { error: message, connect_url: google_drive_popup_connect_url }, status: :unauthorized }
            format.html { render_disconnected(reconnect: true) }
          end
        elsif Integration.request_error?(error)
          respond_to do |format|
            format.json { render json: { error: error.message }, status: :unprocessable_content }
            format.html do
              redirect_to google_drive.recording_imports_path(@recording, upload_flow_params), alert: error.message
            end
          end
        else
          raise
        end
      end

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

      def render_disconnected(reconnect: google_drive_reconnect?)
        @query = params[:query].to_s.strip
        @files = []
        @next_page_token = nil
        @show_connect = true
        @reconnect = reconnect
        @oauth_connect_path = google_drive_oauth_connect_path
        @oauth_return_to = google_drive_connect_return_path(popup: embedded_upload_provider_request?)
        @authorization_path = google_drive_popup_connect_url if embedded_upload_provider_request?
        render :index
      end

      def selected_file_ids
        Array(params[:file_ids]).filter_map do |selection|
          case selection
          when String
            selection.presence
          when ActionController::Parameters, Hash
            id = selection[:id] || selection["id"]
            next if id.blank?

            resource_key = selection[:resource_key] || selection["resource_key"] || selection[:resourceKey] || selection["resourceKey"]
            { "id" => id.to_s, "resource_key" => resource_key.to_s.presence }.compact
          end
        end.uniq
      end
    end
  end
end
