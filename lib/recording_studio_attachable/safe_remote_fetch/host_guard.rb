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
        IPAddr.new("192.168.0.0/16"),
        IPAddr.new("198.18.0.0/15"),
        IPAddr.new("224.0.0.0/4"),
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
        IPAddr.new("::ffff:192.168.0.0/112"),
        IPAddr.new("::ffff:198.18.0.0/111"),
        IPAddr.new("::ffff:224.0.0.0/100"),
        IPAddr.new("::ffff:0:0/96"),
        IPAddr.new("2002::/16")
      ].freeze
      BLOCKED_HOSTS = %w[localhost metadata.google.internal].freeze

      def initialize(allowed_hosts)
        @allowed_hosts = Array(allowed_hosts)
      end

      def validate!(uri)
        raise Error, "Remote download must use HTTPS" unless uri.is_a?(URI::HTTPS)
        raise Error, "Remote download host is missing" if uri.host.blank?
        raise Error, "Remote download must use port 443" unless uri.port.nil? || uri.port == 443
        raise Error, "Remote download host is not allowed" unless allowed?(uri.host) && !blocked?(uri.host)
      end

      def public_ip(host)
        addresses = addresses_for(host)
        raise Error, "Remote download host could not be resolved" if addresses.empty?
        raise Error, "Remote download host resolves to a private address" if addresses.any? { |address| private_ip?(address) }

        addresses.first
      end

      private

      attr_reader :allowed_hosts

      def allowed?(host)
        normalized = host.to_s.downcase
        allowed_hosts.any? { |pattern| host_matches?(normalized, pattern.to_s.downcase) }
      end

      def host_matches?(normalized, allowed)
        return normalized == allowed unless allowed.start_with?("*.")

        suffix = allowed.delete_prefix("*.")
        normalized == suffix || normalized.end_with?(".#{suffix}")
      end

      def blocked?(host)
        BLOCKED_HOSTS.include?(host.to_s.downcase)
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
