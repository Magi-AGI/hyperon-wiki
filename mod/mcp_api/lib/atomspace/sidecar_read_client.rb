# frozen_string_literal: true

require "socket"
require "json"
require_relative "read_client"
require_relative "atom"
require_relative "errors"

module Atomspace
  # Production read client (Lane C C2): talks to the sidecar's privileged `POST /read` over the UNIX
  # socket (atom payloads carry card Content, so the read surface is Unix-only -- never TCP). Maps the
  # type-tagged {atom, fields} sidecar JSON to Atomspace::Atom DTOs with the ids the auth filter needs.
  #
  # Bound in production by config/initializers/atomspace_read_client.rb. A class-level `transport`
  # (callable: (verb, path, body) -> [status, parsed_hash_or_nil]) is injectable for unit tests so the
  # contract is testable without a live socket.
  class SidecarReadClient < ReadClient
    SOCKET_ERRORS = [Errno::ENOENT, Errno::ECONNREFUSED, Errno::EPIPE, Errno::ECONNRESET,
                     Errno::ETIMEDOUT, IOError, SocketError, SystemCallError].freeze

    class << self
      attr_accessor :socket_path, :transport

      # Class-level watermark meta (the ReadClient contract calls this on the bound class).
      def watermark_meta
        status, body = request(:get, "/health/watermark")
        unless status == 200 && body.is_a?(Hash)
          raise ServiceUnavailable, "sidecar watermark unavailable (HTTP #{status})"
        end

        { atomspace_watermark: body["last_applied_action_id"],
          monitor_status: "healthy", staleness_seconds: 0.0 } # true lag is Decko-side (sidecar has no PG)
      rescue *SOCKET_ERRORS => e
        raise ServiceUnavailable, "sidecar unreachable: #{e.class}: #{e.message}"
      end

      # One request to the sidecar -- the injected transport in tests, else real HTTP-over-UNIX-socket.
      def request(verb, path, body = nil)
        return transport.call(verb, path, body) if transport

        unix_request(verb, path, body)
      end

      def default_socket_path
        socket_path || File.join(ENV["SIDECAR_RUN_DIR"] || "/home/ubuntu/atomspace-run", "sidecar.sock")
      end

      private

      # Minimal HTTP/1.0 over the UNIX socket (the sidecar serves wsgiref on AF_UNIX; HTTP/1.0 + close
      # => read to EOF). Returns [status_int, parsed_body_or_nil].
      def unix_request(verb, path, body)
        sock = UNIXSocket.new(default_socket_path)
        payload = body.nil? ? "" : JSON.generate(body)
        sock.write("#{verb.to_s.upcase} #{path} HTTP/1.0\r\n" \
                   "Host: localhost\r\nContent-Type: application/json\r\n" \
                   "Content-Length: #{payload.bytesize}\r\nConnection: close\r\n\r\n#{payload}")
        raw = sock.read.to_s
        head, _, json_body = raw.partition("\r\n\r\n")
        status = head[%r{\AHTTP/\d\.\d (\d+)}, 1].to_i
        [status, parse(json_body)]
      ensure
        sock&.close
      end

      def parse(raw)
        JSON.parse(raw)
      rescue JSON::ParserError, TypeError
        nil
      end
    end

    # ---- card-scoped (return Array<Atomspace::Atom>) ----
    def query_atoms(pattern:, limit: nil, include_trash: false, **)
      read("query_atoms", pattern: normalize_pattern(pattern), limit: limit, include_trash: include_trash)
    end

    def get_card_atom(card_id:, include_trash: false, **)
      read("get_card_atom", card_id: parse_card_id(card_id, required: true), include_trash: include_trash)
    end

    def get_card_provenance(card_id: nil, event_id: nil, action_id_range: nil, **)
      min, max = parse_action_id_range(action_id_range)
      read("get_card_provenance", card_id: parse_card_id(card_id, required: false), event_id: event_id,
                                  action_id_min: min, action_id_max: max)
    end

    def list_references(card_id:, ref_type: nil, include_trash: false, **)
      read("list_references", card_id: parse_card_id(card_id, required: true), ref_type: ref_type,
                              include_trash: include_trash)
    end

    def list_atoms_by_type(type_name:, limit: nil, include_trash: false, **)
      read("list_atoms_by_type", type_name: type_name, limit: limit, include_trash: include_trash)
    end

    # ---- aggregate (reuse /space_stats) ----
    def atom_types
      space_stats_raw.fetch("by_kind", {}).keys
    end

    def atom_count_by_type
      space_stats_raw.fetch("by_kind", {})
    end

    def space_stats
      raw = space_stats_raw
      { atom_count: raw["atom_count"], types: raw.fetch("by_kind", {}), mirror_lag: 0 }
    end

    # ---- quarantine: FAIL CLOSED until the sidecar B3 admin surface lands (Codex) ----
    def quarantine_list
      raise ServiceUnavailable, "quarantine unavailable: sidecar admin (B3) surface not implemented"
    end

    def quarantine_delete(_id)
      raise ServiceUnavailable, "quarantine unavailable: sidecar admin (B3) surface not implemented"
    end

    private

    def read(op, **filters)
      body = { op: op }.merge(filters.compact)
      status, parsed = self.class.request(:post, "/read", body)
      unless status == 200 && parsed.is_a?(Hash) && parsed["results"].is_a?(Array)
        raise ServiceUnavailable, "sidecar /read #{op} failed (HTTP #{status})"
      end

      parsed["results"].map { |raw| to_atom(raw) }
    rescue *SOCKET_ERRORS => e
      raise ServiceUnavailable, "sidecar unreachable: #{e.class}: #{e.message}"
    end

    def space_stats_raw
      status, parsed = self.class.request(:get, "/space_stats", nil)
      raise ServiceUnavailable, "sidecar /space_stats failed (HTTP #{status})" unless status == 200 && parsed.is_a?(Hash)

      parsed
    rescue *SOCKET_ERRORS => e
      raise ServiceUnavailable, "sidecar unreachable: #{e.class}: #{e.message}"
    end

    # {atom, fields:[[name, tagged_value]]} -> Atomspace::Atom with the ids associated_card_ids needs.
    def to_atom(raw)
      fields = (raw["fields"] || []).each_with_object({}) { |(n, v), h| h[n] = decode_value(v) }
      case raw["atom"]
      when "DeckoCard"
        Atom.new(type: "DeckoCard", card_id: fields["Id"], fields: fields)
      when "DeckoReference"
        Atom.new(type: "DeckoReference", card_id: fields["RefererId"], referer_id: fields["RefererId"],
                 referee_id: integer_or_nil(fields["RefereeId"]), fields: fields)
      when "DeckoProvenance"
        Atom.new(type: "DeckoProvenance", card_id: fields["card_id"], fields: fields)
      else
        Atom.new(type: raw["atom"], fields: fields)
      end
    end

    # type-tagged JSON value -> ruby scalar. {"sym"=>x} renders as the symbol name string; primitives
    # (int/string/bool) pass through; an EXPR field (provenance `changes`) arrives already as a string.
    def decode_value(value)
      value.is_a?(Hash) && value.key?("sym") ? value["sym"] : value
    end

    def integer_or_nil(value)
      value.is_a?(Integer) ? value : nil   # an Unresolved RefereeId ("Unresolved" sym) -> nil
    end

    # Strict integer parse for a PUBLIC card-id read input. Never coerce "abc" -> 0 (Codex): a
    # non-integer is a 400 InvalidRequest. nil/blank -> nil (allowed only when not required).
    def parse_card_id(value, required:)
      if value.nil? || value.to_s.strip.empty?
        raise InvalidRequest, "card_id is required" if required

        return nil
      end
      Integer(value.to_s.strip, 10)
    rescue ArgumentError, TypeError
      raise InvalidRequest, "card_id must be an integer: #{value.inspect}"
    end

    # query_atoms pattern -> a structured field-equality filter {kind?, fields?}. Locks the transport
    # boundary (Codex): accepts a Hash, an ActionController::Parameters, or a JSON string; rejects
    # anything else (and a non-object `fields`) as InvalidRequest. Free-form MeTTa templates: Phase 5.
    def normalize_pattern(raw)
      parsed = coerce_pattern(raw)
      raise InvalidRequest, "query_atoms pattern must be an object {kind?, fields?}" unless parsed.is_a?(Hash)

      parsed = stringify_keys(parsed)
      if parsed.key?("kind") || parsed.key?("fields")
        out = {}
        out["kind"] = parsed["kind"] if parsed["kind"]
        if parsed.key?("fields")
          raise InvalidRequest, "query_atoms pattern.fields must be an object" unless parsed["fields"].is_a?(Hash)

          out["fields"] = stringify_keys(parsed["fields"])
        end
        out
      else
        { "fields" => parsed }   # a bare {name => value} field-equality map
      end
    end

    def coerce_pattern(raw)
      return JSON.parse(raw) if raw.is_a?(String)
      return raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)   # ActionController::Parameters

      raw
    rescue JSON::ParserError => e
      raise InvalidRequest, "query_atoms pattern is not valid JSON: #{e.message}"
    end

    def stringify_keys(hash)
      hash.each_with_object({}) { |(k, v), h| h[k.to_s] = v }
    end

    # action_id_range -> [min, max] inclusive. Accepts "MIN-MAX" (either side omittable), or "N" (=> N,N).
    # Blank/nil -> no bound. Non-numeric / min>max -> ArgumentError (the controller renders 400). Reconcile
    # provenance (null action_id) is excluded sidecar-side when any bound is set.
    def parse_action_id_range(range)
      return [nil, nil] if range.nil? || range.to_s.strip.empty?

      str = range.to_s.strip
      if str.include?("-")
        min_s, max_s = str.split("-", 2)
        min = min_s.empty? ? nil : Integer(min_s)
        max = max_s.empty? ? nil : Integer(max_s)
        raise InvalidRequest, "action_id_range min > max: #{range.inspect}" if min && max && min > max

        [min, max]
      else
        n = Integer(str)
        [n, n]
      end
    rescue ArgumentError, TypeError => e
      raise InvalidRequest, "invalid action_id_range #{range.inspect} (expected 'MIN-MAX', 'MIN-', '-MAX', or 'N'): #{e.message}"
    end
  end
end
