# frozen_string_literal: true

# Level 4 bootstrap entry: `rake atomspace_mirror:bootstrap` (a.k.a. `decko atomspace_mirror:bootstrap`).
# Thin wrapper over Bootstrap#run (the runner owns the advisory lock + single-run guard + sweep +
# completion). Operator runbook: ensure a FRESH (empty) sidecar Space first (Option A) -- restart the
# sidecar before running; a failed run is marked 'failed' and must be re-run from scratch.
namespace :atomspace_mirror do
  desc "First-time bootstrap: sweep all cards into the Hyperon Space (Section 1 / Level 4)."
  task bootstrap: :environment do
    run = Bootstrap.new.run
    puts "[atomspace_mirror] bootstrap completed: run=#{run.id} a_start=#{run.a_start} " \
         "cards_swept=#{run.cards_swept} last_card_id_swept=#{run.last_card_id_swept}"
  end
end
