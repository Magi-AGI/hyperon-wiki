#!/usr/bin/env ruby
# Dumps the Ruby ingest naming helpers' output as JSON so the Python port in
# scripts/pipeline/transcript_card_names.py can be diffed against the real
# implementation instead of against hand-written guesses.
#
# Usage: ruby scripts/tests/dump_ruby_card_names.rb <records.json>
#   where records.json is a list of {meeting_name, date, transcript_id}.

require "json"
require "set"

ENV["TRANSCRIPT_INGEST"] = nil
ENV["TRANSCRIPT_INGEST_DRY_RUN"] = "1"

script = File.expand_path("../ingest_transcripts.rb", __dir__)
src = File.read(script)

# Load only the helper definitions, not the main entrypoint: everything up to
# the first top-level invocation. The helpers are pure string functions.
cut = src.index(/^# =+\n# Main\n/) || src.length
eval(src[0...cut]) # rubocop:disable Security/Eval

records = JSON.parse(File.read(ARGV[0]))
transcripts = records.map do |r|
  { meeting_name: r["meeting_name"], date: r["date"],
    transcript_id: r["transcript_id"] }
end

assign_transcript_labels(transcripts)

puts JSON.generate(transcripts.map { |t|
  { "card_name" => t[:card_name], "card_key" => t[:card_key],
    "label" => t[:label], "label_reason" => t[:label_reason] }
})
