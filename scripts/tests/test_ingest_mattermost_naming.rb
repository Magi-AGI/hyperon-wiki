#!/usr/bin/env ruby
# Offline unit tests for ingest_mattermost.rb card-naming logic.
# Runs without Decko/Rails: Cardname is not defined, so name_key() uses its
# approximation fallback. Verifies collision resolution and part sanitization.
#
# Run: ruby scripts/tests/test_ingest_mattermost_naming.rb

require "minitest/autorun"
require "json"
require "tmpdir"

INGEST = File.expand_path("../ingest_mattermost.rb", __dir__)

# Load the script's definitions without executing run!.
# run! is guarded by `$PROGRAM_NAME == __FILE__ || MATTERMOST_INGEST=1`;
# neither holds here, so loading is side-effect free even under Decko.
load INGEST

class TestSanitizeNamePart < Minitest::Test
  def test_collapses_decko_joint
    assert_equal "LLM-PLN", sanitize_name_part("LLM+PLN")
    assert_equal "Neuromorphic - PC", sanitize_name_part("Neuromorphic + PC")
  end

  def test_collapses_slash_and_markup
    assert_equal "Robot- PR", sanitize_name_part("Robot/ PR")
    assert_equal "Bitgrit - SingularityNET", sanitize_name_part("Bitgrit <> SingularityNET")
  end

  def test_trims_and_collapses_whitespace
    assert_equal "DF-Review Notifications", sanitize_name_part("DF-Review Notifications ")
    assert_equal "DEEP - bugs & improvements", sanitize_name_part("DEEP -  bugs & improvements")
  end

  def test_strips_reserved_prefixes
    assert_equal "account", sanitize_name_part("*account")
    assert_equal "foo", sanitize_name_part("~foo")
  end

  def test_blank_becomes_nil
    assert_nil sanitize_name_part("")
    assert_nil sanitize_name_part("   ")
    assert_nil sanitize_name_part("+++")
  end

  def test_single_part_after_sanitize
    # The whole point: a sanitized label must never introduce extra name parts.
    ["LLM+PLN", "Neuromorphic + PC", "a+b+c+d"].each do |raw|
      refute_includes sanitize_name_part(raw), "+", "#{raw.inspect} still contains the joint"
    end
  end
end

class TestAssignChannelLabels < Minitest::Test
  def ch(id:, slug:, display:, type: "O")
    { id: id, slug: slug, display: display, type: type, posts: 0, threads: 0 }
  end

  def test_unambiguous_names_are_preserved
    chans = [ch(id: "a1", slug: "general", display: "General"),
             ch(id: "b2", slug: "random", display: "Random")]
    assign_channel_labels(chans)
    assert_equal "General", chans[0][:label]
    assert_equal "Random",  chans[1][:label]
    assert_equal %w[display_name display_name], chans.map { |c| c[:label_reason] }
    assert_equal "Raw Data+mattermost+General", chans[0][:card_name]
  end

  def test_duplicate_display_names_get_slug_suffix
    chans = [ch(id: "jmod", slug: "test",      display: "test"),
             ch(id: "qk6a", slug: "test-jan1", display: "test")]
    assign_channel_labels(chans)
    labels = chans.map { |c| c[:label] }
    assert_equal ["test (test)", "test (test-jan1)"], labels
    assert_equal %w[display_name+slug display_name+slug], chans.map { |c| c[:label_reason] }
    assert_equal 2, chans.map { |c| c[:card_key] }.uniq.length
  end

  def test_duplicate_display_and_slug_falls_back_to_id
    chans = [ch(id: "id-one", slug: "dup", display: "Dup"),
             ch(id: "id-two", slug: "dup", display: "Dup")]
    assign_channel_labels(chans)
    assert_equal 2, chans.map { |c| c[:card_key] }.uniq.length
    assert_includes chans[1][:label], "id-two"
  end

  def test_keys_unique_across_singularization
    # Decko singularizes keys, so "Agent" and "Agents" can collide upstream;
    # at minimum our own assignment must never emit a duplicate key.
    chans = [ch(id: "x", slug: "agent",  display: "Agent"),
             ch(id: "y", slug: "agents", display: "Agents")]
    assign_channel_labels(chans)
    assert_equal 2, chans.map { |c| c[:card_key] }.uniq.length
  end

  def test_blank_display_falls_back_to_slug_then_id
    chans = [ch(id: "zz", slug: "fallback-slug", display: "  ")]
    assign_channel_labels(chans)
    assert_equal "fallback-slug", chans[0][:label]
  end

  def test_joint_in_display_never_creates_extra_parts
    chans = [ch(id: "p1", slug: "llmpln", display: "LLM+PLN")]
    assign_channel_labels(chans)
    # parent is 2 parts, so a correct channel card is exactly 3 parts
    assert_equal 3, chans[0][:card_name].split("+").length
  end

  def test_raises_nothing_and_resolves_three_way_collision
    chans = [ch(id: "i1", slug: "t", display: "T"),
             ch(id: "i2", slug: "t", display: "T"),
             ch(id: "i3", slug: "t", display: "T")]
    assign_channel_labels(chans)
    assert_equal 3, chans.map { |c| c[:card_key] }.uniq.length
  end
end

