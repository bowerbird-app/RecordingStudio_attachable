# frozen_string_literal: true

module RecordingStudioAttachable
  module ProvidersHelper
    def remote_file_entry_value(entry, *names)
      names.each do |name|
        if entry.respond_to?(:stringify_keys)
          value = entry.stringify_keys[name.to_s]
          return value unless value.nil?
        elsif entry.respond_to?(name)
          return entry.public_send(name)
        end
      end

      nil
    end
  end
end
