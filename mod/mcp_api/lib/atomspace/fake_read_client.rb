# frozen_string_literal: true

require_relative "read_client"
require_relative "atom"

module Atomspace
  # TEST/DEV ONLY. Bound via config/initializers/atomspace_read_client.rb guarded by
  # Rails.env (never in production). Holds an in-memory Array<Atomspace::Atom> so the L7
  # readiness port + L9 auth post-filter get full coverage without a running sidecar.
  class FakeReadClient < ReadClient
    class << self
      attr_accessor :atoms, :watermark

      def seed!(atoms)
        @atoms = atoms
      end

      def watermark_meta
        { atomspace_watermark: watermark || 0, monitor_status: "healthy", staleness_seconds: 0.0 }
      end
    end

    def query_atoms(pattern:, limit: nil, include_trash: false, **)
      scoped = all.select { |a| a.type == "DeckoCard" }
      limit ? scoped.first(limit.to_i) : scoped
    end

    def get_card_atom(card_id:, include_trash: false, **)
      # the DeckoCard atom ONLY (references are list_references) -- aligned with SidecarReadClient +
      # the locked C2 contract (Codex 2026-06-25).
      all.select { |a| a.type == "DeckoCard" && a.card_id.to_s == card_id.to_s }
    end

    def get_card_provenance(card_id: nil, event_id: nil, **)
      all.select { |a| a.type == "DeckoProvenance" }
    end

    def list_references(card_id:, ref_type: nil, include_trash: false, **)
      all.select { |a| a.type == "DeckoReference" }
    end

    def list_atoms_by_type(type_name:, limit: nil, include_trash: false, **)
      scoped = all.select { |a| a.type == type_name }
      limit ? scoped.first(limit.to_i) : scoped
    end

    def atom_types
      all.map(&:type).uniq
    end

    def atom_count_by_type
      all.group_by(&:type).transform_values(&:size)
    end

    def space_stats
      { atom_count: all.size, types: atom_count_by_type, mirror_lag: 0 }
    end

    def quarantine_list
      []
    end

    def quarantine_delete(_id)
      true
    end

    private

    def all
      self.class.atoms || []
    end
  end
end
