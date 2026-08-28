# frozen_string_literal: true

module RecordingStudioAttachable
  class ParentAttachmentsController < ApplicationController
    def show
      @recording = find_recording
      authorize_attachment_action!(:view, @recording, capability_options: capability_options_for(@recording))

      @return_to = validated_local_redirect_target(params[:return_to].presence) || request.referer
      ParentAttachmentSlot.locals(recording: @recording, return_to: @return_to).each do |key, value|
        instance_variable_set(:"@#{key}", value)
      end
    end
  end
end
