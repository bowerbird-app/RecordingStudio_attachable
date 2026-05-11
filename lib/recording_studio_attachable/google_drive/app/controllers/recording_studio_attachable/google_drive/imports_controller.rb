# frozen_string_literal: true

module RecordingStudioAttachable
  module GoogleDrive
    # rubocop:disable Metrics/ClassLength, Metrics/CyclomaticComplexity
    class ImportsController < ApplicationController
      def index
        authorize_google_drive_upload!
        ensure_google_drive_enabled!

        return render_disconnected unless google_drive_connected?

        @query = params[:query].to_s.strip
        response = google_drive_client.list_files(query: @query.presence, page_token: params[:page_token])
        @files = response.fetch("files", [])
        @next_page_token = response["nextPageToken"]
      rescue RecordingStudioAttachable::DependencyUnavailableError => e
        dependency_unavailable_alert(e)
      rescue RecordingStudioAttachable::GoogleDrive::Client::UnauthorizedError
        clear_google_drive_tokens!
        redirect_to google_drive.recording_imports_path(@recording, upload_flow_params),
                    alert: "Google Drive session expired. Reconnect to continue."
      rescue RecordingStudioAttachable::GoogleDrive::Client::Error => e
        @query = params[:query].to_s.strip
        @files = []
        @next_page_token = nil
        flash.now[:alert] = e.message
        render :index, status: :bad_gateway
      end

      def create
        authorize_google_drive_upload!
        ensure_google_drive_enabled!

        result = RecordingStudioAttachable::GoogleDrive::Services::ImportSelectedFiles.call(
          parent_recording: @recording,
          file_ids: selected_file_ids,
          access_token: current_google_drive_access_token,
          actor: current_attachable_actor,
          impersonator: current_attachable_impersonator
        )

        respond_to do |format|
          if result.success?
            format.json do
              render json: {
                redirect_path: resolved_attachment_redirect_path(@recording)
              }, status: :created
            end

            format.html do
              if embedded_upload_provider_request?
                render_upload_provider_modal_event(
                  type: "provider-import-complete",
                  provider_key: "google_drive",
                  modal_id: current_upload_provider_modal_id,
                  redirect_path: resolved_attachment_redirect_path(@recording)
                )
              else
                redirect_to resolved_attachment_redirect_path(@recording),
                            notice: "Imported #{result.value.size} Google Drive file(s)."
              end
            end
          else
            format.json { render json: { error: result.error }, status: :unprocessable_entity }
            format.html do
              redirect_to google_drive.recording_imports_path(
                @recording,
                upload_flow_params
              ), alert: result.error
            end
          end
        end
      rescue RecordingStudioAttachable::DependencyUnavailableError => e
        respond_to do |format|
          format.json { render json: { error: e.message }, status: :unprocessable_entity }
          format.html { dependency_unavailable_alert(e) }
        end
      rescue RecordingStudioAttachable::GoogleDrive::Client::UnauthorizedError
        clear_google_drive_tokens!
        respond_to do |format|
          format.json { render json: { error: "Google Drive session expired. Reconnect to continue." }, status: :unauthorized }
          format.html do
            redirect_to google_drive.recording_imports_path(
              @recording,
              upload_flow_params
            ), alert: "Google Drive session expired. Reconnect to continue."
          end
        end
      end

      private

      def render_disconnected
        @query = params[:query].to_s.strip
        @files = []
        @next_page_token = nil
        @authorization_path = google_drive.recording_connect_path(
          @recording,
          upload_flow_params.merge(popup: (embedded_upload_provider_request? ? 1 : nil))
        )
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
    # rubocop:enable Metrics/ClassLength, Metrics/CyclomaticComplexity
  end
end
