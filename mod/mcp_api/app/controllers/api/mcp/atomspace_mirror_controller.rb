# frozen_string_literal: true

require_relative "../../../../lib/atomspace/errors"
require_relative "../../../../lib/atomspace/read_client"
require_relative "../../../../lib/atomspace/read_consistency_port"
require_relative "../../../../lib/atomspace/observability"
# Decko's routes.rb `require`s controllers at boot, before the mod's concerns autoload
# resolves; load the concern explicitly so `include AtomspaceReadFilter` can't NameError.
require_relative "../../concerns/atomspace_read_filter"

module Api
  module Mcp
    # Lane C, Level 9 read surface. Lives in mod/mcp_api (NOT Lane A's mod/atomspace_mirror
    # engine). Gated by the mcp:atomspace:read scope; quarantine additionally needs mcp:admin.
    # Auth-on-read via Card::Auth.as multi-card filter (Invariant 9). Read-your-writes via the
    # L7 ReadConsistencyPort. Aggregate tools are gate-only (no card-scoped payload).
    class AtomspaceMirrorController < BaseController
      include AtomspaceReadFilter

      before_action :require_atomspace_read_scope!, except: %i[quarantine_index quarantine_delete]
      before_action :require_quarantine_scope!, only: %i[quarantine_index quarantine_delete]
      rescue_from Atomspace::ServiceUnavailable, with: :render_read_client_unavailable
      # Read-your-writes before Lane A's L7 read_consistency is wired -> fail-closed 503, not a
      # generic 500, AND with a distinct signal reason for triage (Codex Findings 4 + 2).
      rescue_from Atomspace::ReadConsistencyPort::NotWired, with: :render_consistency_unavailable

      # --- card-scoped, read-your-writes-aware ---
      def query_atoms
        return unless ready?(params[:wait_for_event_id])

        render_card_scoped read_client.query_atoms(
          pattern: params.require(:pattern), limit: params[:limit],
          include_trash: truthy(params[:include_trash])
        )
      end

      def get_card_atom
        return unless ready?(params[:wait_for_event_id])

        render_card_scoped read_client.get_card_atom(
          card_id: params.require(:card_id), include_trash: truthy(params[:include_trash])
        )
      end

      def get_card_provenance
        return unless ready?(params[:wait_for_event_id])

        render_card_scoped read_client.get_card_provenance(
          card_id: params[:card_id], event_id: params[:event_id],
          action_id_range: params[:action_id_range]
        )
      end

      def list_references
        return unless ready?(params[:wait_for_event_id])

        render_card_scoped read_client.list_references(
          card_id: params.require(:card_id), ref_type: params[:ref_type],
          include_trash: truthy(params[:include_trash])
        )
      end

      def list_atoms_by_type
        return unless ready?(params[:wait_for_event_id])

        render_card_scoped read_client.list_atoms_by_type(
          type_name: params.require(:type_name), limit: params[:limit],
          include_trash: truthy(params[:include_trash])
        )
      end

      # --- aggregate / global: gate-only, NO card-scoped payload, NOT card-filtered ---
      def atom_types
        render_global(read_client.atom_types)
      end

      def atom_count_by_type
        render_global(read_client.atom_count_by_type)
      end

      def space_stats
        render_global(read_client.space_stats)
      end

      # --- admin quarantine (mcp:atomspace:read + mcp:admin) ---
      def quarantine_index
        render_global(read_client.quarantine_list)
      end

      def quarantine_delete
        read_client.quarantine_delete(params.require(:id))
        head :no_content
      end

      private

      def read_client
        @read_client ||= Atomspace::ReadClient.for(account: @current_mcp_account)
      end

      # Pre-query readiness poll. Returns false (after rendering a terminal error) when the
      # event is not ready; true when ready or no wait requested. Releases the AR connection
      # across the sleep window so RYW polling cannot starve the pool (Gemini #1).
      def ready?(event_id)
        return true if event_id.blank?

        deadline = monotonic + max_wait
        loop do
          case Atomspace::ReadConsistencyPort.check_event_ready(event_id)
          when :ready
            return true
          when :failed
            return render_err(503, "event_failed", event_id)
          when :integrity_error
            Atomspace::Observability.alert(signal_class: 4,
                                           payload: { signal: "mirror_integrity", event_id: event_id })
            return render_err(409, "mirror_integrity", event_id)
          else # :not_yet / :not_yet_inserted
            return render_err(503, "staleness_timeout", event_id) if monotonic >= deadline

            ActiveRecord::Base.clear_active_connections!
            sleep poll_interval
          end
        end
      end

      def render_card_scoped(atoms)
        render json: {
          results: filter_by_read_auth(atoms, @current_mcp_account).map(&:to_h),
          _meta: Atomspace::ReadClient.safe_watermark_meta.merge(limit_semantics: "pre_auth_best_effort")
        }
      end

      def render_global(payload)
        render json: { results: payload, _meta: Atomspace::ReadClient.safe_watermark_meta }
      end

      def render_err(code, err, event_id)
        render json: { error: err, event_id: event_id, _meta: Atomspace::ReadClient::SAFE_META }, status: code
        false
      end

      def render_read_client_unavailable(_error)
        render_unavailable("read_client_unbound")
      end

      def render_consistency_unavailable(_error)
        render_unavailable("read_consistency_not_wired")
      end

      def render_unavailable(reason)
        Atomspace::Observability.alert(signal_class: 3, payload: { signal: reason })
        render json: { error: "atomspace_unavailable", reason: reason, _meta: Atomspace::ReadClient::SAFE_META },
               status: 503
      end

      # Auth gates. Match the mcp_api render-and-halt idiom: a before_action that renders sets
      # performed? and halts the filter chain + action (verified by request spec). Codex 2.
      def require_atomspace_read_scope!
        render_forbidden("mcp:atomspace:read scope required") unless token_scopes.include?("mcp:atomspace:read")
      end

      def require_quarantine_scope!
        granted = token_scopes.include?("mcp:atomspace:read") && token_scopes.include?("mcp:admin")
        render_forbidden("mcp:atomspace:read + mcp:admin required") unless granted
      end

      def token_scopes
        ((@current_mcp_payload && @current_mcp_payload["scope"]) || "").split
      end

      def render_forbidden(detail)
        render json: { error: "forbidden", detail: detail }, status: :forbidden
      end

      def max_wait
        (ENV["READ_YOUR_WRITES_MAX_WAIT_SECONDS"] || 2).to_f
      end

      def poll_interval
        (ENV["READ_YOUR_WRITES_POLL_INTERVAL_MS"] || 50).to_f / 1000.0
      end

      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def truthy(value)
        ActiveModel::Type::Boolean.new.cast(value)
      end
    end
  end
end
