# frozen_string_literal: true

require "active_support/message_verifier"

module RecordingStudioAttachable
  class AttachmentCollection
    PREVIEW_VARIANT = :square_med
    STALE_FORM = "This form is out of date. Reload the page and try again."
    GONE = "One of these is gone. Reload the page and try again."
    SORTABLE_MISSING = "sortable: true needs the parent to respond to recording_studio_orderable_reorder!. This parent does not."
    ORDERABLE_ALLOWS = "The parent must allow RecordingStudioAttachable::Attachment in Orderable allows, or omit allows."
    EMPTY_MESSAGES = {
      images: "No images yet.",
      files: "No files yet.",
      attachments: "Nothing here yet."
    }.freeze

    Field = Data.define(:key, :label, :column, :blank, :control)
    FIELDS = {
      caption: Field.new(:caption, "Caption", :caption, :clear, :text),
      credit: Field.new(:credit, "Credit", :credit, :clear, :text),
      alt_text: Field.new(:alt_text, "Alt text", :alt_text, :clear, :text),
      name: Field.new(:name, "Name", :name, :keep, :text),
      description: Field.new(:description, "Description", :description, :clear, :area)
    }.freeze
    ASSOCIATIONS = { images: :images, attachments: :all, files: :files }.freeze
    ROW_KEYS = %i[recording_id order name description caption credit alt_text].freeze

    Row = Data.define(:recording, :order, :values)
    Revision = Data.define(:recording, :changes)

    private_constant :Field, :Revision

    class << self
      def for(recording:, association:, fields:, sortable:, return_to: nil)
        build(recording:, association:, fields:, sortable:, return_to:).tap(&:prepare!)
      end

      def permit(params)
        AttachmentCollectionParams.permit(params)
      end

      def from_params(recording:, params:)
        sheet = AttachmentCollectionParams.editor(params)
        choices = AttachmentCollectionToken.read(sheet[:signed_editor], recording)
        build(recording:, **choices, submitted_rows: sheet[:rows]).tap(&:prepare!)
      end

      def normalize_association(association)
        AttachmentCollectionParams.association(association)
      end

      def normalize_fields(fields)
        AttachmentCollectionParams.fields(fields)
      end

      private

      def build(recording:, association:, fields:, sortable:, **options)
        new(
          recording: recording,
          association: normalize_association(association),
          fields: normalize_fields(fields),
          sortable: ActiveModel::Type::Boolean.new.cast(sortable) == true,
          **options
        )
      end
    end

    attr_reader :recording, :association, :fields, :return_to, :signed_editor

    def initialize(recording:, association:, fields:, sortable:, **options)
      @recording = recording
      @association = association
      @fields = fields
      @sortable = sortable
      @return_to = options[:return_to]
      @submitted_rows = AttachmentCollectionParams.row_list(options[:submitted_rows])
      @signed_editor = signed_token
    end

    def sortable?
      @sortable
    end

    def form_id
      "attachment-collection-#{recording.id}"
    end

    def empty_message
      EMPTY_MESSAGES.fetch(association)
    end

    def input_name(key)
      "attachment_collection[rows][][#{key}]"
    end

    def rows
      @rows ||= display_recordings.each_with_index.map { |item, index| build_row(item, index) }
    end

    def revisions
      change_pairs.filter_map { |item, changes| Revision.new(recording: item, changes: changes) }
    end

    def reorder_ids
      return unless sortable?

      AttachmentCollectionOrder.new(
        child_ids: membership.child_ids,
        recordings: display_recordings,
        submitted_rows: @submitted_rows
      ).ids
    end

    def prepare!
      ensure_sortable_parent! if sortable?
      rows
      assert_known_rows!
    end

    private

    def signed_token
      AttachmentCollectionToken.sign(recording:, association:, fields: fields.map(&:key), sortable: sortable?)
    end
  end

  module AttachmentCollectionSheet
    private

    def build_row(item, index)
      AttachmentCollection::Row.new(recording: item, order: sortable? ? index + 1 : nil, values: field_values(item))
    end

    def field_values(item)
      fields.to_h { |field| [field.key, item.recordable.public_send(field.column)] }
    end

    def change_pairs
      AttachmentCollectionChanges.new(recordings: display_recordings, fields: fields, submitted_rows: @submitted_rows).pairs
    end

    def display_recordings
      @display_recordings ||= membership.recordings
    end

    def membership
      @membership ||= AttachmentCollectionMembership.new(recording:, association:, sortable: sortable?)
    end

    def ensure_sortable_parent!
      return if recording.respond_to?(:recording_studio_orderable_reorder!)

      raise ArgumentError, AttachmentCollection::SORTABLE_MISSING
    end

    def assert_known_rows!
      known = display_recordings.map { |item| item.id.to_s }
      return if @submitted_rows.all? { |row| row[:recording_id].blank? || known.include?(row[:recording_id].to_s) }

      raise ArgumentError, AttachmentCollection::GONE
    end
  end

  class AttachmentCollection
    include AttachmentCollectionSheet
  end

  class AttachmentCollectionParams
    class << self
      def permit(params)
        parameters = coerce(params)
        parameters.permit(:redirect_mode, :return_to, attachment_collection: collection_keys)
      end

      def editor(params)
        data = indifferent(params)
        nested = data[:attachment_collection]
        return indifferent(nested) if nested.present?

        data
      end

      def association(name)
        raise ArgumentError, "Unknown association: #{name.inspect}" if name.blank?

        key = name.to_sym
        return key if AttachmentCollection::ASSOCIATIONS.key?(key)

        raise ArgumentError, "Unknown association: #{name}"
      end

      def fields(list)
        keys = Array(list).map(&:to_sym)
        raise ArgumentError, "fields must be present" if keys.empty?

        keys.map { |key| AttachmentCollection::FIELDS.fetch(key) { raise ArgumentError, "Unknown field: #{key}" } }
      end

      def row_list(rows)
        Array(rows).map { |row| indifferent(row) }
      end

      def indifferent(value)
        hash_from(value).with_indifferent_access
      end

      private

      def collection_keys
        [:signed_editor, :redirect_mode, :return_to, { rows: AttachmentCollection::ROW_KEYS }]
      end

      def coerce(params)
        return params if params.is_a?(ActionController::Parameters)

        ActionController::Parameters.new(params)
      end

      def hash_from(value)
        return {} if value.nil?
        return value.to_unsafe_h if value.respond_to?(:to_unsafe_h)
        return value.to_h if value.respond_to?(:to_h)

        {}
      end
    end
  end

  class AttachmentCollectionToken
    PURPOSE = "recording_studio_attachable.attachment_collection"

    class << self
      def sign(recording:, association:, fields:, sortable:)
        verifier.generate(payload(recording, association, fields, sortable))
      end

      def read(token, recording)
        data = payload_hash(verifier.verify(token))
        raise ArgumentError, AttachmentCollection::STALE_FORM unless data[:parent_id].to_s == recording.id.to_s

        choices(data)
      rescue ActiveSupport::MessageVerifier::InvalidSignature
        raise ArgumentError, AttachmentCollection::STALE_FORM
      end

      private

      def choices(data)
        {
          association: AttachmentCollectionParams.association(data[:association]),
          fields: data[:fields],
          sortable: ActiveModel::Type::Boolean.new.cast(data[:sortable]) == true
        }
      end

      def payload(recording, association, fields, sortable)
        {
          "parent_id" => recording.id.to_s,
          "association" => association.to_s,
          "fields" => Array(fields).map(&:to_s),
          "sortable" => sortable == true
        }
      end

      def payload_hash(payload)
        raise ArgumentError, AttachmentCollection::STALE_FORM unless payload.is_a?(Hash)

        payload.with_indifferent_access
      end

      def verifier
        app = defined?(Rails) ? Rails.application : nil
        return app.message_verifier(PURPOSE) if app.respond_to?(:message_verifier)

        @verifier ||= ActiveSupport::MessageVerifier.new(PURPOSE, digest: "SHA256", serializer: JSON)
      end
    end
  end

  class AttachmentCollectionMembership
    def initialize(recording:, association:, sortable:)
      @recording = recording
      @association = association
      @sortable = sortable
    end

    def recordings
      @recordings ||= @sortable ? orderable_recordings(loaded) : newest_first(loaded)
    end

    def child_ids
      orderable_children.map { |child| child.respond_to?(:id) ? child.id : child }
    end

    private

    attr_reader :recording, :association

    def loaded
      @loaded ||= Array(query.unpaged)
    end

    def query
      Queries::ForRecording.new(
        recording: recording,
        scope: :direct,
        include_trashed: false,
        kind: AttachmentCollection::ASSOCIATIONS.fetch(association)
      )
    end

    def newest_first(list)
      list.sort_by { |item| [item.created_at, item.id] }.reverse
    end

    def orderable_recordings(list)
      known = child_ids.map(&:to_s)
      missing = list.reject { |item| known.include?(item.id.to_s) }
      raise ArgumentError, AttachmentCollection::ORDERABLE_ALLOWS if missing.any?

      by_id = list.index_by { |item| item.id.to_s }
      child_ids.filter_map { |id| by_id[id.to_s] }
    end

    def orderable_children
      Array(recording.recording_studio_orderable_children)
    end
  end

  class AttachmentCollectionChanges
    def initialize(recordings:, fields:, submitted_rows:)
      @recordings = recordings
      @fields = fields
      @submitted_rows = submitted_rows
      @by_id = recordings.index_by { |item| item.id.to_s }
    end

    def pairs
      @submitted_rows.filter_map { |row| pair_for(row) }
    end

    private

    def pair_for(row)
      item = find!(row[:recording_id])
      changes = changes_for(item.recordable, row)
      return if changes.empty?

      [item, changes]
    end

    def find!(recording_id)
      @by_id.fetch(recording_id.to_s) { raise ArgumentError, AttachmentCollection::GONE }
    end

    def changes_for(attachment, row)
      @fields.each_with_object({}) do |field, changes|
        assign_change(changes, field, attachment, row)
      end
    end

    def assign_change(changes, field, attachment, row)
      return unless row.key?(field.key)

      raw = row[field.key]
      return if keep?(field, attachment.public_send(field.column), raw)

      changes[field.key] = raw
    end

    def keep?(field, current, raw)
      return kept_name?(current, raw) if field.blank == :keep

      omitted_or_same?(current, raw)
    end

    def kept_name?(current, raw)
      raw.nil? || raw == "" || raw == current
    end

    def omitted_or_same?(current, raw)
      return true if raw.nil?

      cleared(raw) == cleared(current)
    end

    def cleared(value)
      value == "" ? nil : value
    end
  end

  class AttachmentCollectionOrder
    def initialize(child_ids:, recordings:, submitted_rows:)
      @child_ids = child_ids
      @recordings = recordings
      @submitted_rows = submitted_rows
    end

    def ids
      submitted = sorted_submissions
      assert_permutation!(submitted)
      spliced = splice(canonical_ids(submitted))
      return if spliced == @child_ids

      spliced
    end

    private

    def sorted_submissions
      @submitted_rows.each_with_index.sort_by { |row, index| [order_number(row, index), index] }.map(&:first)
    end

    def order_number(row, index)
      raw = row[:order]
      return index unless raw.to_s.match?(/\A-?\d+\z/)

      raw.to_i
    end

    def assert_permutation!(submitted)
      left = submitted.map { |row| row[:recording_id].to_s }.tally
      right = @recordings.map { |item| item.id.to_s }.tally
      raise ArgumentError, AttachmentCollection::GONE unless left == right
    end

    def canonical_ids(submitted)
      by_id = @recordings.index_by { |item| item.id.to_s }
      submitted.map { |row| by_id.fetch(row[:recording_id].to_s).id }
    end

    def splice(queue)
      pending = queue.dup
      members = @recordings.map { |item| item.id.to_s }
      @child_ids.map { |id| members.include?(id.to_s) ? pending.shift : id }
    end
  end

  private_constant :AttachmentCollectionSheet, :AttachmentCollectionParams, :AttachmentCollectionToken,
                   :AttachmentCollectionMembership, :AttachmentCollectionChanges, :AttachmentCollectionOrder
end
