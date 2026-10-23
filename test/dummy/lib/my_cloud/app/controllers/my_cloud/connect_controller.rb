# frozen_string_literal: true

module MyCloud
  class ConnectController < ApplicationController
    def show
      authorize_provider_upload!
      ensure_provider_available!
      @reconnect = MyCloud.reconnect_required?
      render :show
    rescue RecordingStudioAttachable::DependencyUnavailableError => e
      dependency_unavailable_alert(e)
    end

    def create
      authorize_provider_upload!
      ensure_provider_available!
      MyCloud.connect!(current_attachable_actor)
      redirect_to my_cloud.recording_connected_path(@recording, popup: params[:popup], **upload_flow_params)
    rescue RecordingStudioAttachable::DependencyUnavailableError => e
      dependency_unavailable_alert(e)
    end

    def complete
      authorize_provider_upload!
      ensure_provider_available!
      render_provider_auth_complete(reload_url: my_cloud.recording_imports_path(@recording, **upload_flow_params, embed: "modal"))
    rescue RecordingStudioAttachable::DependencyUnavailableError => e
      dependency_unavailable_alert(e)
    end

    def destroy
      authorize_provider_upload!
      ensure_provider_available!
      MyCloud.disconnect!(current_attachable_actor)
      redirect_to my_cloud.recording_imports_path(@recording, upload_flow_params),
                  notice: RecordingStudioAttachable::Copy.t("providers.disconnect", default: "Disconnect")
    rescue RecordingStudioAttachable::DependencyUnavailableError => e
      dependency_unavailable_alert(e)
    end
  end
end
