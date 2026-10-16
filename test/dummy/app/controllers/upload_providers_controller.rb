# frozen_string_literal: true

require "base64"

class UploadProvidersController < ApplicationController
  def show
    @recording = find_recording
  end

  def create
    @recording = find_recording
    result = RecordingStudioAttachable::Services::ImportAttachment.call(
      parent_recording: @recording,
      io: StringIO.new(demo_cloud_png),
      filename: "demo-cloud-import.png",
      content_type: "image/png",
      actor: Current.actor,
      impersonator: Current.impersonator,
      name: "Demo cloud import",
      description: "Imported through the dummy upload provider reference flow",
      source: "demo_cloud",
      metadata: { provider: "demo_cloud", demo: true }
    )

    if result.success?
      redirect_to recording_studio_attachable.attachment_path(result.value), notice: "Imported demo attachment."
    else
      redirect_to demo_upload_provider_path(recording_id: @recording.id), alert: result.error
    end
  end

  private

  def find_recording
    RecordingStudio::Recording.find(params[:recording_id])
  end

  def demo_cloud_png
    Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")
  end
end
