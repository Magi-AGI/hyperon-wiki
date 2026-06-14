# frozen_string_literal: true

module Atomspace
  # L10 observability adapter seam (Lane C). Phase 4 default writes structured JSON to
  # Rails.logger; deployment-time adapters (CloudWatch/Prometheus/Loki/PagerDuty/SNS) are
  # wired per docs/ATOMSPACE-MIRROR-DEPLOYMENT.md. Signal classes per L10.
  module Observability
    SIGNAL_CLASSES = {
      3 => "sidecar_apply",
      4 => "drift_integrity"
    }.freeze

    def self.alert(signal_class:, payload:)
      Rails.logger.warn(
        { atomspace_signal: signal_class, name: SIGNAL_CLASSES[signal_class] }.merge(payload).to_json
      )
    end
  end
end
