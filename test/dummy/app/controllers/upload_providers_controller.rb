# frozen_string_literal: true

class UploadProvidersController < ApplicationController
  def show
    @recording = find_recording
  end

  def create
    @recording = find_recording
    result = RecordingStudioAttachable::Services::ImportAttachment.call(
      parent_recording: @recording,
      io: StringIO.new(demo_cloud_svg),
      filename: "demo-cloud-import.svg",
      content_type: "image/svg+xml",
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

  def demo_cloud_svg
    <<~SVG
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 320 180" role="img" aria-labelledby="title desc">
        <title>Demo cloud import</title>
        <desc>A sample image imported through the dummy provider flow.</desc>
        <rect width="320" height="180" rx="24" fill="#F7F3E8" />
        <circle cx="88" cy="78" r="28" fill="#2E5E4E" />
        <path d="M36 138c18-34 41-51 70-51 24 0 43 11 57 33 10-10 23-15 38-15 31 0 52 16 63 48H36Z" fill="#D96C4D" />
        <path d="M116 52h88" stroke="#182126" stroke-width="10" stroke-linecap="round" />
        <path d="M116 82h120" stroke="#182126" stroke-width="10" stroke-linecap="round" opacity="0.72" />
        <path d="M116 112h64" stroke="#182126" stroke-width="10" stroke-linecap="round" opacity="0.48" />
      </svg>
    SVG
  end
end