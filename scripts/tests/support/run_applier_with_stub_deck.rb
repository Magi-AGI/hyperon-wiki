# Harness: boot the stub deck, then run the REAL applier inside that process.
#
# This is how the offline suite reaches the applier's live phase. The applier
# is `load`ed, not re-implemented, so the gates, the classifier and the write
# callsites under test are the shipped ones.
#
# The stub deck is booted FIRST and left in place, so by the time the applier
# evaluates its `defined?(Card)` gate there is a Card API - which is the whole
# point: the applier walks all the way to the write callsite and the mutation
# recorder gets to be empty on purpose rather than by default.
#
# The mutation log is flushed from an at_exit hook so it survives the applier's
# own `exit(1)` on refusal.
#
# Invoked by test_apply_transcript_delta.rb; not useful by hand.

require "json"

support = File.expand_path("stub_card_deck.rb", __dir__)
load support
StubDeck.boot!
at_exit { StubDeck.flush! }

# DECK_ORIGIN is read from env by the applier; STUB_DECK_ORIGIN feeds the
# Card.config.deck_origin fallback path so both sources can be tested.
load File.expand_path("../../apply_transcript_delta.rb", __dir__)
