# frozen_string_literal: true

module RecordingStudioAttachable
  class ClientWiringDiagnostics
    def initialize(root: Rails.root)
      @root = root
    end

    def call
      [importmap_check, active_storage_javascript_check, stimulus_controllers_check]
    end

    private

    attr_reader :root

    def importmap_check
      path = root.join("config/importmap.rb")
      return warn_check("Importmap entries", "Importmap is not used") unless path.exist?

      source = path.read
      required = ["@rails/activestorage", "controllers/recording_studio_attachable"]
      missing = required.reject { |entry| source.include?(entry) }

      return pass_check("Importmap entries") if missing.empty?

      warn_check("Importmap entries", "missing #{missing.join(', ')}")
    end

    def active_storage_javascript_check
      path = root.join("app/javascript/application.js")
      return warn_check("Active Storage JavaScript startup", "could not be inspected") unless path.exist?

      source = path.read
      wired = source.include?("@rails/activestorage") && source.match?(/ActiveStorage\.start\(\)/)
      return pass_check("Active Storage JavaScript startup") if wired

      warn_check("Active Storage JavaScript startup", "could not detect ActiveStorage.start()")
    end

    def stimulus_controllers_check
      path = root.join("app/javascript/controllers/index.js")
      return warn_check("Attachable Stimulus controllers", "could not be inspected") unless path.exist?

      return pass_check("Attachable Stimulus controllers") if path.read.include?("controllers/recording_studio_attachable")

      warn_check("Attachable Stimulus controllers", "could not detect engine controller wiring")
    end

    def pass_check(label)
      EnvironmentDoctor::Check.new(status: :pass, label: label, detail: nil)
    end

    def warn_check(label, detail)
      EnvironmentDoctor::Check.new(status: :warn, label: label, detail: detail)
    end
  end
end
