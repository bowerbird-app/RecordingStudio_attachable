# frozen_string_literal: true

module RecordingStudioAttachable
  class ApplicationController < (defined?(::ApplicationController) ? ::ApplicationController : ActionController::Base)
    protect_from_forgery with: :exception
    layout :recording_studio_attachable_layout

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
      recording = RecordingStudio::Recording.find(id)
      raise ActiveRecord::RecordNotFound unless recording.recordable_type == "RecordingStudioAttachable::Attachment"

      recording
    end

    def authorize_attachment_action!(action, recording, capability_options: {})
      RecordingStudioAttachable::Authorization.authorize!(
        action: action,
        actor: current_attachable_actor,
        recording: recording,
        capability_options: capability_options
      )
    end

    def authorize_attachment_owner_action!(action, attachment_recording)
      authorize_attachment_action!(
        action,
        attachable_owner_recording(attachment_recording),
        capability_options: capability_options_for(attachment_recording)
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

    def attachable_owner_recording(recording)
      RecordingStudioAttachable::Authorization.owner_recording_for(recording)
    end

    def capability_options_for(recording)
      owner_type = RecordingStudioAttachable::Authorization.owner_type_for(recording)
      return {} if owner_type.blank? || !defined?(RecordingStudio)

      RecordingStudio.capability_options(:attachable, for_type: owner_type) || {}
    end

    def configured_attachable_option(recording, option_name)
      capability_options_for(recording).fetch(option_name) do
        RecordingStudioAttachable.configuration.public_send(option_name)
      end
    end

    def recording_studio_attachable_layout
      configured_layout = RecordingStudioAttachable.configuration.layout
      return "recording_studio_attachable/blank" if configured_layout.blank?

      normalized_layout = configured_layout.to_s
      return "recording_studio_attachable/blank" if %w[blank blank_upload recording_studio_attachable/blank].include?(normalized_layout)

      normalized_layout
    end
  end
end
