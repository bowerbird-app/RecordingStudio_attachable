#!/usr/bin/env ruby
# frozen_string_literal: true

# Query count and median wall time for attachment read routes.
#
#   cd test/dummy
#   RAILS_ENV=test bundle exec ruby script/benchmark_attachment_reads.rb
#
# ITERATIONS (default 200) and WARMUP (default 20) control the sample.
# BENCH_OUT writes a JSON summary. The script always uses the test database.

ENV["RAILS_ENV"] = "test"

require_relative "../config/environment"
require "action_dispatch/testing/integration"

class AttachmentReadBenchmark
  PNG = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")
  HOOK = :attachable_available_for?

  Route = Struct.new(:name, :path, :format, keyword_init: true)

  class Client
    include Warden::Test::Helpers

    def initialize
      Warden.test_mode!
      @session = ActionDispatch::Integration::Session.new(Rails.application)
    end

    def sign_in(user)
      login_as(user, scope: :user)
    end

    def get(path, format:)
      @session.get(path, as: format)
      @session.response
    end
  end

  def initialize
    @iterations = Integer(ENV.fetch("ITERATIONS", "200"))
    @warmup = Integer(ENV.fetch("WARMUP", "20"))
    @client = Client.new
  end

  def run
    quiet_logs
    prepare_records
    rows = []
    rows.concat(sample("none"))
    define_hook
    rows.concat(sample("true"))
    report(rows)
  ensure
    remove_hook
  end

  private

  def quiet_logs
    Rails.logger.level = Logger::ERROR if Rails.logger
    ActiveRecord::Base.logger = nil
  end

  def prepare_records
    password = SecureRandom.hex(16)
    user = User.create!(
      email: "bench-#{SecureRandom.hex(4)}@example.com",
      password: password,
      password_confirmation: password,
      name: "Bench"
    )
    Current.actor = user
    workspace = Workspace.create!(name: "Bench #{SecureRandom.hex(4)}")
    @owner = RecordingStudio.create_root_recording!(workspace, actor: user)
    grant_access(user)
    @attachment = attach_image(user)
    process_preview
    @client.sign_in(user)
    @routes = routes_for(@owner.id, @attachment.id)
  end

  def grant_access(user)
    authorizer = RecordingStudioAccessible.configuration.access_management_authorizer
    RecordingStudioAccessible.configuration.access_management_authorizer = ->(**) { true }
    result = RecordingStudioAccessible.bootstrap_owner_access!(recording: @owner, actor: user)
    raise result.error if result.failure?
  ensure
    RecordingStudioAccessible.configuration.access_management_authorizer = authorizer
  end

  def attach_image(user)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(PNG),
      filename: "bench.png",
      content_type: "image/png"
    )
    attachment = RecordingStudioAttachable::Attachment.build_from_blob(
      blob: blob,
      name: "Bench",
      root_recording: @owner
    )
    RecordingStudio.record!(
      action: "attachment_uploaded",
      recordable: attachment,
      root_recording: @owner,
      parent_recording: @owner,
      actor: user
    ).recording
  end

  def process_preview
    target = @attachment.recordable.preview_target_named(:large)
    raise "preview target missing" if target.blank?

    target.processed
  end

  def routes_for(owner_id, attachment_id)
    prefix = "/recording_studio_attachable"
    [
      Route.new(name: "file", path: "#{prefix}/attachments/#{attachment_id}/file", format: nil),
      Route.new(name: "preview", path: "#{prefix}/attachments/#{attachment_id}/preview/large", format: nil),
      Route.new(name: "download", path: "#{prefix}/attachments/#{attachment_id}/download", format: nil),
      Route.new(name: "show", path: "#{prefix}/attachments/#{attachment_id}", format: nil),
      Route.new(name: "listing", path: "#{prefix}/recordings/#{owner_id}/attachments", format: nil),
      Route.new(name: "picker", path: "#{prefix}/recordings/#{owner_id}/attachments/picker", format: :json)
    ]
  end

  def define_hook
    Workspace.define_method(HOOK) do |actor:, action:, recording:|
      actor && action && recording
      true
    end
  end

  def remove_hook
    return unless defined?(Workspace)
    return unless Workspace.private_method_defined?(HOOK) || Workspace.method_defined?(HOOK) || Workspace.public_method_defined?(HOOK)

    Workspace.remove_method(HOOK)
  end

  def sample(hook)
    @routes.map do |route|
      @warmup.times { request(route) }
      samples = Array.new(@iterations) { request(route) }
      summarize(route, hook, samples)
    end
  end

  def request(route)
    queries = []
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    response = nil
    ActiveSupport::Notifications.subscribed(query_counter(queries), "sql.active_record") do
      response = @client.get(route.path, format: route.format)
    end
    elapsed_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000.0
    status = response.status.to_i
    raise "#{route.name} returned #{status}" unless status == 200

    { queries: queries, count: queries.length, ms: elapsed_ms }
  end

  def query_counter(queries)
    lambda do |_name, _started, _finished, _id, payload|
      kind = payload[:name].to_s
      next if kind == "SCHEMA" || kind == "CACHE" || payload[:cached]

      queries << kind
    end
  end

  def summarize(route, hook, samples)
    counts = samples.map { |sample| sample[:count] }
    times = samples.map { |sample| sample[:ms] }
    {
      route: route.name,
      hook: hook,
      queries: median(counts).to_i,
      query_min: counts.min,
      query_max: counts.max,
      median_ms: median(times).round(3),
      query_names: samples.first[:queries].tally
    }
  end

  def median(values)
    ordered = values.sort
    middle = ordered.length / 2
    return ordered[middle] if ordered.length.odd?

    (ordered[middle - 1] + ordered[middle]) / 2.0
  end

  def report(rows)
    puts "| Route | Hook | Queries | Median ms |"
    puts "| --- | --- | ---: | ---: |"
    rows.each do |row|
      puts "| #{row[:route]} | #{row[:hook]} | #{row[:queries]} | #{row[:median_ms]} |"
    end

    path = ENV.fetch("BENCH_OUT", nil)
    return if path.blank?

    File.write(path, JSON.pretty_generate(iterations: @iterations, warmup: @warmup, rows: rows))
    puts "wrote #{path}"
  end
end

AttachmentReadBenchmark.new.run
