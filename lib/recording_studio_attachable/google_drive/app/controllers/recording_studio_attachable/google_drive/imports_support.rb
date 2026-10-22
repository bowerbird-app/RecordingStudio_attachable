# frozen_string_literal: true

module RecordingStudioAttachable
  module GoogleDrive
    module ImportsSupport
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
        return respond_to_reconnect_error if Integration.reconnect_required?(error)
        raise unless Integration.request_error?(error)

        respond_to_request_error(error)
      end

      def respond_to_reconnect_error
        message = Copy.t("google_drive.reconnect_to_continue", default: "Reconnect Google Drive to continue")
        respond_to do |format|
          format.json { render json: { error: message, connect_url: google_drive_popup_connect_url }, status: :unauthorized }
          format.html { render_disconnected(reconnect: true) }
        end
      end

      def respond_to_request_error(error)
        respond_to do |format|
          format.json { render json: { error: error.message }, status: :unprocessable_content }
          format.html do
            redirect_to google_drive.recording_imports_path(@recording, upload_flow_params), alert: error.message
          end
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
        Array(params[:file_ids]).filter_map { |selection| file_id_selection(selection) }.uniq
      end

      def file_id_selection(selection)
        return selection.presence if selection.is_a?(String)
        return unless selection.is_a?(Hash) || selection.is_a?(ActionController::Parameters)

        id = selection[:id] || selection["id"]
        return if id.blank?

        resource_key = nested_resource_key(selection)
        { "id" => id.to_s, "resource_key" => resource_key.to_s.presence }.compact
      end

      def nested_resource_key(selection)
        selection[:resource_key] || selection["resource_key"] || selection[:resourceKey] || selection["resourceKey"]
      end
    end
  end
end
