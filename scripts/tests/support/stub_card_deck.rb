# A fake Decko deck for the delta applier's offline tests.
#
# WHY THIS EXISTS
#   Without a Card API the applier refuses at its card_api_available? gate, so
#   every offline refusal probe used to stop *before* the write path existed at
#   all. "Zero writes" was then only the absence of an opportunity, and the
#   counters in the apply report were self-reported.
#
#   This file supplies just enough Card/Card::Act/Card::Auth/ActiveRecord for
#   the applier to walk its whole live phase, and RECORDS EVERY MUTATING CALL
#   it receives. A refusal probe run against this stub is therefore positive
#   evidence: the applier reached a state where it *could* have written, and
#   the recorder is empty.
#
#   Mutating calls that the applier must never make at all (destroy, delete,
#   trash=, save, name=, update_column, raw SQL) are recorded AND raise, so a
#   future edit that introduces one fails loudly instead of being counted.
#
# WHAT IT IS NOT
#   Not a Decko emulator. Name keys, left_id ancestry, content hashing, trash
#   and act ids are modelled because the applier's invariants read them;
#   everything else is absent on purpose, so a test cannot accidentally come to
#   depend on Decko behaviour this file only guesses at.
#
# ENV CONTRACT (set by the test harness, not by a human):
#   STUB_DECK_CARDS     path to a JSON array of card fixtures (see boot!)
#   STUB_MUTATION_LOG   path the recorder is dumped to at exit
#   STUB_ALLOW_WRITES   "1" lets create!/update! actually mutate the fake deck;
#                       anything else makes them record and raise, which is how
#                       a refusal probe proves it never got that far
#   STUB_DB_HOST        database host the ActiveRecord stub reports

require "json"
require "digest"

module StubDeck
  # Calls that are legitimate for the applier to make, but must be counted.
  WRITE_OPS = %w[create update].freeze
  # Calls that must never happen. Recorded and raised.
  FORBIDDEN_OPS = %w[destroy delete trash_assign save save_bang update_column
                     update_attribute update_all delete_all destroy_all rename
                     raw_sql].freeze

  class ForbiddenCall < StandardError; end
  class WriteRefused < StandardError; end

  class << self
    def mutations
      @mutations ||= []
    end

    def cards
      @cards ||= []
    end

    def acts
      @acts ||= []
    end

    # Cards the fake deck created on its own, the way Decko creates a missing
    # left card when a "+child" is created. Kept OUT of `mutations` on
    # purpose: mutations are calls the APPLIER made, and conflating the two
    # would make "the applier touched exactly one card" untestable.
    def autovivified
      @autovivified ||= []
    end

    def allow_writes?
      ENV["STUB_ALLOW_WRITES"] == "1"
    end

    def record!(op, detail = {})
      mutations << { "op" => op.to_s }.merge(detail.transform_keys(&:to_s))
    end

    # A forbidden call is recorded first, so the evidence survives the raise.
    def forbidden!(op, detail = {})
      record!(op, detail)
      raise ForbiddenCall, "stub deck: forbidden call #{op} #{detail.inspect}"
    end

    # A permitted write still refuses unless the harness opted in, so the
    # default posture of the stub matches the default posture of the applier.
    def gate_write!(op, detail = {})
      record!(op, detail)
      return if allow_writes?

      raise WriteRefused,
            "stub deck: #{op} attempted without STUB_ALLOW_WRITES=1 #{detail.inspect}"
    end

    # Approximates Decko's key the same way the applier and planner do when
    # Cardname is absent. Cardname is deliberately NOT defined by this stub:
    # defining a half-right Cardname would make the applier's name handling
    # agree with a fiction rather than with its own fallback.
    def key(name)
      name.to_s.split("+").map do |part|
        part.gsub(/([a-z0-9])([A-Z])/, '\1_\2')
            .downcase
            .gsub(/[^a-z0-9]+/, "_")
            .gsub(/\A_+|_+\z/, "")
      end.join("+")
    end

    def next_id
      @next_id = (@next_id || cards.map(&:id).max.to_i) + 1
    end

    def next_act_id
      @next_act_id = (@next_act_id || acts.map { |a| a["id"] }.max.to_i) + 1
    end

    def by_key
      cards.each_with_object({}) { |c, acc| acc[key(c.name)] = c }
    end

    def find_by_name(name)
      by_key[key(name)]
    end

    def find_by_id(id)
      cards.find { |c| c.id == id }
    end

    # Fixture shape, one hash per card:
    #   { "name" => "Raw Data+transcripts+X", "content" => "...",
    #     "type_name" => "RawData", "trash" => false }
    # left_id is resolved from the name, so a fixture cannot describe an
    # ancestry its own names contradict - except deliberately, via "left".
    def boot!
      path = ENV["STUB_DECK_CARDS"].to_s
      fixtures = path.empty? ? [] : JSON.parse(File.read(path))
      @cards = fixtures.each_with_index.map do |f, i|
        StubCard.new(
          id: f["id"] || (100 + i),
          name: f["name"],
          content: f["content"].to_s,
          type_name: f.fetch("type_name", "RawData"),
          trash: f.fetch("trash", false),
          explicit_left: f["left"]
        )
      end
      @next_id = nil
      # A fixture naming "A+b+c" implies "A+b" exists, because in Decko it
      # must: left cards are real cards. Materialising them here keeps the
      # fixture files short without making the ancestry a fiction.
      @cards.reject(&:explicit_left).map(&:name).each { |n| ensure_ancestors!(n) }
      resolve_left_ids!
      @acts = Array(fixtures.first && fixtures.first["_acts"]) if fixtures.first
      @acts ||= []
      @acts = [{ "id" => 1000, "card_ids" => [] }] if @acts.empty?
      @next_act_id = nil
      @autovivified = []
    end

    # Create every missing intermediate card above `name`, shallowest first.
    # Returns the names it had to create.
    def ensure_ancestors!(name, record: false)
      parts = name.to_s.split("+")
      created = []
      (1...parts.length).each do |i|
        ancestor = parts[0...i].join("+")
        next if find_by_name(ancestor)

        cards << StubCard.new(id: next_id, name: ancestor, content: "",
                              type_name: "Basic", trash: false)
        created << ancestor
      end
      return created if created.empty?

      resolve_left_ids!
      if record
        created.each do |n|
          autovivified << n
          log_act!(find_by_name(n).id)
        end
      end
      created
    end

    def resolve_left_ids!
      index = by_key
      cards.each do |c|
        target = c.explicit_left || begin
          parts = c.name.to_s.split("+")
          parts.length > 1 ? parts[0..-2].join("+") : nil
        end
        c.left_id = target ? index[key(target)]&.id : nil
      end
    end

    # Record an act the way Decko would, so the applier's act audit has
    # something real to read.
    def log_act!(card_id)
      acts << { "id" => next_act_id, "card_ids" => [card_id] }
    end

    def register!(card)
      cards << card
      resolve_left_ids!
      log_act!(card.id)
      card
    end

    def dump
      { "mutations" => mutations,
        "write_ops" => mutations.count { |m| WRITE_OPS.include?(m["op"]) },
        "forbidden_ops" => mutations.count { |m| FORBIDDEN_OPS.include?(m["op"]) },
        "autovivified" => autovivified,
        "cards_final" => cards.reject(&:trash).length }
    end

    def flush!
      path = ENV["STUB_MUTATION_LOG"].to_s
      return if path.empty?

      File.write(path, JSON.pretty_generate(dump))
    end
  end
