# frozen_string_literal: true

class AddArrivalAndLatencyBucketToApiRequestLogs < ActiveRecord::Migration[8.1]
  def up
    table = "recording_studio_api_api_request_logs"
    return unless table_exists?(table)

    add_column table, :arrived_at, :datetime unless column_exists?(table, :arrived_at)
    add_column table, :latency_bucket_ms, :integer unless column_exists?(table, :latency_bucket_ms)
    change_column_default table, :arrived_at, from: nil, to: -> { "clock_timestamp()" }
  end

  def down
    table = "recording_studio_api_api_request_logs"
    return unless table_exists?(table)

    remove_column table, :latency_bucket_ms if column_exists?(table, :latency_bucket_ms)
    remove_column table, :arrived_at if column_exists?(table, :arrived_at)
  end
end
