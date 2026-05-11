# frozen_string_literal: true

require "uri"

module RecordingStudioAttachable
  class ApplicationController < (defined?(::ApplicationController) ? ::ApplicationController : ActionController::Base)
    PROVIDER_EVENT_STORAGE_KEY = "recording-studio-attachable:provider-event"

    protect_from_forgery with: :exception
    layout :recording_studio_attachable_layout

    rescue_from RecordingStudioAttachable::Authorization::NotAuthorizedError, with: :handle_not_authorized
    rescue_from ActiveRecord::RecordNotFound, with: :handle_record_not_found

    helper_method :current_attachable_actor
    helper_method :embedded_upload_provider_request?
    helper_method :attachment_redirect_params
    helper_method :authorized_attachment_file_path
    helper_method :authorized_attachment_preview_path

    private

    def current_attachable_actor
      return Current.actor if defined?(Current) && Current.respond_to?(:actor)
      return current_user if respond_to?(:current_user, true)

      nil
    end

    def current_attachable_impersonator
      return Current.impersonator if defined?(Current) && Current.respond_to?(:impersonator)

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
          redirect_back_or_to(main_app.root_path, alert: exception.message)
        end
        format.json { render json: { error: exception.message }, status: :forbidden }
      end
    end

    def handle_record_not_found
      respond_to do |format|
        format.html do
          redirect_back_or_to(main_app.root_path, alert: "Attachment resource not found")
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

    def configured_upload_providers(recording)
      RecordingStudioAttachable.configuration.upload_providers.select do |provider|
        provider.render?(view_context: view_context, recording: recording)
      end
    end

    def authorized_attachment_file_path(recording)
      attachment_file_path(recording)
    end

    def authorized_attachment_preview_path(recording, variant_name)
      attachment = recording&.recordable
      return if attachment.blank?
      return unless attachment.respond_to?(:preview_target_named)
      return if attachment.preview_target_named(variant_name).blank?

      attachment_preview_file_path(recording, variant_name: variant_name)
    end

    def authorized_attachment_inline_variant_urls(recording)
      original_url = authorized_attachment_file_path(recording)

      {
        small: authorized_attachment_preview_path(recording, :small) || original_url,
        medium: authorized_attachment_preview_path(recording, :med) || original_url,
        large: authorized_attachment_preview_path(recording, :large) || original_url
      }
    end

    def attachment_redirect_params(fallback_return_to: nil)
      mode = params[:redirect_mode].to_s.presence
      return {} if mode.blank?

      return_to = params[:return_to].presence
      return_to = fallback_return_to if mode == "referer" && return_to.blank?

      {
        redirect_mode: mode,
        return_to: validated_local_redirect_target(return_to)
      }.compact_blank
    end

    def upload_provider_request_params
      {
        embed: (embedded_upload_provider_request? ? "modal" : nil),
        provider_key: current_upload_provider_key,
        provider_modal_id: current_upload_provider_modal_id
      }.compact
    end

    def upload_flow_params(fallback_return_to: nil)
      upload_provider_request_params.merge(attachment_redirect_params(fallback_return_to: fallback_return_to))
    end

    def resolved_attachment_redirect_path(recording)
      redirect_params = attachment_redirect_params

      case redirect_params[:redirect_mode]
      when "return_to", "referer"
        redirect_params[:return_to] || default_attachment_redirect_path(recording)
      else
        default_attachment_redirect_path(recording)
      end
    end

    def default_attachment_redirect_path(recording)
      return recording_studio_attachable.recording_attachments_path(recording) if respond_to?(:recording_studio_attachable, true)

      recording_attachments_path(recording)
    end

    def recording_studio_attachable_layout
      configured_layout = RecordingStudioAttachable.configuration.layout
      return "recording_studio_attachable/blank" if configured_layout.blank?

      normalized_layout = configured_layout.to_s
      return "recording_studio_attachable/blank" if %w[blank blank_upload recording_studio_attachable/blank].include?(normalized_layout)

      normalized_layout
    end

    def embedded_upload_provider_request?
      params[:embed].to_s == "modal"
    end

    def current_upload_provider_key
      params[:provider_key].presence
    end

    def current_upload_provider_modal_id
      params[:provider_modal_id].presence
    end

    def render_upload_provider_modal_event(type:, redirect_path: nil, reload_url: nil, provider_key: current_upload_provider_key,
                                           modal_id: current_upload_provider_modal_id, close_window: false, status: :ok)
      payload = {
        namespace: "recording-studio-attachable",
        type: type,
        providerKey: provider_key,
        modalId: modal_id,
        redirectPath: redirect_path,
        reloadUrl: reload_url
      }.compact
      payload_json = ERB::Util.json_escape(payload.to_json)

      render html: <<~HTML.html_safe, layout: false, status: status
        <!DOCTYPE html>
        <html>
          <head>
            <meta charset="utf-8">
            <title>Recording Studio Attachable</title>
          </head>
          <body>
            <script>
              (() => {
                const payload = JSON.parse("#{payload_json}");
                const storageKey = "#{PROVIDER_EVENT_STORAGE_KEY}";
                const channelName = `${storageKey}:channel`;
                const targets = [];

                if (window.opener) targets.push(window.opener);
                if (window.parent && window.parent !== window) targets.push(window.parent);

                targets.forEach((target) => {
                  try {
                    target.postMessage(payload, window.location.origin);
                  } catch (_error) {
                  }
                });

                try {
                  window.localStorage.setItem(storageKey, JSON.stringify({ payload, sentAt: Date.now() }));
                } catch (_error) {
                }

                if (window.BroadcastChannel) {
                  try {
                    const channel = new window.BroadcastChannel(channelName);
                    channel.postMessage(payload);
                    channel.close();
                  } catch (_error) {
                  }
                }

                #{'window.close();' if close_window}
              })();
            </script>
            <p>Returning to the upload page…</p>
          </body>
        </html>
      HTML
    end

    def validated_local_redirect_target(target)
      return if target.blank?

      uri = URI.parse(target.to_s)
      return unless valid_local_redirect_uri?(uri)

      [uri.path, uri.query.presence && "?#{uri.query}", uri.fragment.presence && "##{uri.fragment}"].compact.join
    rescue URI::InvalidURIError
      nil
    end

    def valid_local_redirect_uri?(uri)
      return false unless uri.path&.start_with?("/")
      return false if uri.host.present? && !same_origin_redirect_uri?(uri)
      return false if uri.scheme.present? && !same_origin_redirect_uri?(uri)

      true
    end

    def same_origin_redirect_uri?(uri)
      base_uri = URI.parse(request.base_url)
      uri.scheme == base_uri.scheme && uri.host == base_uri.host && uri.port == base_uri.port
    rescue URI::InvalidURIError
      false
    end
  end
end
