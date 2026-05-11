# frozen_string_literal: true

require "uri"

module RecordingStudioAttachable
  class UploadProvider
    STRATEGIES = %i[link modal_page client_picker].freeze

    class RouteHelpersProxy
      def initialize(view_context)
        @view_context = view_context
      end

      def method_missing(name, *args, **kwargs, &)
        return @view_context.public_send(name, *args, **kwargs, &) if @view_context.respond_to?(name)

        return main_app.public_send(name, *args, **kwargs, &) if main_app.respond_to?(name)

        super
      end

      def respond_to_missing?(name, include_private = false)
        @view_context.respond_to?(name, include_private) || main_app.respond_to?(name, include_private) || super
      end

      private

      def main_app
        return unless @view_context.respond_to?(:main_app)

        @main_app ||= @view_context.main_app
      end
    end

    attr_reader :key, :label, :description, :icon, :style, :size, :strategy, :launcher, :modal_size,
                :remote_importer

    def initialize(key:, label:, url:, description: nil, icon: "cloud", style: :secondary, size: :md,
                   target: nil, visible: nil, strategy: :link, launcher: nil, bootstrap_url: nil,
                   import_url: nil, remote_importer: nil, presentation: nil, modal_title: nil, modal_size: :xl,
                   iframe_title: nil, **system_arguments)
      @key = key.to_sym
      @label = label
      @url = url
      @description = description
      @icon = icon
      @style = style.to_sym
      @size = size.to_sym
      @target = target
      @visible = visible
      normalized_strategy = (presentation || strategy).to_sym
      @strategy = normalized_strategy
      @launcher = launcher&.to_s
      @bootstrap_url = bootstrap_url
      @import_url = import_url
      @remote_importer = remote_importer
      @modal_title = modal_title
      @modal_size = modal_size.to_sym
      @iframe_title = iframe_title
      @system_arguments = system_arguments

      validate_strategy!
      validate_remote_importer!
    end

    def render?(view_context:, recording:)
      return false if launch_url(view_context:, recording:).blank?

      visible = resolve(@visible, view_context:, recording:)
      visible.nil? || !!visible
    end

    def button_options(view_context:, recording:, query_params: {})
      options = {
        text: label,
        style: style,
        size: size,
        icon: icon
      }

      if client_picker?
        options[:type] = "button"
        options[:data] = merged_data(
          action: "recording-studio-attachable--upload#launchProvider",
          provider_strategy: strategy,
          provider_key: key,
          provider_launcher: launcher,
          provider_bootstrap_url: resolved_bootstrap_url(view_context:, recording:, query_params: query_params),
          provider_import_url: resolved_import_url(view_context:, recording:, query_params: query_params)
        )
      elsif modal?
        options[:type] = "button"
        options[:data] = merged_data(
          action: "recording-studio-attachable--upload#launchProvider",
          provider_strategy: strategy,
          provider_key: key,
          modal_id: modal_id(recording: recording),
          provider_frame_url: modal_url(view_context:, recording:, query_params: query_params),
          provider_modal_id: modal_id(recording: recording)
        )
      else
        options[:url] = resolved_url(view_context:, recording:, query_params: query_params)
        options[:target] = resolve(@target, view_context:, recording:)
      end

      options.merge(non_data_system_arguments).compact
    end

    def modal?
      strategy == :modal_page
    end

    def client_picker?
      strategy == :client_picker
    end

    def supports_remote_imports?
      remote_importer.respond_to?(:call)
    end

    def modal_id(recording:)
      "recording-studio-attachable-provider-#{key}-#{recording.id}-modal"
    end

    def modal_title(view_context:, recording:)
      resolve(@modal_title, view_context:, recording:) || label
    end

    def iframe_title(view_context:, recording:)
      resolve(@iframe_title, view_context:, recording:) || "#{label} picker"
    end

    def import_remote_attachments(parent_recording:, attachments:, actor: nil, impersonator: nil, context: nil)
      raise ArgumentError, "Upload provider does not support remote imports" unless supports_remote_imports?

      call_importer(
        parent_recording: parent_recording,
        attachments: attachments,
        actor: actor,
        impersonator: impersonator,
        context: context
      )
    end

    private

    def validate_strategy!
      return if STRATEGIES.include?(strategy)

      raise ArgumentError, "Unknown upload provider strategy: #{strategy.inspect}"
    end

    def validate_remote_importer!
      return if remote_importer.nil? || remote_importer.respond_to?(:call)

      raise ArgumentError, "remote_importer must respond to #call"
    end

    def launch_url(view_context:, recording:, query_params: {})
      return resolved_bootstrap_url(view_context:, recording:, query_params: query_params) if client_picker?

      if modal?
        modal_url(view_context:, recording:, query_params: query_params)
      else
        resolved_url(view_context:, recording:, query_params: query_params)
      end
    end

    def resolved_url(view_context:, recording:, query_params: {})
      append_query_params(resolve(@url, view_context:, recording:), query_params)
    end

    def modal_url(view_context:, recording:, query_params: {})
      base_url = resolved_url(view_context:, recording:, query_params: query_params)
      return if base_url.blank?

      uri = URI.parse(base_url)
      params = URI.decode_www_form(uri.query.to_s)
      params.reject! { |key, _value| %w[embed provider_key provider_modal_id].include?(key) }
      params.push(
        %w[embed modal],
        ["provider_key", key.to_s],
        ["provider_modal_id", modal_id(recording: recording)]
      )
      uri.query = URI.encode_www_form(params)
      uri.to_s
    rescue URI::InvalidURIError
      separator = base_url.include?("?") ? "&" : "?"
      "#{base_url}#{separator}embed=modal&provider_key=#{key}&provider_modal_id=#{modal_id(recording: recording)}"
    end

    def resolved_bootstrap_url(view_context:, recording:, query_params: {})
      append_query_params(resolve(@bootstrap_url || @url, view_context:, recording:), query_params)
    end

    def resolved_import_url(view_context:, recording:, query_params: {})
      append_query_params(resolve(@import_url, view_context:, recording:), query_params)
    end

    def append_query_params(url, query_params)
      return url if url.blank?

      sanitized_params = query_params.to_h.compact_blank
      return url if sanitized_params.blank?

      uri = URI.parse(url)
      params = URI.decode_www_form(uri.query.to_s)
      params.reject! { |key, _value| sanitized_params.key?(key.to_sym) || sanitized_params.key?(key.to_s) }
      params.concat(sanitized_params.map { |key, value| [key.to_s, value] })
      uri.query = URI.encode_www_form(params)
      uri.to_s
    rescue URI::InvalidURIError
      separator = url.include?("?") ? "&" : "?"
      "#{url}#{separator}#{URI.encode_www_form(sanitized_params)}"
    end

    def merged_data(extra_data)
      system_data = @system_arguments.fetch(:data, {}).to_h.transform_keys(&:to_sym)
      merged = system_data.merge(extra_data)
      merged[:action] = [system_data[:action], extra_data[:action]].compact.join(" ").strip.presence if extra_data[:action].present?
      merged
    end

    def non_data_system_arguments
      @system_arguments.except(:data)
    end

    def call_importer(parent_recording:, attachments:, actor:, impersonator:, context:)
      kwargs = {
        parent_recording: parent_recording,
        attachments: attachments,
        actor: actor,
        impersonator: impersonator,
        context: context
      }
      parameters = @remote_importer.parameters

      return @remote_importer.call(**kwargs) if parameters.any? { |type, _name| type == :keyrest }

      keyword_names = parameters.filter_map do |type, name|
        name if %i[key keyreq].include?(type)
      end
      return @remote_importer.call(**kwargs.slice(*keyword_names)) if keyword_names.any?

      case @remote_importer.arity
      when 5
        @remote_importer.call(parent_recording, attachments, actor, impersonator, context)
      when 4
        @remote_importer.call(parent_recording, attachments, actor, impersonator)
      when 3
        @remote_importer.call(parent_recording, attachments, actor)
      when 2
        @remote_importer.call(parent_recording, attachments)
      when 1
        @remote_importer.call(parent_recording)
      else
        @remote_importer.call
      end
    end

    def resolve(value, view_context:, recording:)
      return value unless value.respond_to?(:call)

      route_helpers = RouteHelpersProxy.new(view_context)
      kwargs = { view_context: view_context, route_helpers: route_helpers, recording: recording }
      parameters = value.parameters

      return value.call(**kwargs) if parameters.any? { |type, _name| type == :keyrest }

      keyword_names = parameters.filter_map do |type, name|
        name if %i[key keyreq].include?(type)
      end
      return value.call(**kwargs.slice(*keyword_names)) if keyword_names.any?

      case value.arity
      when 2
        value.call(route_helpers, recording)
      when 1
        value.call(recording)
      else
        value.call
      end
    end
  end
end
