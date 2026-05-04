# frozen_string_literal: true

module RecordingStudioAttachable
  class ApplicationController < (defined?(::ApplicationController) ? ::ApplicationController : ActionController::Base)
    protect_from_forgery with: :exception

    rescue_from RecordingStudioAttachable::Authorization::NotAuthorizedError, with: :handle_not_authorized
    rescue_from ActiveRecord::RecordNotFound, with: :handle_record_not_found

    helper_method :current_attachable_actor

    private

    def current_attachable_actor
      return Current.actor if defined?(Current) && Current.respond_to?(:actor)
      return current_user if respond_to?(:current_user, true)

      nil
    end

    def find_recording(id = params[:recording_id])
      RecordingStudio::Recording.find(id)
    end

    def find_attachment_recording(id = params[:id])
      RecordingStudio::Recording.find(id)
    end

    def authorize_attachment_action!(action, recording, capability_options: {})
      RecordingStudioAttachable::Authorization.authorize!(
        action: action,
        actor: current_attachable_actor,
        recording: recording,
        capability_options: capability_options
      )
    end

    def handle_not_authorized(exception)
      respond_to do |format|
        format.html do
          redirect_back fallback_location: main_app.root_path, alert: exception.message
        end
        format.json { render json: { error: exception.message }, status: :forbidden }
      end
    end

    def handle_record_not_found
      respond_to do |format|
        format.html do
          redirect_back fallback_location: main_app.root_path, alert: "Attachment resource not found"
        end
        format.json { render json: { error: "Not found" }, status: :not_found }
      end
    end
  end
end
