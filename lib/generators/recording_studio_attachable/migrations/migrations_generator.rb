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
        @migration_stamp = Time.now.utc
        Dir[File.join(self.class.source_root, "db/migrate/*.rb")].each do |source_path|
          migration_name = File.basename(source_path).sub(/^\d+_/, "")
          destination_filename = "#{next_migration_number}_#{migration_name}"
          copy_file source_path, File.join("db/migrate", destination_filename)
          @migration_stamp += 1
        end
      end

      private

      def next_migration_number
        formatted = @migration_stamp.strftime("%Y%m%d%H%M%S")
        return formatted if ActiveRecord.timestamped_migrations

        ActiveRecord::Migration.next_migration_number(formatted)
      end
    end
  end
end
