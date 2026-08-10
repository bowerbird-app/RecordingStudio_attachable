# frozen_string_literal: true

module RecordingStudioAttachable
  class EnvironmentDoctor
    Check = Data.define(:status, :label, :detail) do
      def required_failure?
        status == :fail
      end
    end

    class Result
      attr_reader :checks

      def initialize(checks)
        @checks = checks
      end

      def success?
        checks.none?(&:required_failure?)
      end
    end

    class << self
      def call(io: $stdout)
        new(io: io).call
      end
    end

    def initialize(io:)
      @io = io
    end

    def call
      checks = server_checks + client_checks
      checks.each { |check| print_check(check) }
      Result.new(checks)
    end

    private

    attr_reader :io

    def server_checks
      return [fail_check("Active Storage", "is not loaded")] unless defined?(ActiveStorage::Blob)

      diagnostic = ImageProcessorDiagnostics.call

      [
        pass_check("Active Storage", "loaded"),
        active_storage_service_check,
        processor_check(diagnostic),
        transformation_check(diagnostic),
        engine_mount_check,
        direct_upload_routes_check
      ]
    end

    def active_storage_service_check
      configured_service = Rails.application.config.active_storage.service
      ActiveStorage::Blob.service

      pass_check("Active Storage service", configured_service.presence || "configured")
    rescue StandardError => error
      fail_check("Active Storage service", safe_error(error))
    end

    def processor_check(diagnostic)
      if diagnostic.success? || diagnostic.stage == :transformation
        pass_check("Variant processor", diagnostic.processor)
      else
        fail_check("Variant processor", "#{diagnostic.processor}: #{diagnostic.error}")
      end
    end

    def transformation_check(diagnostic)
      return pass_check("Image transformation") if diagnostic.success?

      fail_check("Image transformation", diagnostic.error)
    end

    def engine_mount_check
      mounted = Rails.application.routes.routes.any? do |route|
        mounted_app(route.app) == RecordingStudioAttachable::Engine
      end

      mounted ? pass_check("Attachable engine route") : fail_check("Attachable engine route", "not mounted")
    end

    def mounted_app(app)
      5.times do
        return app unless app.respond_to?(:app)

        nested_app = app.app
        return app if nested_app.equal?(app)

        app = nested_app
      end
      app
    end

    def direct_upload_routes_check
      named_routes = Rails.application.routes.named_routes
      available = named_routes.route_defined?(:rails_direct_uploads)

      available ? pass_check("Active Storage direct-upload routes") : fail_check(
        "Active Storage direct-upload routes",
        "rails_direct_uploads is unavailable"
      )
    end

    def client_checks
      [importmap_check, active_storage_javascript_check, stimulus_controllers_check]
    end

    def importmap_check
      path = Rails.root.join("config/importmap.rb")
      return warn_check("Importmap entries", "Importmap is not used") unless path.exist?

      source = path.read
      required = ["@rails/activestorage", "controllers/recording_studio_attachable"]
      missing = required.reject { |entry| source.include?(entry) }

      missing.empty? ? pass_check("Importmap entries") : warn_check("Importmap entries", "missing #{missing.join(", ")}")
    end

    def active_storage_javascript_check
      path = Rails.root.join("app/javascript/application.js")
      return warn_check("Active Storage JavaScript startup", "could not be inspected") unless path.exist?

      source = path.read
      wired = source.include?("@rails/activestorage") && source.match?(/ActiveStorage\.start\(\)/)

      wired ? pass_check("Active Storage JavaScript startup") : warn_check(
        "Active Storage JavaScript startup",
        "could not detect ActiveStorage.start()"
      )
    end

    def stimulus_controllers_check
      path = Rails.root.join("app/javascript/controllers/index.js")
      return warn_check("Attachable Stimulus controllers", "could not be inspected") unless path.exist?

      if path.read.include?("controllers/recording_studio_attachable")
        pass_check("Attachable Stimulus controllers")
      else
        warn_check("Attachable Stimulus controllers", "could not detect engine controller wiring")
      end
    end

    def pass_check(label, detail = nil)
      Check.new(status: :pass, label: label, detail: detail)
    end

    def fail_check(label, detail)
      Check.new(status: :fail, label: label, detail: detail)
    end

    def warn_check(label, detail)
      Check.new(status: :warn, label: label, detail: detail)
    end

    def print_check(check)
      suffix = check.detail.present? ? ": #{check.detail}" : ""
      io.puts "#{check.status.to_s.upcase} #{check.label}#{suffix}"
    end

    def safe_error(error)
      "#{error.class}: #{error.message.to_s.gsub(/\s+/, " ").strip}"
    end
  end
end
