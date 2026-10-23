# frozen_string_literal: true

require "stringio"

module MyCloud
  class ImportsController < ApplicationController
    def index
      authorize_provider_upload!
      ensure_provider_available!
      @show_connect = !MyCloud.connected?(current_attachable_actor) || MyCloud.reconnect_required?
      @reconnect = MyCloud.reconnect_required?
      @path = params[:path].to_s
      @query = params[:query]
      @current_path = @path.presence || "/"
      @parent_url = parent_folder_url
      @files = decorated_entries
      render :index
    rescue RecordingStudioAttachable::DependencyUnavailableError => e
      dependency_unavailable_alert(e)
    end

    def create
      authorize_provider_upload!
      ensure_provider_available!
      raise RecordingStudioAttachable::ReconnectRequired, "reconnect" if MyCloud.reconnect_required?

      result = import_selected
      if result.success?
        redirect_to resolved_attachment_redirect_path(@recording),
                    notice: RecordingStudioAttachable::Copy.t(
                      "providers.imported_count",
                      count: result.value.size,
                      default: "Imported #{result.value.size} files."
                    )
      else
        redirect_to my_cloud.recording_imports_path(@recording, upload_flow_params.merge(path: params[:path])),
                    alert: result.error
      end
    rescue RecordingStudioAttachable::DependencyUnavailableError => e
      respond_to do |format|
        format.json { render json: { error: e.message }, status: :unprocessable_content }
        format.html { dependency_unavailable_alert(e) }
      end
    end

    private

    def decorated_entries
      MyCloud.entries_at(@path).map do |entry|
        next entry unless entry["kind"] == "folder"

        entry.merge(
          "open_url" => my_cloud.recording_imports_path(@recording, **upload_flow_params, path: entry["id"])
        )
      end
    end

    def parent_folder_url
      return if @path.blank?

      my_cloud.recording_imports_path(@recording, **upload_flow_params)
    end

    def import_selected
      ids = Array(params[:file_ids]).compact_blank
      if ids.blank?
        return RecordingStudioAttachable::Services::BaseService::Result.new(
          success: false,
          error: RecordingStudioAttachable::Copy.t("providers.select_at_least_one", default: "Select at least one file")
        )
      end

      RecordingStudioAttachable::Services::ImportRemoteFiles.call(
        parent_recording: @recording,
        provider_key: :my_cloud,
        actor: current_attachable_actor,
        impersonator: current_attachable_impersonator,
        payloads: ids.map { |id| remote_payload(id) }
      )
    end

    def remote_payload(id)
      file = MyCloud::FILES.find { |entry| entry["id"] == id } || MyCloud::FILES.first
      {
        download: -> { { io: StringIO.new(MyCloud::CLOUD_PNG), filename: file["name"], content_type: file["content_type"] } },
        filename: file["name"],
        content_type: file["content_type"],
        byte_size: MyCloud::CLOUD_PNG.bytesize,
        name: file["name"],
        metadata: { external_id: file["id"], external_url: "https://cloud.test/#{file['id']}" }
      }
    end
  end
end
