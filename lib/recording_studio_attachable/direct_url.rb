# frozen_string_literal: true

module RecordingStudioAttachable
  # Builds public custom-domain URLs for Active Storage blob keys.
  #
  # Hosts point +config.direct_url_host+ at a public CDN/custom domain that
  # serves the same object keys as the Active Storage service (for example an
  # R2 custom domain). Keys are treated as unguessable; URLs are not signed and
  # do not expire.
  module DirectUrl
    module_function

    def build(blob_key, host: RecordingStudioAttachable.configuration.direct_url_host)
      raise ConfigurationError, missing_host_message if host.blank?
      raise ArgumentError, "blob_key is required for a direct URL" if blob_key.blank?

      "https://#{normalize_host(host)}/#{blob_key}"
    end

    def ensure_host_configured!(host: RecordingStudioAttachable.configuration.direct_url_host)
      raise ConfigurationError, missing_host_message if host.blank?
    end

    def missing_host_message
      "RecordingStudioAttachable config.direct_url_host must be set when url_mode is :direct " \
        '(for example config.direct_url_host = "images.example.com")'
    end

    def normalize_host(host)
      host.to_s.strip.sub(%r{\Ahttps?://}i, "").delete_suffix("/")
    end
  end
end
