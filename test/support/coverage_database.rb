# frozen_string_literal: true

require "fileutils"
require "digest"

module CoverageDatabase
  class << self
    attr_accessor :real_models
  end

  URL = ENV.fetch(
    "DATABASE_URL",
    "postgres://postgres:postgres@localhost:5432/recording_studio_attachable_test"
  )

  def connect_coverage_database!
    install_real_active_storage!
    ActiveRecord::Base.establish_connection(URL)
    ActiveRecord::Base.connection
    RecordingStudioAttachable::Attachment.reset_column_information if defined?(RecordingStudioAttachable::Attachment)
    ActiveStorage::Blob.reset_column_information
    ActiveStorage::Attachment.reset_column_information
  end

  def install_real_active_storage!
    capture_real_models!
    return if @active_storage_swapped

    @previous_active_storage = {}
    CoverageDatabase.real_models.each do |name, real|
      current = ActiveStorage.const_get(name) if ActiveStorage.const_defined?(name, false)
      @previous_active_storage[name] = current
      next if current.equal?(real)

      ActiveStorage.send(:remove_const, name) if current
      ActiveStorage.const_set(name, real)
    end
    @active_storage_swapped = true
  end

  def restore_active_storage!
    return unless @active_storage_swapped

    @previous_active_storage.each do |name, previous|
      ActiveStorage.send(:remove_const, name) if ActiveStorage.const_defined?(name, false)
      ActiveStorage.const_set(name, previous) if previous
    end
    @active_storage_swapped = false
  end

  def capture_real_models!
    return if CoverageDatabase.real_models

    removed = {}
    %i[Blob Attachment VariantRecord].each do |name|
      next unless ActiveStorage.const_defined?(name, false)

      removed[name] = ActiveStorage.const_get(name)
      ActiveStorage.send(:remove_const, name)
    end
    load_active_storage_models!
    CoverageDatabase.real_models = {
      Blob: ActiveStorage::Blob,
      Attachment: ActiveStorage::Attachment,
      VariantRecord: ActiveStorage::VariantRecord
    }
    %i[Blob Attachment VariantRecord].each do |name|
      ActiveStorage.send(:remove_const, name) if ActiveStorage.const_defined?(name, false)
      ActiveStorage.const_set(name, removed[name]) if removed[name]
    end
  end

  def load_active_storage_models!
    root = Gem.loaded_specs.fetch("activestorage").full_gem_path
    require "active_storage/attached/model"
    require "active_storage/reflection"
    unless ActiveRecord::Reflection.singleton_class.ancestors.include?(ActiveStorage::Reflection::ReflectionExtension)
      ActiveRecord::Reflection.singleton_class.prepend(ActiveStorage::Reflection::ReflectionExtension)
    end
    unless ActiveRecord::Base.respond_to?(:attachment_reflections)
      ActiveRecord::Base.include(ActiveStorage::Reflection::ActiveRecordExtensions)
    end
    ActiveRecord::Base.include(ActiveStorage::Attached::Model) unless ActiveRecord::Base.respond_to?(:has_one_attached)

    require File.join(root, "app/models/active_storage/filename")
    require File.join(root, "app/models/active_storage/record")
    ActiveStorage.const_set(:Blob, Class.new(ActiveStorage::Record)) unless defined?(ActiveStorage::Blob)
    %w[analyzable identifiable representable servable].each do |name|
      require File.join(root, "app/models/active_storage/blob", name)
    end
    require File.join(root, "app/models/active_storage/blob")
    require File.join(root, "app/models/active_storage/attachment")
    require File.join(root, "app/models/active_storage/variant_record")
  end

  def with_disk_service
    install_real_active_storage!
    directory = Dir.mktmpdir("attachable-coverage")
    previous_services = ActiveStorage::Blob.services
    previous_service = ActiveStorage::Blob.service
    previous_verifier = ActiveStorage.verifier if ActiveStorage.respond_to?(:verifier)
    registry = ActiveStorage::Service::Registry.new(test: { service: "Disk", root: directory })
    ActiveStorage::Blob.services = registry
    ActiveStorage::Blob.service = registry.fetch(:test)
    ActiveStorage.verifier = ActiveSupport::MessageVerifier.new("attachable-coverage-secret")
    ActiveStorage::Blob.instance_variable_set(:@signed_id_verifier, nil)
    install_disk_routes!(ActiveStorage::Blob.service)
    yield
  ensure
    if defined?(previous_services) && ActiveStorage::Blob.respond_to?(:services=)
      ActiveStorage::Blob.services = previous_services
    end
    if defined?(previous_service) && ActiveStorage::Blob.respond_to?(:service=)
      ActiveStorage::Blob.service = previous_service
    end
    ActiveStorage.verifier = previous_verifier if defined?(previous_verifier)
    ActiveStorage::Blob.instance_variable_set(:@signed_id_verifier, nil) if defined?(ActiveStorage::Blob)
    FileUtils.rm_rf(directory) if directory
  end

  def install_disk_routes!(service)
    routes = ActionDispatch::Routing::RouteSet.new
    routes.draw do
      put "/disk/:encoded_token", to: "active_storage/disk#update", as: :update_rails_disk_service
    end
    routes.default_url_options[:host] = "example.com"
    helpers = routes.url_helpers
    service.define_singleton_method(:url_helpers) { helpers }
    service.define_singleton_method(:url_options) { { host: "example.com" } }
  end

  def checksum_for(bytes)
    Digest::MD5.base64digest(bytes)
  end
end
