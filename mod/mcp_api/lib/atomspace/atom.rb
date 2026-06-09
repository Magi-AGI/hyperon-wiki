# frozen_string_literal: true

module Atomspace
  # Canonical read-side DTO returned by ReadClient. The auth filter (Invariant 9,
  # 2026-06-09 multi-card clarification) requires EVERY id in #associated_card_ids to be
  # ok?(:read). associated_card_ids returns only RESOLVED card ids the atom references;
  # an unresolved DeckoReference target (dangling key) is excluded -- it neither blocks
  # nor leaks, while the referer must still be readable.
  class Atom
    attr_reader :type, :card_id

    def initialize(type:, card_id: nil, referer_id: nil, referee_id: nil, fields: {})
      @type = type
      @card_id = card_id
      @referer_id = referer_id
      @referee_id = referee_id   # nil when the reference target is Unresolved
      @fields = fields
    end

    def associated_card_ids
      case @type
      when "DeckoReference" then [@referer_id, @referee_id].compact
      else [@card_id].compact
      end
    end

    def to_h
      { type: @type, card_id: @card_id }.merge(@fields).compact
    end
  end
end
