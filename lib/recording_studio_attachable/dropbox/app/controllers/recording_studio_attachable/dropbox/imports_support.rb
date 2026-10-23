# frozen_string_literal: true

require "marcel"

module RecordingStudioAttachable
  module Dropbox
    module ImportsSupport
      private

      def load_dropbox_page
        @query = params[:query].to_s.strip
        page = dropbox_listing_page
        @files = listed_files(page)
        @next_page_token = page.next_cursor
      end

      def dropbox_listing_page
        client = dropbox_client
        cursor = params[:page_token]
        page_size = dropbox_configuration.page_size
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
            "mimeType" => mime_type_for(file)
          }
        end
      end

      def mime_type_for(file)
        Marcel::MimeType.for(name: file.name.to_s)
      end

      def handle_index_dropbox_error(error)
        return render_disconnected(reconnect: true) if Integration.reconnect_required?(error)
        raise unless Integration.request_error?(error)

        @query = params[:query].to_s.strip
        @files = []
        @next_page_token = nil
        flash.now[:alert] = error.message
        render :index, status: :bad_gateway
      end

      def handle_create_dropbox_error(error)
        return respond_to_reconnect_error if Integration.reconnect_required?(error)
        raise unless Integration.request_error?(error)

        respond_to_request_error(error)
      end

      def respond_to_reconnect_error
        message = Copy.t("dropbox.reconnect_to_continue", default: "Reconnect Dropbox to continue")
        respond_to do |format|
          format.json { render json: reconnect_json(message), status: :unauthorized }
          format.html { render_disconnected(reconnect: true) }
        end
      end

      def reconnect_json(message)
        { error: message }.merge(dropbox_popup_connect_payload)
      end

      def respond_to_request_error(error)
        respond_to do |format|
          format.json { render json: { error: error.message }, status: :unprocessable_content }
          format.html do
            redirect_to dropbox.recording_imports_path(@recording, upload_flow_params), alert: error.message
          end
        end
      end

      def render_disconnected(reconnect: dropbox_reconnect?)
        @query = params[:query].to_s.strip
        @files = []
        @next_page_token = nil
        @show_connect = true
        @reconnect = reconnect
        @oauth_connect_path = dropbox_oauth_connect_path
        @oauth_return_to = dropbox_connect_return_path(popup: embedded_upload_provider_request?)
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

        {
          "id" => id.to_s,
          "name" => (selection[:name] || selection["name"]).to_s.presence
        }.compact
      end
    end
  end
end
