# frozen_string_literal: true

require "yaml"
require_relative "simplecov_helper"
require "minitest/autorun"

class RenameVerificationTest < Minitest::Test
  def setup
    @root = File.expand_path("..", __dir__)
    @gem_name = detect_gem_name
    @pascal_name = to_pascal_case(@gem_name)
  end

  def test_gemspec_file_exists
    assert File.exist?(File.join(@root, "#{@gem_name}.gemspec"))
  end

  def test_main_lib_file_exists
    assert File.exist?(File.join(@root, "lib", "#{@gem_name}.rb"))
  end

  def test_version_and_engine_files_exist
    assert File.exist?(File.join(@root, "lib", @gem_name, "version.rb"))
    assert File.exist?(File.join(@root, "lib", @gem_name, "engine.rb"))
  end

  def test_namespace_matches_detected_name
    lib_source = File.read(File.join(@root, "lib", "#{@gem_name}.rb"))
    engine_source = File.read(File.join(@root, "lib", @gem_name, "engine.rb"))

    assert_includes lib_source, "module #{@pascal_name}"
    assert_includes engine_source, "module #{@pascal_name}"
    assert_includes engine_source, "isolate_namespace #{@pascal_name}"
  end

  def test_old_template_directories_are_gone
    refute Dir.exist?(File.join(@root, "lib", "gem_template"))
    refute Dir.exist?(File.join(@root, "app", "controllers", "gem_template"))
    refute Dir.exist?(File.join(@root, "app", "views", "gem_template"))
  end

  private

  def detect_gem_name
    gemspec = Dir.glob(File.join(@root, "*.gemspec")).first
    File.basename(gemspec, ".gemspec")
  end

  def to_pascal_case(value)
    value.split("_").map(&:capitalize).join
  end
end