end

class StubCard
  attr_reader :id, :explicit_left
  attr_accessor :content, :type_name, :trash, :left_id

  def initialize(id:, name:, content:, type_name:, trash:, explicit_left: nil)
    @id = id
    @name = name
    @content = content
    @type_name = type_name
    @trash = trash
    @explicit_left = explicit_left
  end

  def name
    @name
  end

  # ---- the one permitted mutation on an existing card -------------------
  def update!(attrs)
    StubDeck.gate_write!(:update, card: @name, id: @id,
                                  keys: attrs.keys.map(&:to_s),
                                  chars: attrs[:content].to_s.length)
    attrs.each do |k, v|
      case k.to_sym
      when :content then @content = v.to_s
      when :type_code then @type_name = v.to_s == "raw_data" ? "RawData" : v.to_s
      else StubDeck.forbidden!(:update_unexpected_attribute, card: @name, attr: k.to_s)
      end
    end
    StubDeck.log_act!(@id)
    self
  end

  # ---- everything below must never be called ---------------------------
  def destroy(*)        = StubDeck.forbidden!(:destroy, card: @name)
  def destroy!(*)       = StubDeck.forbidden!(:destroy, card: @name)
  def delete(*)         = StubDeck.forbidden!(:delete, card: @name)
  def delete!(*)        = StubDeck.forbidden!(:delete, card: @name)
  def save(*)           = StubDeck.forbidden!(:save, card: @name)
  def save!(*)          = StubDeck.forbidden!(:save_bang, card: @name)
  def update_column(*)  = StubDeck.forbidden!(:update_column, card: @name)
  def update_attribute(*) = StubDeck.forbidden!(:update_attribute, card: @name)
  def update(*)         = StubDeck.forbidden!(:update_non_bang, card: @name)

  # Setters cannot use the endless-def form.
  def trash=(_value)
    StubDeck.forbidden!(:trash_assign, card: @name)
  end

  def name=(_value)
    StubDeck.forbidden!(:rename, card: @name)
  end
