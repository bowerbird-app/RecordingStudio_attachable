# frozen_string_literal: true

require "securerandom"

module RecordingStudioAttachable
  module Adapter
    class Session
      def initialize(session, key:, provider_name:)
        @session = session
        @key = key
        @provider_name = provider_name
      end

      def tokens
        storage.fetch("tokens", {})
      end

      def store_tokens!(incoming)
        storage["tokens"] = tokens.merge(incoming.compact.stringify_keys)
        SessionCookie.raise_if_overflow!(session)
      end

      def clear_tokens!
        storage.delete("tokens")
      end

      def store_state!(recording_id:, extra: {}, redirect_params: {})
        state = SecureRandom.hex(24)
        storage["oauth_state"] = {
          "value" => state,
          "recording_id" => recording_id.to_s
        }.merge(extra.stringify_keys).merge(redirect_params.stringify_keys)
        state
      end

      def consume_state!(state)
        saved = storage.delete("oauth_state") || {}
        expected = saved["value"].to_s
        actual = state.to_s
        return saved if expected.present? && actual.present? && ActiveSupport::SecurityUtils.secure_compare(expected, actual)

        raise RecordingStudioAttachable::Error, "#{provider_name} authorization state did not match"
      end

      def storage
        session[key] ||= {}
      end

      def dig(*)
        storage.dig(*)
      end

      private

      attr_reader :session, :key, :provider_name
    end
  end
end
