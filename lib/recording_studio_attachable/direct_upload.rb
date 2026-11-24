# frozen_string_literal: true

require "marcel"

module RecordingStudioAttachable
  # Direct-upload blobs this gem creates. The signed id, the parent recording,
  # and the actor are checked again when the file is attached.
  module DirectUpload
    TAG = "recording_studio_attachable"
    PURPOSE = :attachable_upload
    INLINE_TYPES = %w[image/png image/jpeg image/gif image/webp application/pdf].freeze
    GENERIC_CONTENT_TYPES = %w[application/octet-stream binary/octet-stream].freeze
    SIGNED_BLOB_INVALID =
      "signed_blob_id is invalid or expired. Prepare an upload first and use the signed_blob_id it returns."
    CHECKSUM_MISMATCH =
      "The uploaded bytes do not match the checksum. Prepare an upload and PUT the exact file again."

    module_function

    def prepare!(recording:, actor:, filename:, byte_size:, checksum:, content_type:)
      raise ArgumentError, "Actor is required" if actor.blank?

      size = byte_count(byte_size)
      reject_type!(recording, content_type)
      reject_size!(recording, size)
      reject_pending!(recording, actor)
      reserve!(recording, create_blob!(recording, actor, filename, size, checksum, content_type))
    end

    def ensure_pending!(recording, actor)
      raise ArgumentError, "Actor is required" if actor.blank?

      reject_pending!(recording, actor)
    end

    def prepare_from_io!(recording:, actor:, io:, filename:, declared_type:)
      raise ArgumentError, "Actor is required" if actor.blank?
      raise ArgumentError, "filename is required" if filename.blank?

      stored_type = import_content_type(io, filename: filename, declared: declared_type)
      reject_type!(recording, stored_type)
      reject_size!(recording, io_bytesize(io))
      reject_pending!(recording, actor)
      reserve!(recording, uploaded_blob!(recording, actor, io, filename, stored_type))
    end

    def max_file_size_for(recording)
      recording_option(recording, :max_file_size)
    end

    def ticket(blob)
      ttl = expires_in
      {
        signed_blob_id: sign(blob),
        upload: {
          url: blob.service_url_for_direct_upload(expires_in: ttl),
          headers: blob.service_headers_for_direct_upload
        },
        expires_at: ttl.from_now.iso8601
      }
    end

    def browser_json(blob)
      {
        signed_id: sign(blob),
        direct_upload: {
          url: blob.service_url_for_direct_upload(expires_in: expires_in),
          headers: blob.service_headers_for_direct_upload
        }
      }
    end

    def sign(blob)
      blob.signed_id(purpose: PURPOSE, expires_in: expires_in)
    end

    def accept!(signed_id, recording:, actor:)
      blob = signed_blob(signed_id)
      raise ArgumentError, "Blob is already attached" if attached?(blob)

      verify_binding!(blob, recording, actor)
      blob
    end

    def import_content_type(io, filename:, declared:)
      detected = detect_type(io, filename)
      declared_type = normalized_type(declared)
      return detected if declared_type.blank? || GENERIC_CONTENT_TYPES.include?(declared_type) || declared_type != detected

      declared_type
    ensure
      rewind_io(io)
    end

    def sniff!(blob, capability_options)
      declared = normalized_type(blob.content_type)
      sniffed = identified_type(blob)
      raise ArgumentError, "File content does not match #{declared}" unless sniffed == declared
      return if type_allowed?(sniffed, capability_options)

      raise ArgumentError, "Blob content type #{sniffed.inspect} is not allowed"
    rescue *integrity_errors
      raise ArgumentError, CHECKSUM_MISMATCH
    end

    def metadata_for(recording:, actor:)
      {
        TAG => "1",
        "parent_recording_id" => recording.id.to_s,
        "root_recording_id" => root_id(recording),
        "actor_type" => actor_type(actor),
        "actor_id" => actor_id(actor)
      }
    end

    def delivery_disposition(requested, content_type)
      return :attachment unless requested.to_sym == :inline
      return :inline if INLINE_TYPES.include?(normalized_type(content_type))

      :attachment
    end

    def expires_in
      RecordingStudioAttachable.configuration.direct_upload_expires_in
    end

    def pending_count(recording, actor)
      return 0 unless ActiveStorage::Blob.respond_to?(:unattached)

      pending_scope(recording, actor).count
    end

    def expired_unattached(cutoff)
      tagged_unattached.where(created_at: ...cutoff)
    end

    def tagged_unattached
      ActiveStorage::Blob.unattached.where("metadata::jsonb ->> ? = ?", TAG, "1")
    end

    def actor_id(actor)
      return actor.id.to_s if actor.respond_to?(:id) && !actor.id.nil?

      actor.to_s
    end

    def actor_type(actor)
      actor.class.name.presence || actor.class.to_s
    end

    def normalized_type(content_type)
      type = content_type.to_s.split(";").first.to_s.strip.downcase
      type == "image/jpg" ? "image/jpeg" : type
    end

    class << self
      private

      def byte_count(byte_size)
        Integer(byte_size)
      rescue ArgumentError, TypeError
        raise ArgumentError, "byte_size must be zero or more"
      end

      def signed_blob(signed_id)
        ActiveStorage::Blob.find_signed!(signed_id, purpose: PURPOSE)
      rescue *invalid_signed_blob_errors, ArgumentError
        # find_signed! raises ArgumentError for a blank or malformed signed id, not only InvalidSignature.
        raise ArgumentError, SIGNED_BLOB_INVALID
      end

      def invalid_signed_blob_errors
        [ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound] + integrity_errors
      end

      def integrity_errors
        defined?(ActiveStorage::IntegrityError) ? [ActiveStorage::IntegrityError] : []
      end

      def reject_type!(recording, content_type)
        return if type_allowed_for?(recording, content_type)

        raise ArgumentError, "Content type #{content_type} is not allowed"
      end

      def reject_size!(recording, size)
        raise ArgumentError, "byte_size must be zero or more" if size.negative?
        return if size_allowed?(recording, size)

        raise ArgumentError, "File exceeds maximum file size"
      end

      def reject_pending!(recording, actor)
        limit = RecordingStudioAttachable.configuration.pending_upload_limit
        return if limit.blank? || pending_count(recording, actor) < limit.to_i

        raise ArgumentError, "Too many pending uploads"
      end

      def create_blob!(recording, actor, filename, size, checksum, content_type)
        ActiveStorage::Blob.create_before_direct_upload!(
          filename: filename,
          byte_size: size,
          checksum: checksum,
          content_type: content_type,
          metadata: metadata_for(recording: recording, actor: actor)
        )
      end

      def uploaded_blob!(recording, actor, io, filename, content_type)
        rewind_io(io)
        ActiveStorage::Blob.create_and_upload!(
          io: io,
          filename: filename,
          content_type: content_type,
          identify: false,
          metadata: metadata_for(recording: recording, actor: actor)
        )
      end

      def io_bytesize(io)
        rewind_io(io)
        return io.size if io.respond_to?(:size)

        bytes = io.read.to_s.bytesize
        rewind_io(io)
        bytes
      end

      def reserve!(recording, blob)
        root = root_recording(recording)
        incoming = StorageLimit::IncomingBytes.for(root, [blob])
        StorageLimit.with_storage_capacity!(root, incoming) { blob }
      rescue StandardError
        drop!(blob)
        raise
      end

      def drop!(blob)
        return unless blob.respond_to?(:persisted?) && blob.persisted?

        StorageLimit.discard_unattached!([blob])
      rescue StandardError
        nil
      end

      def verify_binding!(blob, recording, actor)
        meta = blob.metadata.to_h.stringify_keys
        issued_for_upload!(meta)
        issued_for_recording!(meta, recording)
        issued_for_actor!(meta, actor)
      end

      def issued_for_upload!(meta)
        return if meta[TAG].to_s == "1"

        raise ArgumentError, "Blob was not issued for this upload"
      end

      def issued_for_recording!(meta, recording)
        return if meta["parent_recording_id"].to_s == recording.id.to_s

        raise ArgumentError, "Blob was not issued for this recording"
      end

      def issued_for_actor!(meta, actor)
        return if meta["actor_type"].to_s == actor_type(actor) && meta["actor_id"].to_s == actor_id(actor)

        raise ArgumentError, "Blob was not issued for this actor"
      end

      def identified_type(blob)
        blob.open { |io| detect_type(io, blob.filename.to_s) }
      rescue ActiveStorage::FileNotFoundError
        raise ArgumentError, "File has not been uploaded"
      end

      def detect_type(io, filename)
        rewind_io(io)
        magic = Marcel::Magic.by_magic(io)
        rewind_io(io)
        return normalized_type(magic.type) if magic

        guessed = normalized_type(Marcel::Magic.by_path(filename.to_s)&.type)
        return guessed if guessed.present? && !magic_required?(guessed)

        "application/octet-stream"
      end

      def rewind_io(io)
        io.rewind if io.respond_to?(:rewind)
      end

      def magic_required?(type)
        type.start_with?("image/") || type == "application/pdf"
      end

      def type_allowed?(type, capability_options)
        configuration.allowed_content_type?(type, allowed_content_types: option(capability_options, :allowed_content_types))
      end

      def type_allowed_for?(recording, content_type)
        configuration.allowed_content_type?(content_type, allowed_content_types: recording_option(recording, :allowed_content_types))
      end

      def size_allowed?(recording, size)
        max = recording_option(recording, :max_file_size)
        max.blank? || size <= max
      end

      def option(capability_options, name)
        options = capability_options.to_h.symbolize_keys
        return options[name] if options.key?(name)

        configuration.public_send(name)
      end

      def recording_option(recording, name)
        options = capability_options_for(recording)
        return options[name] if options.key?(name)

        configuration.public_send(name)
      end

      def capability_options_for(recording)
        return {} unless defined?(RecordingStudio) && RecordingStudio.respond_to?(:capability_options)

        owner_type = recording.respond_to?(:recordable_type) ? recording.recordable_type : nil
        return {} if owner_type.blank?

        (RecordingStudio.capability_options(:attachable, for_type: owner_type) || {}).to_h.symbolize_keys
      end

      def pending_scope(recording, actor)
        tagged_unattached
          .where("metadata::jsonb ->> 'root_recording_id' = ?", root_id(recording))
          .where("metadata::jsonb ->> 'actor_type' = ?", actor_type(actor))
          .where("metadata::jsonb ->> 'actor_id' = ?", actor_id(actor))
      end

      def attached?(blob)
        relation = blob.attachments
        return false if relation.nil?
        return relation.exists? if relation.respond_to?(:exists?)
        return false if relation.respond_to?(:empty?) && relation.empty?

        relation.respond_to?(:any?) && relation.any?
      end

      def root_recording(recording)
        return recording unless recording.respond_to?(:root_recording)

        recording.root_recording || recording
      end

      def root_id(recording)
        root_recording(recording).id.to_s
      end

      def configuration
        RecordingStudioAttachable.configuration
      end
    end
  end
end
