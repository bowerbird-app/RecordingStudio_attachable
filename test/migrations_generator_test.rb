# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"
require "generators/recording_studio_attachable/migrations/migrations_generator"

class MigrationsGeneratorTest < Minitest::Test
  def test_copy_migrations_stamps_each_file_one_second_apart
    previous = ActiveRecord.timestamped_migrations
    ActiveRecord.timestamped_migrations = true

    Dir.mktmpdir do |dir|
      generator = RecordingStudioAttachable::Generators::MigrationsGenerator.new([], {}, destination_root: dir)
      generator.copy_migrations

      stamps = Dir[File.join(dir, "db/migrate/*.rb")].map { |path| File.basename(path)[/\A\d{14}/] }.sort
      sources = Dir[File.expand_path("../db/migrate/*.rb", __dir__)]

      assert_equal sources.size, stamps.size
      assert_operator stamps.size, :>, 1
      stamps.each_cons(2) do |left, right|
        assert_equal stamp_time(left) + 1, stamp_time(right)
      end
    end
  ensure
    ActiveRecord.timestamped_migrations = previous
  end

  private

  def stamp_time(number)
    Time.utc(
      number[0, 4].to_i, number[4, 2].to_i, number[6, 2].to_i,
      number[8, 2].to_i, number[10, 2].to_i, number[12, 2].to_i
    )
  end
end
