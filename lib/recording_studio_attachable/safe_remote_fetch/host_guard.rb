# frozen_string_literal: true

require "ipaddr"
require "resolv"

module RecordingStudioAttachable
  class SafeRemoteFetch
    class HostGuard
      PRIVATE_NETWORKS = [
        IPAddr.new("0.0.0.0/8"),
        IPAddr.new("10.0.0.0/8"),
        IPAddr.new("100.64.0.0/10"),
        IPAddr.new("127.0.0.0/8"),
        IPAddr.new("169.254.0.0/16"),
        IPAddr.new("172.16.0.0/12"),
        IPAddr.new("192.0.0.0/24"),
        IPAddr.new("192.0.2.0/24"),
        IPAddr.new("192.168.0.0/16"),
        IPAddr.new("198.18.0.0/15"),
        IPAddr.new("198.51.100.0/24"),
        IPAddr.new("203.0.113.0/24"),
        IPAddr.new("224.0.0.0/4"),
        IPAddr.new("240.0.0.0/4"),
        IPAddr.new("::/128"),
        IPAddr.new("::1/128"),
        IPAddr.new("64:ff9b::/96"),
        IPAddr.new("fc00::/7"),
        IPAddr.new("fe80::/10"),
        IPAddr.new("::ffff:0.0.0.0/104"),
        IPAddr.new("::ffff:10.0.0.0/104"),
        IPAddr.new("::ffff:100.64.0.0/106"),
        IPAddr.new("::ffff:127.0.0.0/104"),
        IPAddr.new("::ffff:169.254.0.0/112"),
        IPAddr.new("::ffff:172.16.0.0/108"),
        IPAddr.new("::ffff:192.0.0.0/120"),
        IPAddr.new("::ffff:192.0.2.0/120"),
        IPAddr.new("::ffff:192.168.0.0/112"),
        IPAddr.new("::ffff:198.18.0.0/111"),
        IPAddr.new("::ffff:198.51.100.0/120"),
        IPAddr.new("::ffff:203.0.113.0/120"),
        IPAddr.new("::ffff:224.0.0.0/100"),
        IPAddr.new("::ffff:240.0.0.0/100"),
        IPAddr.new("::ffff:0:0/96"),
        IPAddr.new("100::/64"),
        IPAddr.new("2001::/32"),
        IPAddr.new("2001:db8::/32"),
        IPAddr.new("2002::/16"),
        IPAddr.new("ff00::/8")
      ].freeze
      BLOCKED_HOSTS = %w[localhost metadata.google.internal].freeze
      BLOCKED_SUFFIXES = %w[.internal .local .localhost].freeze
      HOST_NOT_ALLOWED = "This remote download host is not allowed."
      IMPORTS_OFF = "Remote imports are turned off."
      HOST_BLOCKED =
        "This remote download host is blocked. Imports cannot use localhost, local names, or cloud metadata endpoints."

      def initialize(allowed_hosts)
        @allowed_hosts = allowed_hosts == :none ? :none : Array(allowed_hosts)
      end

      def validate!(uri)
        require_https!(uri)
        raise Error, HOST_BLOCKED if blocked?(uri.host)
        raise Error, IMPORTS_OFF if imports_off?
        raise Error, HOST_NOT_ALLOWED unless allowed?(uri.host)
      end

      def public_ip(host)
        addresses = addresses_for(host)
        raise Error, "Remote download host could not be resolved" if addresses.empty?
        raise Error, "Remote download host resolves to a private address" if addresses.any? { |address| private_ip?(address) }

        addresses.first
      end

      private

      attr_reader :allowed_hosts

      def require_https!(uri)
        raise Error, "Remote download must use HTTPS" unless uri.is_a?(URI::HTTPS)
        raise Error, "Remote download host is missing" if uri.host.blank?
        raise Error, "Remote download must use port 443" unless uri.port.nil? || uri.port == 443
      end

      def imports_off?
        allowed_hosts == :none
      end

      def allowed?(host)
        return false if imports_off?
        return true if allowed_hosts.blank?

        normalized = host.to_s.downcase
        allowed_hosts.any? { |pattern| host_matches?(normalized, pattern.to_s.downcase) }
      end

      def host_matches?(normalized, allowed)
        return normalized == allowed unless allowed.start_with?("*.")

        suffix = allowed.delete_prefix("*.")
        normalized == suffix || normalized.end_with?(".#{suffix}")
      end

      def blocked?(host)
        name = host.to_s.downcase.delete_suffix(".")
        return true if BLOCKED_HOSTS.include?(name)

        BLOCKED_SUFFIXES.any? { |suffix| name.end_with?(suffix) }
      end

      def addresses_for(host)
        Resolv.getaddresses(host.to_s)
      rescue Resolv::ResolvError, SocketError
        raise Error, "Remote download host could not be resolved"
      end

      def private_ip?(address)
        ip = IPAddr.new(address)
        PRIVATE_NETWORKS.any? { |network| network.include?(ip) }
      rescue IPAddr::InvalidAddressError
        true
      end
    end
  end
end
