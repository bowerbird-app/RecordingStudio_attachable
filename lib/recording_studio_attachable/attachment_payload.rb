# frozen_string_literal: true

require "uri"

module RecordingStudioAttachable
  module AttachmentPayload
    module_function

    def build(recording, actor:, url_mode: nil, rails_url: nil)
      attachment = recording.recordable
      urls = { file: file_url(recording, attachment, actor: actor, url_mode: url_mode, rails_url: rails_url) }
      absolute = absolute_file_url(recording, actor: actor, url_mode: url_mode, rails_url: rails_url)
      urls[:file_url] = absolute if absolute.present?
      {
        id: recording.id,
        kind: attachment.attachment_kind,
        name: attachment.name,
        urls: urls
      }
    end

    def file_url(recording, attachment, actor:, url_mode:, rails_url:)
      return unless Authorization.allowed?(action: :view, actor: actor, recording: recording)

      attachment.original_url(mode: url_mode, rails_url: rails_path(recording, rails_url))
    end

    def absolute_file_url(recording, actor:, url_mode:, rails_url:)
      return unless rails_delivery?(url_mode)
      return unless Authorization.allowed?(action: :view, actor: actor, recording: recording)

      path = rails_path(recording, rails_url)
      origin = public_origin
      return if origin.blank? || path.blank? || path.include?("://")

      "#{origin.chomp('/')}#{path.start_with?('/') ? path : "/#{path}"}"
    end

    def rails_delivery?(url_mode)
      RecordingStudioAttachable.configuration.resolve_url_mode(url_mode) == :rails
    end

    def public_origin
      configured = origin_from(RecordingStudioAttachable.configuration.public_url_host)
      return configured if configured

      origin_from_options(inherited_url_options)
    end

    def inherited_url_options
      options = route_url_options
      return options if options[:host].present?

      mailer_url_options
    end

    def route_url_options
      return {} unless rails_app

      raw = rails_app.routes.default_url_options if rails_app.routes.respond_to?(:default_url_options)
      raw.respond_to?(:to_h) ? raw.to_h.symbolize_keys : {}
    end

    def mailer_url_options
      return {} unless rails_app

      mailer = rails_app.config.action_mailer.default_url_options
      return {} if mailer.blank?

      mailer.to_h.symbolize_keys
    end

    def rails_app
      return unless defined?(Rails) && Rails.respond_to?(:application)

      Rails.application
    end

    def origin_from_options(options)
      host = options.to_h.symbolize_keys[:host].presence
      return if host.blank?

      protocol = options[:protocol].presence || "https"
      protocol = protocol.to_s.delete_suffix("://")
      port = options[:port]
      standard = protocol == "http" ? 80 : 443
      suffix = port.present? && port.to_i != standard ? ":#{port}" : ""
      "#{protocol}://#{host}#{suffix}"
    end

    def origin_from(value)
      text = value.to_s.strip
      return if text.blank?

      text = "https://#{text}" unless text.include?("://")
      uri = URI.parse(text)
      return if uri.host.blank?

      "#{uri.scheme}://#{uri.host}#{port_suffix(uri)}"
    rescue URI::InvalidURIError
      nil
    end

    def port_suffix(uri)
      standard = uri.scheme == "http" ? 80 : 443
      return "" if uri.port.nil? || uri.port == standard

      ":#{uri.port}"
    end

    def rails_path(recording, rails_url)
      return rails_url if rails_url.present?

      Engine.routes.url_helpers.attachment_file_path(recording)
    end
  end
end
