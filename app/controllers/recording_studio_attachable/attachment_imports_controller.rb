# frozen_string_literal: true

require_relative "../../services/recording_studio_attachable/services/import_attachment_payloads"

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
      RecordingStudioAttachable::Services::ImportAttachmentPayloads.call(
        parent_recording: @recording,
        actor: current_attachable_actor,
        impersonator: current_attachable_impersonator,
        attachments: attachment_payloads,
        context: self
      )
    rescue ArgumentError => e
      RecordingStudioAttachable::Services::BaseService::Result.new(success: false, error: e.message)
    end

    def attachment_payloads
      default_provider_key = attachment_import_params[:provider_key].presence
      permitted = attachment_import_params.permit(
        :provider_key,
        attachments: [
          :provider_key,
          :signed_blob_id,
          :name,
          :description,
          :filename,
          :content_type,
          :identify,
          :file,
          { metadata: {} },
          { provider_payload: {} }
        ]
      )

      Array(permitted.fetch(:attachments, [])).map do |attachment|
        normalize_attachment_payload(attachment.to_h.symbolize_keys, default_provider_key: default_provider_key)
      end
    end

    def normalize_attachment_payload(payload, default_provider_key: nil)
      uploaded_file = payload.delete(:file)
      payload.delete(:source)
      payload.delete(:service_name)
      payload[:provider_key] = payload[:provider_key].presence || default_provider_key
      if payload[:provider_key].present? && registered_provider(payload[:provider_key]).blank?
        raise ArgumentError,
              "Unknown upload provider"
      end

      payload[:metadata] = normalized_metadata(payload[:metadata], provider_key: payload[:provider_key])
      payload[:provider_payload] = normalized_provider_payload(payload[:provider_payload], provider_key: payload[:provider_key])
      payload[:identify] = ActiveModel::Type::Boolean.new.cast(payload[:identify]) if payload.key?(:identify)

      return payload unless uploaded_file.present?

      payload[:io] = uploaded_file.tempfile
      payload[:filename] = payload[:filename].presence || uploaded_file.original_filename
      payload[:content_type] = payload[:content_type].presence || uploaded_file.content_type
      payload
    end

    def normalized_metadata(metadata, provider_key: nil)
      normalized = metadata.respond_to?(:to_h) ? metadata.to_h : {}
      normalized = normalized.except("provider", :provider)
      return normalized if provider_key.blank?

      normalized.merge("provider" => import_source_for(provider_key))
    end

    def normalized_provider_payload(provider_payload, provider_key: nil)
      return nil if provider_payload.blank?
      return nil if provider_key.blank?
      raise ArgumentError, "Unknown upload provider" if registered_provider(provider_key).blank?

      provider_payload.to_h.compact_blank
    end

    def registered_provider(provider_key)
      return if provider_key.blank?

      RecordingStudioAttachable.configuration.upload_provider(provider_key)
    end

    def import_source_for(provider_key)
      registered_provider(provider_key)&.key&.to_s || "provider_import"
    end

    def attachment_import_params
      params.fetch(:attachment_import, ActionController::Parameters.new)
    end

    def attachment_json(recording)
      attachment = recording.recordable
      insert_url = authorized_attachment_file_path(recording)

      {
        id: recording.id,
        name: attachment.name,
        description: attachment.description,
        content_type: attachment.content_type,
        byte_size: attachment.byte_size,
        attachment_kind: attachment.attachment_kind,
        thumbnail_url: authorized_attachment_preview_path(recording, :square_small) || insert_url,
        insert_url: insert_url,
        variant_urls: authorized_attachment_inline_variant_urls(recording),
        alt: attachment.name,
        show_path: attachment_path(recording)
      }
    end
  end
end
