# frozen_string_literal: true

require_relative "lib/recording_studio_attachable/version"

Gem::Specification.new do |spec|
  spec.name        = "recording_studio_attachable"
  spec.version     = RecordingStudioAttachable::VERSION
  spec.authors     = ["Bowerbird"]
  spec.homepage    = "https://github.com/bowerbird-app/RecordingStudio_attachable"
  spec.summary     = "Optional Recording Studio addon for child attachment recordings"
  spec.description = "Reusable Recording Studio addon for uploading and managing files and images as child recordings"
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  spec.add_dependency "rails", "~> 8.1.0"
end
