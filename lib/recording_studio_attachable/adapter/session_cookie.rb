# frozen_string_literal: true

module RecordingStudioAttachable
  module Adapter
    module SessionCookie
      COOKIE_BUDGET = 3200
      OVERFLOW_MESSAGE = "This cookie jar is full. Disconnect the other cloud provider and connect again, " \
                         "or switch the host to a server-side session store."

      module_function

      def raise_if_overflow!(session)
        return if encoded_size(session) <= COOKIE_BUDGET

        raise ActionDispatch::Cookies::CookieOverflow, OVERFLOW_MESSAGE
      end

      def overflow_message
        OVERFLOW_MESSAGE
      end

      def encoded_size(session)
        payload = session.respond_to?(:to_hash) ? session.to_hash : session.to_h
        payload.to_json.bytesize
      end
    end
  end
end
