# frozen_string_literal: true

module RecordingStudioAttachable
  # ChatGPT's file object. download_url is a bearer secret: it is fetched, then
  # dropped. It is never stored, and it is stripped from any error we raise.
  module AttachedFile
    SHAPE = "file must be an object with download_url and file_id"
    LEAD = "The attached file could not be downloaded"
    DEFAULT_NAME = "upload"
    Source = Struct.new(:url, :mime, :name)

    module_function

    def fetch(file, max_bytes:, remote_file:)
      downloaded = nil
      source = parsed(file)
      remote = remote_file.call(source.url, source.name)
      downloaded = SafeRemoteFetch.call(remote, max_bytes: max_bytes)
      yield downloaded.io, source.name, source.mime.presence || downloaded.content_type
    rescue StandardError => e
      raise without_secret(e, source, remote), cause: nil
    ensure
      SafeRemoteFetch.close_io(downloaded&.io)
    end

    def parsed(file)
      values = hash_values(file)
      url = values[:download_url].to_s.strip
      raise ArgumentError, SHAPE if url.empty? || values[:file_id].to_s.strip.empty?

      Source.new(url, values[:mime_type].to_s.strip, filename(values[:file_name]))
    end

    def hash_values(file)
      raise ArgumentError, SHAPE unless file.is_a?(Hash)

      file.to_h.symbolize_keys
    end

    def filename(name)
      base = File.basename(name.to_s).strip
      return DEFAULT_NAME if base.empty? || base == "." || base == ".."
      return DEFAULT_NAME if base.include?("://") || base.include?("\0")

      base
    end

    def without_secret(error, source, remote)
      return error unless secret_in?(error, source, remote)

      SafeRemoteFetch::Error.new(scrubbed(error.message, source.url, remote))
    end

    def secret_in?(error, source, remote)
      return false if source.nil?
      return true if error.is_a?(SafeRemoteFetch::Error)

      text = error.message.to_s
      text.include?(source.url) || leaked_path?(text, remote)
    end

    def leaked_path?(text, remote)
      path = request_uri(remote)
      !path.empty? && text.include?(path)
    end

    def scrubbed(text, secret, remote)
      cleaned = strip(strip(text.to_s, secret), request_uri(remote)).gsub(/\s+/, " ").strip
      cleaned.empty? ? LEAD : "#{LEAD}. #{cleaned}"
    end

    def request_uri(remote)
      uri = remote&.uri
      uri.respond_to?(:request_uri) ? uri.request_uri.to_s : ""
    end

    def strip(text, secret)
      needle = secret.to_s
      needle.empty? ? text : text.split(needle).join
    end
    private_class_method :parsed, :hash_values, :filename, :without_secret, :secret_in?, :leaked_path?,
                         :scrubbed, :request_uri, :strip
  end
end
