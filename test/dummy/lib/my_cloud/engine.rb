# frozen_string_literal: true

require "pathname"

module MyCloud
  class Engine < ::Rails::Engine
    def self.find_root(_from)
      Pathname.new(File.expand_path(".", __dir__))
    end

    isolate_namespace MyCloud
    engine_name "my_cloud"
  end
end

ActiveSupport.on_load(:recording_studio_attachable) do
  RecordingStudioAttachable.register_adapter_routes(:my_cloud) do
    mount MyCloud::Engine, at: "/my_cloud", as: :my_cloud
  end
end
