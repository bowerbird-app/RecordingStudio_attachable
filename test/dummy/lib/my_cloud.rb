# frozen_string_literal: true

require "base64"
require_relative "my_cloud/engine"

module MyCloud
  CLOUD_PNG = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")
  FILES = [
    { "id" => "file-1", "name" => "Cloud brief.png", "content_type" => "image/png", "kind" => "file" },
    { "id" => "file-2", "name" => "Nested brief.png", "content_type" => "image/png", "kind" => "file" }
  ].freeze

  module_function

  def connections
    @connections ||= {}
  end

  def reset!
    connections.clear
    @force_reconnect = false
  end

  def connected?(actor)
    connections[actor_key(actor)] == :connected
  end

  def connect!(actor)
    connections[actor_key(actor)] = :connected
    @force_reconnect = false
  end

  def disconnect!(actor)
    connections.delete(actor_key(actor))
  end

  def force_reconnect!
    @force_reconnect = true
  end

  def reconnect_required?
    @force_reconnect
  end

  def actor_key(actor)
    actor.respond_to?(:id) ? actor.id : actor
  end

  def entries_at(path)
    normalized = path.to_s
    normalized = "" if normalized == "/"

    case normalized
    when ""
      [
        { "id" => "folder-1", "name" => "Briefs", "kind" => "folder" },
        FILES.first
      ]
    when "folder-1"
      [FILES.fetch(1)]
    else
      []
    end
  end
end