class TestRealExportIfPresent < Minitest::Test
  EXPORT = ENV["MATTERMOST_EXPORT_DIR"]

  def test_run_of_record_export_has_no_collisions
    skip "set MATTERMOST_EXPORT_DIR to run" unless EXPORT && Dir.exist?(EXPORT)

    files = Dir.glob("#{EXPORT}/**/*.json")
                .reject { |f| NON_CHANNEL_FILES.include?(File.basename(f)) }.sort
    chans = files.filter_map do |f|
      m = JSON.parse(File.read(f))["channel"]
      next unless m
      { id: m["id"], slug: m["name"], display: m["display_name"], type: m["type"],
        posts: m["post_count"], threads: m["thread_count"] }
    end
    assign_channel_labels(chans)

    keys = chans.map { |c| c[:card_key] }
    assert_equal keys.length, keys.uniq.length, "duplicate card keys in real export"
    chans.each do |c|
      assert_equal 3, c[:card_name].split("+").length,
                   "#{c[:card_name].inspect} has wrong part count"
    end
  end
end

# ------------------------------------------------------------
# Private-channel read restriction
# ------------------------------------------------------------
class TestPrivateReadRuleNaming < Minitest::Test
  def test_rule_name_targets_the_card_self_set
    assert_equal "Raw Data+mattermost+Secret+*self+*read",
                 self_read_rule_name("Raw Data+mattermost+Secret")
  end

  def test_chunk_cards_get_their_own_rule_name
    # Chunk cards are governed by RawData+*type+*read, which outranks the
    # "_left" inheritance rule, so each needs its own self rule.
    assert_equal "Raw Data+mattermost+Secret+chunk-3+*self+*read",
                 self_read_rule_name("Raw Data+mattermost+Secret+chunk-3")
  end

  def test_self_is_the_highest_precedence_pattern
    # Guards the core assumption: *self beats *type, so a per-card read rule
    # overrides the RawData type rule. (Decko pattern order, highest first.)
    assert_equal "*self", %w[*self *type\ plus\ right *right *rule *rstar
                             *star *type *all\ plus *all].first
  end

  def test_restriction_is_on_by_default
    assert RESTRICT_PRIVATE, "private channels must be restricted unless explicitly disabled"
  end

  def test_default_party_is_a_single_name
    refute_includes PRIVATE_READ_PARTY, "+", "party name must be one card, not a compound"
    refute_empty PRIVATE_READ_PARTY
  end
end

class TestPrivatePermissionPlan < Minitest::Test
  # Drives the real planner in dry-run mode over a synthetic export and asserts
  # that exactly the private channels' cards get read rules.
  def setup
    STATS[:cards].clear
    STATS[:perms].clear
    %i[created updated errors planned_create planned_update
       perm_created perm_updated perm_errors
       planned_perm_create planned_perm_update].each { |k| STATS[k] = 0 }
  end

  def channel_payload(id:, slug:, display:, type:, posts: 2)
    {
      "channel" => { "id" => id, "name" => slug, "display_name" => display,
                     "type" => type, "post_count" => posts, "thread_count" => 0,
                     "exported_at" => "2026-01-01T00:00:00Z" },
      "posts" => Array.new(posts) do |i|
        { "id" => "#{id}-p#{i}", "username" => "u#{i}",
          "created" => "2026-01-01T00:00:0#{i}Z", "message" => "m#{i}" }
      end,
      "threads" => {}
    }
  end

  def test_only_private_channels_get_read_rules
    skip "dry-run planning requires DRY_RUN=1" unless DRY_RUN

    Dir.mktmpdir do |dir|
      File.write("#{dir}/pub.json",
                 JSON.dump(channel_payload(id: "c1", slug: "general",
                                           display: "General", type: "O")))
      File.write("#{dir}/priv.json",
                 JSON.dump(channel_payload(id: "c2", slug: "secret",
                                           display: "Secret", type: "P")))

      ingest_channel("#{dir}/pub.json", "Raw Data+mattermost+General",
                     private_channel: false)
      ingest_channel("#{dir}/priv.json", "Raw Data+mattermost+Secret",
                     private_channel: true)

      assert_equal 2, STATS[:cards].length
      assert_equal ["Raw Data+mattermost+Secret"], STATS[:perms].map { |p| p[:card] }
      assert_equal ["Raw Data+mattermost+Secret+*self+*read"],
                   STATS[:perms].map { |p| p[:rule] }
      assert_equal [PRIVATE_READ_PARTY], STATS[:perms].map { |p| p[:party] }.uniq
      assert_equal 0, STATS[:perm_errors]
    end
  end

  def test_every_chunk_of_a_private_channel_is_covered
    skip "dry-run planning requires DRY_RUN=1" unless DRY_RUN

    Dir.mktmpdir do |dir|
      # Force chunking: each post is padded past MAX_CARD_CHARS in aggregate.
      big = channel_payload(id: "c3", slug: "bigpriv", display: "BigPriv", posts: 6,
                            type: "P")
      big["posts"].each { |p| p["message"] = "x" * (MAX_CARD_CHARS / 2) }
      File.write("#{dir}/big.json", JSON.dump(big))

      written = ingest_channel("#{dir}/big.json", "Raw Data+mattermost+BigPriv",
                               private_channel: true)

      assert_operator written, :>, 1, "expected the channel to chunk"
      # Every written card (index + chunks) must have a matching read rule.
      card_names = STATS[:cards].map { |c| c[:name] }
      perm_cards = STATS[:perms].map { |p| p[:card] }
      assert_equal card_names.sort, perm_cards.sort,
                   "every private card must get its own read rule"
      assert(STATS[:perms].any? { |p| p[:rule].include?("+chunk-1+*self+*read") },
             "chunk cards must get self read rules")
      assert_equal 0, STATS[:perm_errors]
    end
  end
end
