# frozen_string_literal: true

module RecordingStudioAttachable
  class AttachmentImportsController < ApplicationController
    def create
      @recording = find_recording
      capability_options = capability_options_for(@recording)

      authorize_attachment_action!(:upload, @recording, capability_options: capability_options)
      result = import_result

      respond_to do |format|
        format.html do
          if result.success?
            redirect_to resolved_attachment_redirect_path(@recording), notice: "Imported #{result.value.size} attachment(s)."
          else
            redirect_to recording_attachment_upload_path(@recording, attachment_redirect_params), alert: result.error
          end
        end
        format.json do
          if result.success?
            render json: {
              attachments: Array(result.value).map { |recording| attachment_json(recording) },
              redirect_path: resolved_attachment_redirect_path(@recording)
            }, status: :created
          else
            render json: { error: result.error, errors: result.errors }, status: :unprocessable_entity
          end
        end
      end
    end

    private

    def import_result
      return failure_result("Unknown upload provider") if provider_key.present? && registered_provider.blank?

      payloads = attachment_payloads
      return failure_result("No importable attachment payloads were provided") if payloads.blank?

      io_payloads = payloads.select { |payload| payload[:io].present? }
      blob_payloads = payloads.select { |payload| payload[:signed_blob_id].present? }

      if io_payloads.any? && blob_payloads.any?
        return failure_result("Attachment import payloads must all use either file uploads or signed_blob_id values")
      end

      if io_payloads.any?
        RecordingStudioAttachable::Services::ImportAttachments.call(
          parent_recording: @recording,
          actor: current_attachable_actor,
          impersonator: current_attachable_impersonator,
          attachments: io_payloads,
          source: import_source
        )
      elsif blob_payloads.any?
        RecordingStudioAttachable::Services::RecordAttachmentUploads.call(
          parent_recording: @recording,
          actor: current_attachable_actor,
          impersonator: current_attachable_impersonator,
          attachments: blob_payloads,
          default_source: import_source
        )
      else
        failure_result("No importable attachment payloads were provided")
      end
    end

    def failure_result(error)
      RecordingStudioAttachable::Services::BaseService::Result.new(success: false, error: error)
    end

    def provider_key
      attachment_import_params[:provider_key].presence
    end

    def registered_provider
      return if provider_key.blank?

      RecordingStudioAttachable.configuration.upload_provider(provider_key)
    end

    def import_source
      registered_provider&.key&.to_s || "provider_import"
    end

    def attachment_payloads
      permitted = attachment_import_params.permit(
        :provider_key,
        attachments: [
          :signed_blob_id,
          :name,
          :description,
          :filename,
          :content_type,
          :identify,
          :file,
          { metadata: {} }
        ]
      )

      Array(permitted.fetch(:attachments, [])).map do |attachment|
        normalize_attachment_payload(attachment.to_h.symbolize_keys)
      end
    end

    def normalize_attachment_payload(payload)
      uploaded_file = payload.delete(:file)
      payload.delete(:source)
      payload.delete(:service_name)
      payload[:metadata] = normalized_metadata(payload[:metadata])
      payload[:identify] = ActiveModel::Type::Boolean.new.cast(payload[:identify]) if payload.key?(:identify)

      return payload unless uploaded_file.present?

      payload[:io] = uploaded_file.tempfile
      payload[:filename] = payload[:filename].presence || uploaded_file.original_filename
      payload[:content_type] = payload[:content_type].presence || uploaded_file.content_type
      payload
    end

    def normalized_metadata(metadata)
      normalized = metadata.respond_to?(:to_h) ? metadata.to_h : {}
      normalized = normalized.except("provider", :provider)
      return normalized if provider_key.blank?

      normalized.merge("provider" => import_source)
    end

    def attachment_import_params
      params.fetch(:attachment_import, ActionController::Parameters.new)
    end

    def attachment_json(recording)
      {
        id: recording.id,
        name: recording.recordable.name,
        content_type: recording.recordable.content_type,
        byte_size: recording.recordable.byte_size,
        attachment_kind: recording.recordable.attachment_kind,
        show_path: attachment_path(recording)
      }
    end
  end
end
