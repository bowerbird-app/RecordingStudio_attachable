# frozen_string_literal: true

namespace :flat_pack do
  desc "Mirror FlatPack component sources into tmp for Tailwind scanning"
  task :sync_tailwind_sources do
    require "fileutils"

    flat_pack_spec = Gem::Specification.find_by_name("flat_pack")
    source_path = Pathname.new(flat_pack_spec.gem_dir).join("app/components")
    target_path = Rails.root.join("tmp/tailwind/flat_pack_components")

    FileUtils.rm_rf(target_path)
    FileUtils.mkdir_p(target_path.dirname)
    FileUtils.cp_r(source_path, target_path)
  end
end

%w[tailwindcss:build tailwindcss:watch].each do |task_name|
  Rake::Task[task_name].enhance(["flat_pack:sync_tailwind_sources"]) if Rake::Task.task_defined?(task_name)
end