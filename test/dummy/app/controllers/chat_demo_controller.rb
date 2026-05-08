# frozen_string_literal: true

class ChatDemoController < ApplicationController
  before_action :set_workspace_context
  before_action :set_chat_thread_context

  def show
    @chat_threads = chat_threads
    @draft_message = current_draft_message
    @draft_attachments = attachment_recordings_for(@draft_message)
    @messages = persisted_messages
  end

  def create
    draft_message = find_draft_message!(chat_demo_params[:draft_message_id])
    body = chat_demo_params[:body].to_s.strip

    if body.blank? && draft_message.chat_message_attachments.empty?
      redirect_to chat_demo_path, alert: "Add a message or choose at least one image."
      return
    end

    send_draft_message!(draft_message, body.presence)

    redirect_to chat_demo_path
  end

  def attach_attachment
    draft_message = find_draft_message!(params[:id])
    attachment_recording = find_attachment_recording_for_message!(params[:attachment_recording_id])

    draft_message.chat_message_attachments.find_or_create_by!(attachment_recording: attachment_recording)

    render json: { ok: true, attachment_recording_id: attachment_recording.id }
  end

  def detach_attachment
    draft_message = find_draft_message!(params[:id])

    draft_message.chat_message_attachments.find_by!(attachment_recording_id: params[:attachment_recording_id]).destroy!

    head :no_content
  end

  def destroy
    reset_dynamic_messages!
    redirect_to chat_demo_path, notice: "Chat demo reset."
  end

  private

  def set_workspace_context
    @workspace = Workspace.first
    @root_recording = RecordingStudio::Recording.unscoped.find_by(
      recordable: @workspace,
      parent_recording_id: nil
    )
    return if @root_recording.blank?

    @chat_attachment_picker_path = recording_studio_attachable.recording_attachment_picker_path(
      @root_recording,
      scope: :subtree
    )
    @chat_attachment_create_path = recording_studio_attachable.recording_attachments_path(
      @root_recording,
      redirect_mode: "return_to",
      return_to: chat_demo_path
    )
    @chat_attachment_upload_path = recording_studio_attachable.recording_attachment_upload_path(
      @root_recording,
      redirect_mode: "return_to",
      return_to: chat_demo_path
    )
  end

  def set_chat_thread_context
    @chat_thread = ChatThread.order(:created_at, :id).first
    return if @chat_thread.blank? || @root_recording.blank?

    @chat_thread_recording = RecordingStudio::Recording.unscoped.find_or_create_by!(recordable: @chat_thread) do |recording|
      recording.root_recording_id = @root_recording.id
      recording.parent_recording_id = @root_recording.id
    end
  end

  def chat_threads
    return [] if @chat_thread.blank?

    [ build_chat_thread(@chat_thread) ]
  end

  def build_chat_thread(chat_thread)
    latest_message = chat_thread.latest_message

    {
      chat_group_name: chat_thread.title,
      avatar_items: [ { initials: "RS" } ],
      latest_sender: latest_message&.direction == "outgoing" ? "You" : "Attachable",
      latest_preview: latest_message&.body.presence || "Reuse the picker inside the composer.",
      latest_at: latest_message&.timestamp || chat_thread.created_at,
      unread_count: 0,
      active: true
    }
  end

  def persisted_messages
    return [] if @chat_thread.blank?

    @chat_thread.chat_messages
      .sent
      .timeline_order
      .includes(chat_message_attachments: { attachment_recording: { recordable: [ { file_attachment: :blob } ] } })
      .to_a
  end

  def current_draft_message
    return if @chat_thread.blank?

    @current_draft_message ||= @chat_thread.chat_messages.drafts.order(:created_at, :id).first || create_draft_message!
  end

  def chat_demo_params
    params.fetch(:chat_demo, ActionController::Parameters.new).permit(:body, :draft_message_id)
  end

  def create_draft_message!
    draft_message = @chat_thread.chat_messages.create!(
      body: nil,
      direction: "outgoing",
      position: next_message_position,
      status: "draft"
    )
    ensure_message_recording!(draft_message)
    draft_message
  end

  def next_message_position
    @chat_thread.chat_messages.maximum(:position).to_i + 1
  end

  def ensure_message_recording!(message)
    return if @chat_thread_recording.blank?

    RecordingStudio::Recording.unscoped.find_or_create_by!(recordable: message) do |recording|
      recording.root_recording_id = @root_recording.id
      recording.parent_recording_id = @chat_thread_recording.id
    end
  end

  def find_draft_message!(id)
    message = @chat_thread.chat_messages.drafts.find(id)
    ensure_message_recording!(message)
    message
  end

  def send_draft_message!(draft_message, body)
    draft_message.class.transaction do
      attachment_recordings = draft_message.attachment_recordings.to_a
      position = draft_message.position
      direction = draft_message.direction

      destroy_message!(draft_message)

      sent_message = draft_message.chat_thread.chat_messages.new(
        body: body,
        direction: direction,
        position: position,
        status: "sent",
        sent_at: Time.current
      )

      attachment_recordings.each do |attachment_recording|
        sent_message.chat_message_attachments.build(attachment_recording: attachment_recording)
      end

      sent_message.save!
      ensure_message_recording!(sent_message)
      sent_message
    end
  end

  def attachment_recordings_for(message)
    return [] if message.blank?

    message.attachment_recordings.includes(recordable: [ { file_attachment: :blob } ]).to_a
  end

  def find_attachment_recording_for_message!(id)
    RecordingStudio::Recording.unscoped.find_by!(id: id, recordable_type: "RecordingStudioAttachable::Attachment")
  end

  def reset_dynamic_messages!
    return if @chat_thread.blank?

    @chat_thread.chat_messages.where(seeded: false).find_each do |message|
      destroy_message!(message)
    end
  end

  def destroy_message!(message)
    message.chat_message_attachments.delete_all
    RecordingStudio::Recording.unscoped.where(recordable: message).delete_all
    message.delete
  end
end
