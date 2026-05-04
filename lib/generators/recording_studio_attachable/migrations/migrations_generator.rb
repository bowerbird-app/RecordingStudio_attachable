# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

module RecordingStudioAttachable
  module Generators
    class MigrationsGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration

      source_root File.expand_path("../../../..", __dir__)

      desc "Copy RecordingStudioAttachable migrations to your application"

      def copy_migrations
        Dir.glob(File.join(self.class.source_root, "db/migrate/*.rb")).sort.each do |source_path|
          migration_name = File.basename(source_path).sub(/^\d+_/, "")
          destination_filename = "#{next_migration_number}_#{migration_name}"
          copy_file source_path, File.join("db/migrate", destination_filename)
          sleep 0.1
        end
      end

      private

      def next_migration_number
        ActiveRecord::Migration.next_migration_number(Time.now.utc.strftime("%Y%m%d%H%M%S"))
      end
    end
  end
end