end

# ------------------------------------------------------------
# Card / Card::Act / Card::Auth
# ------------------------------------------------------------
class Card
  class Relation
    def initialize(records) = @records = records
    def to_a = @records
    def count = @records.length
    def length = @records.length
    def maximum(attr) = @records.map { |r| r.public_send(attr) }.max
    def each(&block) = @records.each(&block)
    def update_all(*) = StubDeck.forbidden!(:update_all)
    def delete_all(*) = StubDeck.forbidden!(:delete_all)
    def destroy_all(*) = StubDeck.forbidden!(:destroy_all)
  end

  module Auth
    def self.as_bot
      yield
    end

    def self.current_id = 1
  end

  class Act
    class ActionRow
      attr_reader :card_id

      def initialize(card_id) = @card_id = card_id
    end

    class Row
      attr_reader :id, :actions

      def initialize(id:, card_ids:)
        @id = id
        @actions = card_ids.map { |cid| ActionRow.new(cid) }
      end
    end

    def self.all_rows
      StubDeck.acts.map { |a| Row.new(id: a["id"], card_ids: Array(a["card_ids"])) }
    end

    def self.count = StubDeck.acts.length

    def self.maximum(attr)
      attr.to_s == "id" ? StubDeck.acts.map { |a| a["id"] }.max : nil
    end

    def self.where(cond)
      rows = all_rows
      if cond.is_a?(Hash) && cond.key?(:id)
        wanted = cond[:id]
        rows = rows.select { |r| wanted.is_a?(Range) ? wanted.cover?(r.id) : wanted == r.id }
      end
      Relation.new(rows)
    end
  end

  class Config
    def try(method, *args)
      respond_to?(method) ? public_send(method, *args) : nil
    end

    def deck_origin = ENV["STUB_DECK_ORIGIN"]
  end

  def self.config = (@config ||= Config.new)

  def self.fetch(identifier, *_rest)
    identifier.is_a?(Integer) ? StubDeck.find_by_id(identifier)
                              : StubDeck.find_by_name(identifier)
  end

  def self.where(cond)
    records =
      case cond
      when Hash
        StubDeck.cards.select do |c|
          cond.all? do |k, v|
            case k.to_sym
            when :trash then c.trash == v
            when :left_id then Array(v).include?(c.left_id)
            when :id then Array(v).include?(c.id)
            else false
            end
          end
        end
      else
        StubDeck.forbidden!(:raw_sql, where: cond.to_s)
      end
    Relation.new(records)
  end

  def self.create!(attrs)
    name = attrs[:name] || attrs["name"]
    StubDeck.gate_write!(:create, card: name.to_s,
                                  type_code: (attrs[:type_code] || attrs["type_code"]).to_s,
                                  chars: (attrs[:content] || attrs["content"]).to_s.length)
    # Decko creates a missing left card implicitly rather than refusing, and
    # the applier's card-count invariant has to tolerate exactly that, so the
    # stub reproduces it. Recorded separately from the applier's own calls.
    StubDeck.ensure_ancestors!(name.to_s, record: true)
    card = StubCard.new(
      id: StubDeck.next_id, name: name.to_s,
      content: (attrs[:content] || attrs["content"]).to_s,
      type_name: "RawData", trash: false
    )
    StubDeck.register!(card)
  end

  def self.create(*) = StubDeck.forbidden!(:create_non_bang)
  def self.delete_all(*) = StubDeck.forbidden!(:delete_all)
  def self.destroy_all(*) = StubDeck.forbidden!(:destroy_all)
end

# ------------------------------------------------------------
# ActiveRecord, only as much as the db-host gate reads
# ------------------------------------------------------------
module ActiveRecord
  class Base
    class DbConfig
      def configuration_hash
        { host: ENV.fetch("STUB_DB_HOST", "127.0.0.1"),
          database: "stub_deck", adapter: "postgresql" }
      end
    end

    class Connection
      def execute(*) = StubDeck.forbidden!(:raw_sql, via: "execute")
      def exec_query(*) = StubDeck.forbidden!(:raw_sql, via: "exec_query")
      def exec_update(*) = StubDeck.forbidden!(:raw_sql, via: "exec_update")
      def exec_delete(*) = StubDeck.forbidden!(:raw_sql, via: "exec_delete")
      def select_all(*) = StubDeck.forbidden!(:raw_sql, via: "select_all")
    end

    def self.connection_db_config = DbConfig.new
    def self.connection = (@connection ||= Connection.new)
  end
end
