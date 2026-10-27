# frozen_string_literal: true

# Sibling gems still declare recording_studio below 6. Widen that requirement
# when Bundler loads gemspecs so this app can resolve 6.1.0.
module WidenRecordingStudioRequirement
  def add_dependency(name, *requirements)
    requirements = [">= 6.1.0"] if name.to_s == "recording_studio" && requirements.none? { |requirement| requirement.to_s.include?("6") }

    super
  end
end

Gem::Specification.prepend(WidenRecordingStudioRequirement) unless Gem::Specification.ancestors.include?(WidenRecordingStudioRequirement)
