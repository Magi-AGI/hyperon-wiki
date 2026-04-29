# Magi-Archive Development Roadmap

**Project**: Collaborative Knowledge Graph Wiki
**Vision**: Human-readable wiki → Semantic knowledge graph → AI Gamemaster reasoning system
**Status**: Planning → Implementation
**Last Updated**: 2025-10-16

---

## Executive Summary

This roadmap outlines the evolution of magi-archive from a simple Decko wiki to a sophisticated knowledge graph system powering AI-driven gamemastering. The approach is **incremental and validated** - each phase delivers value while building toward the long-term vision.

### Timeline Overview

```
Week 1-2:   Phase 1 - Deploy Decko Wiki (IMMEDIATE)
Month 1-3:  Phase 2 - Knowledge Graph Visualizer
Month 3-6:  Phase 3 - Atomspace Integration Prototype
Month 6-9:  Phase 4 - Atomspace Backend Swap (if validated)
2026+:      Phase 5 - AI Gamemaster Foundation
```

---

## Phase 1: Immediate Wiki Deployment ✅ PRIORITY

**Timeline**: Week 1-2 (Target: October 2025)
**Status**: Not Started

### Goals

1. **Get collaborators/players access to documentation ASAP**
2. **Migrate existing MkDocs content to Decko**
3. **Validate AI assistant (Claude Code) workflow**

### Architecture

```
Players/Collaborators
    ↓
Decko Wiki (Rails)
    ↓
PostgreSQL Database
    ↓
AWS EC2 + RDS
```

**Decision Rationale**:
- PostgreSQL is proven, fast, simple
- Can migrate to Atomspace later once validated
- Atomspace integration is untested - don't block immediate needs

### Tasks

#### Week 1: Deploy Infrastructure
- [x] AWS account setup (if needed)
- [ ] Create RDS PostgreSQL instance (db.t3.micro - free tier)
- [ ] Launch EC2 instance (t3.micro Ubuntu 22.04 - free tier)
- [ ] Configure security groups and Elastic IP
- [ ] Install Ruby 3.1+, Decko, dependencies
- [ ] Configure Nginx reverse proxy
- [ ] Set up SSL with Let's Encrypt
- [ ] Create systemd service for auto-start
- [ ] Deploy Decko application

**Reference**: Follow `AWS-DEPLOYMENT.md` step-by-step

#### Week 2: Content Migration & Onboarding
- [ ] Create card types (GameIdea, Faction, Species, Character, Mechanic, etc.)
- [ ] **Manually import** MkDocs content from:
  - `magi-knowledge-repo` (main content)
  - `magi-knowledge-repo-2` through `magi-knowledge-repo-5` (branches)
- [ ] Review and consolidate duplicate/outdated content
- [ ] Set up card relationships (pointers between related cards)
- [ ] Create user accounts for players/collaborators
- [ ] Write onboarding documentation
- [ ] Share wiki URL and credentials

**Note**: Manual import allows for review, cleanup, and reorganization during migration.

### Success Metrics

- [ ] Wiki accessible at https://yourdomain.com
- [ ] All critical MkDocs content migrated
- [ ] 5+ players/collaborators onboarded
- [ ] Claude Code can create/edit cards in <5 seconds
- [ ] Zero data loss from MkDocs → Decko

### Deliverables

- ✅ Live Decko wiki on AWS EC2
- ✅ All MkDocs repositories consolidated into Decko cards
- ✅ Player/collaborator access documentation
- ✅ AI assistant workflow validated

### Decision Point

**End of Week 2**: Is Decko + PostgreSQL "good enough" for immediate needs?
- ✅ Yes → Proceed to Phase 2 (graph visualizer)
- ❌ No → Troubleshoot or pivot to simpler solution

---

## Phase 2: Knowledge Graph Visualizer 🎯

**Timeline**: Month 1-3 (Nov 2025 - Jan 2026)
**Status**: Not Started
**Goal**: Visualize connections between game concepts; discover unanticipated relationships

### Vision

```
┌─────────────────────────────────────────────────┐
│  Decko Card View                                │
│  ┌───────────────────────────────────────────┐ │
│  │  Game Idea: Butterfly Galaxii             │ │
│  │  [Content] [Graph View] [Edit]            │ │
│  │                                           │ │
│  │  ╔═══════════════════════════════════╗   │ │
│  │  ║    Knowledge Graph Visualization  ║   │ │
│  │  ║                                   ║   │ │
│  │  ║      [Butterfly Galaxii]          ║   │ │
│  │  ║           ↓ has_faction           ║   │ │
│  │  ║      [Korvaxian Empire]           ║   │ │
│  │  ║           ↓ has_species           ║   │ │
│  │  ║      [Korvax Synthetics]          ║   │ │
│  │  ║           ↙ ↘                     ║   │ │
│  │  ║    [Tech]   [Narrative]           ║   │ │
│  │  ║                                   ║   │ │
│  │  ║  💡 Suggested: Korvax → Mining    ║   │ │
│  │  ╚═══════════════════════════════════╝   │ │
│  └───────────────────────────────────────────┘ │
└─────────────────────────────────────────────────┘
```

### Architecture Options

**Option A - Decko Plugin/Mod** (Integrated):
```
Decko Card View
    ↓ (built-in format)
Graph Renderer (D3.js/Cytoscape)
    ↓ (queries)
PostgreSQL (card relationships)
```

**Option B - Standalone Service** (Flexible):
```
Decko Card View
    ↓ (iframe embed)
Graph Visualizer App (React/Vue)
    ↓ (API queries)
Decko REST API
    ↓
PostgreSQL
```

**Recommendation**: **Option B** - Easier to develop independently, can evolve separately from Decko

### Tasks

#### Month 1: Research & Prototype
- [ ] Evaluate visualization libraries:
  - D3.js (most flexible, steep learning curve)
  - Cytoscape.js (graph-focused, good layouts)
  - Vis.js (simpler, network-focused)
  - Sigma.js (performance for large graphs)
- [ ] Extract sample Decko card relationships
- [ ] Build proof-of-concept with 20-30 cards
- [ ] Test different layout algorithms (force-directed, hierarchical, circular)
- [ ] User testing with players: which layout is most useful?

#### Month 2: Core Features
- [ ] Build standalone graph visualizer web app
- [ ] Decko API integration for card data
- [ ] Interactive node exploration (click to expand, drill down)
- [ ] Filter by card type (show only factions, only characters, etc.)
- [ ] Search/highlight nodes
- [ ] Zoom/pan controls
- [ ] Export graph as image/SVG

#### Month 3: Smart Connections
- [ ] **"Unanticipated Connections" Algorithm**:
  - Co-occurrence: Cards mentioned together in content
  - Shared tags: Cards with overlapping metadata
  - Semantic similarity: NLP on card content (cosine similarity)
  - Temporal proximity: Cards created/edited around same time
- [ ] Visual highlighting of suggested relationships
- [ ] One-click "Create Relationship" from suggestion
- [ ] Connection strength indicators (weighted edges)

### Key Features

1. **Explicit Relationships**: Show Decko card pointers/nesting as graph edges
2. **Inferred Relationships**: Algorithm suggests hidden connections
3. **Multi-level Exploration**: Expand node → see connected nodes → expand further
4. **Type-based Filtering**: "Show only Mechanics connected to this Game"
5. **Temporal View**: Slider to see graph evolution over time
6. **Collaborative Annotations**: Players can vote on relationship importance

### Success Metrics

- [ ] Visualizer renders 100+ card graph in <3 seconds
- [ ] 80% of players find "unanticipated connections" useful
- [ ] 10+ new explicit relationships created from suggestions
- [ ] Graph helps identify knowledge gaps (isolated nodes)

### Deliverables

- ✅ Interactive graph visualizer (standalone or embedded)
- ✅ Connection suggestion algorithm
- ✅ User documentation for graph navigation
- ✅ API for programmatic graph queries

### Decision Point

**End of Month 3**: Does graph visualization provide value?
- ✅ Yes → Players actively use it, connections discovered
- ❌ No → Simplified version or deprecate, focus on Atomspace instead

---

## Phase 3: Atomspace Integration Prototype 🔬

**Timeline**: Month 3-6 (Jan - Apr 2026)
**Status**: Not Started
**Goal**: Prove that a **read-only AtomSpace semantic mirror** answers queries Decko/PostgreSQL cannot trivially answer, fast enough to be useful, before committing to any deeper migration.

> **⚠ CLUSTER-PILOT REFRAMING (2026-04-29).** The AtomSpace Backend Integration Cluster Pilot narrowed Phase 3 to **READONLY-ATOMSPACE-BRIDGE**. Decko/Rails/PostgreSQL stays the source of truth. AtomSpace serves a read-only semantic mirror; **NO write-through to DAS or MORK**. The MCP adapter pseudocode in this section uses `from hyperon import Atomspace, MCP` — an **apocryphal API** (Source 2 + Source 4). Treat the diagrams and code below as conceptual sketches; the real Phase 3 architecture uses **Decko MCP for extraction + one of: (a) atomspace-bridge style import, or (b) `mork_ffi` for low-latency queries + `mork_loader.py` for periodic hydration.** The choice between (a) and (b) is the prototype-benchmark decision; both fall under READONLY-ATOMSPACE-BRIDGE. See `docs/ATOMSPACE-INTEGRATION.md` Cluster-Pilot Reframing section and the wiki synthesis card `Implementation Families+AtomSpace Backend Integration` for the canonical post-pilot statements.

### Approach

**Parallel Track** - Don't disrupt live wiki:
```
Production Wiki (Decko + PostgreSQL)
    ↓ (continues serving users)

Experimental Track:
    ↓ (export)
Atomspace Instance
    ↓ (testing)
Performance & Reasoning Evaluation
```

### Architecture

```
┌─────────────────────────────────────────────┐
│  Decko (Production - PostgreSQL)            │
│  ↓ nightly export                           │
├─────────────────────────────────────────────┤
│  MCP Adapter                                │
│  ↓ translates Card API ↔ Atomspace         │
├─────────────────────────────────────────────┤
│  Hyperon Atomspace (Test Instance)         │
│  - MCP server integration                   │
│  - PLN reasoning engine                     │
│  - MORK distributed backend (optional)      │
└─────────────────────────────────────────────┘
```

### Tasks

#### Month 3-4: Setup & Export
- [ ] Install Hyperon locally (development machine)
- [ ] Test Hyperon's MCP server implementation
- [ ] Create **Decko → Atomspace export script**:
  ```ruby
  # Export all cards to Atomspace
  Card.all.each do |card|
    atomspace_client.create_concept(
      name: card.name,
      content: card.content,
      type: card.type,
      relationships: card.pointers
    )
  end
  ```
- [ ] Validate exported data integrity
- [ ] Map Decko card types → Atomspace atom types
- [ ] Set up nightly automated export

#### Month 4-5: Performance Benchmarking
- [ ] Measure query latency:
  - PostgreSQL: `Card.fetch("Alice")` → ~100ms
  - Atomspace (via MCP): `atomspace.query("Alice")` → ???ms
  - **Acceptable threshold**: <2 seconds
- [ ] Test bulk operations:
  - Create 10 cards: PostgreSQL vs Atomspace
  - Search by type: PostgreSQL vs Atomspace
  - Complex relationships: PostgreSQL vs Atomspace
- [ ] Measure Atomspace memory usage with 1000+ cards
- [ ] Test MORK distributed backend (if available)

#### Month 5-6: Reasoning Capabilities
- [ ] Test PLN (Probabilistic Logic Networks):
  - Infer implicit relationships
  - Pattern recognition across cards
  - Semantic similarity queries
- [ ] Example reasoning tasks:
  - "Find all factions that conflict with Korvaxians" (indirect relationships)
  - "Which game mechanics are similar to crafting?" (semantic similarity)
  - "What narrative arcs feature both Alice and the Mining Captain?" (path finding)
- [ ] Compare reasoning results to manual graph analysis
- [ ] Evaluate: Does PLN provide insights PostgreSQL can't?

### MCP Adapter Development

Build bidirectional adapter:

```python
# mcp_adapter.py
class DeckoAtomspaceAdapter:
    """Translate between Decko Card API and Atomspace"""

    def fetch_card(self, name: str) -> Card:
        """Query Atomspace, return Card-like object"""
        atom = self.hyperon_mcp.query(f"(Concept '{name}')")
        return Card(
            name=atom.name,
            content=atom.get_value("content"),
            type=atom.get_type(),
            relationships=atom.get_links()
        )

    def create_card(self, card: Card):
        """Create Atomspace atom from Card"""
        self.hyperon_mcp.create_concept(
            name=card.name,
            content=card.content,
            type_node=card.type
        )
        # Create relationship links
        for rel in card.pointers:
            self.hyperon_mcp.create_link("Pointer", card.name, rel)

    def search_cards(self, query: dict) -> list[Card]:
        """Semantic search in Atomspace"""
        atoms = self.hyperon_mcp.query(query)
        return [self._atom_to_card(a) for a in atoms]
```

### Success Metrics (Cluster-Pilot Refined, 2026-04-29)

**Acceptance gates for the read-only mirror:**
- [ ] **Fetch latency <500ms target / <2s acceptable** for typical card-resolution queries against the mirror (tightened from the original <2s, per cluster-pilot R1.accept-1).
- [ ] **5+ semantic insights** that PostgreSQL+Decko cannot trivially answer (e.g., transitive type chains, cross-game relationship paths, semantic similarity beyond exact-match search). **No claim of PLN global completeness** — the PLN cluster No-Go theorem (xiPLN §5; Lean-proven in `Mettapedia/Logic/PLNJointEvidenceNoGo.lean`) shows that local-rule PLN cannot be globally complete without joint-state information; insights must be characterized as "semantic queries that PostgreSQL cannot trivially answer," not as "PLN global inference."
- [ ] **Mirror handles 1000+ cards without performance degradation** at the chosen latency target.
- [ ] **Mirror loader runs reliably** (0 errors in 10 consecutive runs; periodic re-hydration from Decko MCP / direct DB export).
- [ ] **Decko remains source of truth at all times** — no write-through path, no surprises on Decko trash/restore, no consistency drift caused by AtomSpace state.

### Deliverables

- ✅ Decko-MCP-driven extraction pipeline (Phase 3 mirror loader; not "Atomspace MCP").
- ✅ Read-only mirror seam (one of: atomspace-bridge style import, OR `mork_ffi` + `mork_loader.py`).
- ✅ Performance benchmark report (fetch-latency target validation; mechanism-comparison if both seams prototyped).
- ✅ Semantic-insight catalog (the 5+ queries PostgreSQL cannot trivially answer, with worked examples).
- ✅ Re-hydration / cache-invalidation strategy.

### Decision Point: Go/No-Go

**End of Month 6**: Should we promote the read-only mirror to a permanent Phase-4 production feature, retire it, or restructure?

**✅ Proceed to Phase 4 (read-only mirror as durable feature) if**:
- Fetch latency meets <500ms target (or <2s acceptable with a documented reason).
- ≥5 semantic-insight queries land that PostgreSQL+Decko cannot trivially answer.
- Mirror seam is stable; re-hydration cadence is operationally sustainable.
- Decko stays source of truth with zero observed drift from mirror activity.

**❌ Retire the mirror if**:
- Fetch latency >5 seconds (too slow for interactive use).
- The semantic-insight catalog stays empty or trivially reproducible in PostgreSQL+Decko.
- Mirror loader / FFI maintenance burden outweighs the insight value.
- Drift from Decko (even read-only) introduces user-visible inconsistencies.

**❌ Phase 4 write-through is OUT OF SCOPE** until the AtomSpace cluster-pilot blockers are cleared:
- DAS-MorkDB link/S-expression delete (`MorkDB.cc:268-270` hard-fails) — required for Decko trash/restore semantics.
- MORK server-branch reconciliation (Dockerfile pin / image tag / `origin/server` HEAD).
- Decko-semantic mappings (history, RichText, files, permissions, sections/TOC) defined as AtomSpace types.

**Hybrid Option (likely best end-state)**:
- Keep PostgreSQL+Decko as source of truth for interactive wiki.
- Keep AtomSpace mirror for the small-but-real set of semantic queries that PostgreSQL cannot answer.
- No migration risk; cluster-pilot architecture (R4.B1).

---

## Phase 4: Atomspace Backend Swap 🔄

> **⚠ CLUSTER-PILOT REFRAMING (2026-04-29).** Phase 4 as originally written ("replace PostgreSQL with Atomspace as primary data store") is **BLOCKED** by the AtomSpace Backend Integration Cluster Pilot until: (1) DAS-MorkDB link/S-expression delete is implemented (currently hard-fails at `MorkDB.cc:268-270`); (2) MORK server-branch references (Dockerfile pin / image tag / `origin/server` HEAD) are reconciled; (3) Decko semantics (history, RichText, files, permissions, sections/TOC, rename/aliases, rollback) are defined as AtomSpace types. The diagrams and dual-write code below describe the legacy aspirational Phase 4. The realistic Phase 4 outcome is the **read-only mirror promoted to a durable production feature** (per Phase 3 Decision Point above), not a primary-backend swap. Treat the dual-write / cutover material below as conditional on blocker resolution.

**Timeline**: Month 6-9 (Apr - Jul 2026)
**Status**: Conditional (only if Phase 3 successful)
**Goal**: Replace PostgreSQL with Atomspace as primary data store

### Architecture Transition

**Current (Phase 1-3)**:
```
Decko UI → PostgreSQL
         ↘ (export) → Atomspace (testing)
```

**Target (Phase 4)**:
```
Decko UI → MCP Adapter → Hyperon Atomspace (+ MORK)
```

### Migration Strategy: Dual-Write

**Step 1: Parallel Operation** (Month 6)
```
Decko UI
    ↓
Dual-Write Layer
    ↓           ↓
PostgreSQL   Atomspace
(primary)    (shadow)
```

- All writes go to BOTH databases
- Reads come from PostgreSQL (proven stable)
- Verify Atomspace matches PostgreSQL
- Monitor for data consistency issues

**Step 2: Validation** (Month 7)
```
Decko UI
    ↓
Dual-Write Layer
    ↓           ↓
PostgreSQL   Atomspace
(shadow)     (primary)
```

- Switch reads to Atomspace
- PostgreSQL becomes backup
- Monitor query performance in production
- Rollback to PostgreSQL if issues

**Step 3: Cutover** (Month 8)
```
Decko UI → MCP Adapter → Atomspace (primary)
                         ↓
                    PostgreSQL (archive)
```

- Disable writes to PostgreSQL
- Keep PostgreSQL as archive/backup
- Full migration complete

**Step 4: Cleanup** (Month 9)
- Remove dual-write layer
- Archive PostgreSQL backups to S3
- Document Atomspace-only architecture

### Tasks

#### Month 6: Dual-Write Implementation
- [ ] Build dual-write middleware:
  ```ruby
  class DualWriteAdapter
    def create_card(card)
      # Write to both
      pg_result = PostgreSQL.create(card)
      atom_result = Atomspace.create(card)

      # Verify consistency
      raise if pg_result != atom_result
    end
  end
  ```
- [ ] Deploy to staging environment
- [ ] Run consistency checks hourly
- [ ] Monitor for discrepancies

#### Month 7: Atomspace Primary
- [ ] Switch production reads to Atomspace
- [ ] Performance monitoring (24/7)
- [ ] User acceptance testing with players
- [ ] Rollback plan tested and ready

#### Month 8: PostgreSQL Deprecation
- [ ] Disable PostgreSQL writes
- [ ] Final consistency verification
- [ ] Export PostgreSQL to S3 (archive)
- [ ] Update documentation

#### Month 9: Optimization
- [ ] Remove dual-write overhead
- [ ] Tune Atomspace performance
- [ ] MORK distributed setup (if needed for scale)
- [ ] Monitoring and alerting for Atomspace

### MORK Distributed Backend

**If data grows beyond single node**:

```
┌─────────────────────────────────────────┐
│  MORK Distributed Atomspace             │
│                                         │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐│
│  │ Node 1  │  │ Node 2  │  │ Node 3  ││
│  │ (Games) │  │(Factions)│  │(Chars)  ││
│  └─────────┘  └─────────┘  └─────────┘│
│       ↓           ↓           ↓        │
│  ┌───────────────────────────────────┐ │
│  │    MORK Coordination Layer        │ │
│  └───────────────────────────────────┘ │
└─────────────────────────────────────────┘
```

**Questions to answer**:
- Does MORK provide hosting or self-host?
- Cost comparison: single Atomspace vs MORK cluster?
- Network latency between nodes?

### Success Metrics

- [ ] Zero data loss during migration
- [ ] Query latency ≤ PostgreSQL baseline
- [ ] 100% uptime during transition
- [ ] Players don't notice the backend swap
- [ ] Atomspace handles production load (100+ concurrent users)

### Deliverables

- ✅ Atomspace as primary backend
- ✅ Migration complete, PostgreSQL archived
- ✅ MORK distributed setup (if applicable)
- ✅ Updated architecture documentation

### Rollback Plan

**If Atomspace fails in production**:
1. Immediate: Switch reads back to PostgreSQL
2. Stop Atomspace writes
3. Re-enable dual-write to catch up
4. Post-mortem: analyze failure
5. Fix issues, retry migration or abort

---

## Phase 5: AI Gamemaster Foundation 🎮

**Timeline**: 2026+ (Ongoing research project)
**Status**: Future
**Goal**: Use knowledge graph for AI-driven gamemastering with symbolic reasoning

### Vision

```
┌─────────────────────────────────────────────────┐
│           AI Gamemaster System                  │
│                                                 │
│  ┌─────────────────────────────────────────┐   │
│  │  Natural Language Interface (LLM)       │   │
│  │  "I cast fireball at the goblins"       │   │
│  └──────────────┬──────────────────────────┘   │
│                 ↓                               │
│  ┌─────────────────────────────────────────┐   │
│  │  NL → Symbolic Translator               │   │
│  │  (LLM extracts: cast, fireball, goblins)│   │
│  └──────────────┬──────────────────────────┘   │
│                 ↓                               │
│  ┌─────────────────────────────────────────┐   │
│  │  Atomspace Knowledge Graph              │   │
│  │  - Rules: Fire spells burn wood         │   │
│  │  - Context: Goblins in wooden tavern    │   │
│  │  - Consequences: ???                    │   │
│  └──────────────┬──────────────────────────┘   │
│                 ↓                               │
│  ┌─────────────────────────────────────────┐   │
│  │  PLN Reasoning Engine                   │   │
│  │  Infers: Tavern catches fire!           │   │
│  └──────────────┬──────────────────────────┘   │
│                 ↓                               │
│  ┌─────────────────────────────────────────┐   │
│  │  Symbolic → NL Response (LLM)           │   │
│  │  "The tavern erupts in flames..."       │   │
│  └─────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
```

### Core Capabilities

#### 1. **Rules as Symbolic Knowledge**

Store game rules in Atomspace for reasoning:

```scheme
; Explicit rule
(ImplicationLink (stv 1.0 1.0)  ; strength=1.0, confidence=1.0
  (AndLink
    (Predicate "PlayerCasts" (Variable "$player") (Variable "$spell"))
    (Inheritance (Variable "$spell") (Concept "FireSpell"))
    (Predicate "LocationMaterial" (Variable "$location") (Concept "Wood")))
  (Evaluation
    (Predicate "CatchesFire")
    (Variable "$location")))

; Probabilistic "unwritten rule" learned from gameplay
(ImplicationLink (stv 0.8 0.6)  ; strength=0.8, confidence=0.6
  (AndLink
    (Predicate "PlayerFumbles" (Variable "$player"))
    (Predicate "GMPersonality" (Concept "Narrative")))
  (Evaluation
    (Predicate "OffersNarrativeChoice")
    (Variable "$player")))
```

#### 2. **Learning from Gameplay**

Extract patterns from session logs:

```python
# Analyze gameplay transcripts
def extract_gm_patterns(session_logs):
    """Learn 'unwritten rules' from how GM handles situations"""

    # Pattern: When player fumbles, GM offers choice 80% of time
    pattern = ImplicationLink(
        condition=AndLink(
            Predicate("PlayerFumbles"),
            Predicate("GMStyle", "Narrative")
        ),
        consequence=Evaluation(
            Predicate("OffersChoice"),
            strength=0.8,  # Learned from frequency
            confidence=0.7  # Based on sample size
        )
    )

    atomspace.add(pattern)
```

#### 3. **Context-Aware Reasoning**

PLN infers consequences based on context:

```scheme
; Player action
(Evaluation (Predicate "PlayerCasts")
  (List (Concept "Alice") (Concept "Fireball")))

; Context
(Evaluation (Predicate "LocationIs")
  (List (Concept "Alice") (Concept "WoodenTavern")))

(Inheritance (Concept "Fireball") (Concept "FireSpell"))
(Inheritance (Concept "WoodenTavern") (Concept "WoodStructure"))

; PLN reasons:
; FireSpell + WoodStructure → FIRE!
; → Infers consequences automatically
```

#### 4. **Adaptive Difficulty**

Analyze player capabilities, adjust encounters:

```scheme
; Track player stats
(Evaluation (Predicate "PlayerLevel") (List (Concept "Alice") (Number 5)))
(Evaluation (Predicate "RecentVictories") (List (Concept "Alice") (Number 8)))

; PLN infers: Player is winning too easily
(ImplicationLink (stv 0.9 0.8)
  (AndLink
    (GreaterThan (Predicate "RecentVictories") (Number 7))
    (LessThan (Predicate "DifficultyRating") (Number 0.6)))
  (Evaluation
    (Predicate "IncreaseDifficulty")
    (Concept "NextEncounter")))
```

#### 5. **Cross-System Integration**

Connect knowledge graphs across MAGI ecosystem:

```
Magi-Archive (Rules & Lore)
    ↓ (queries)
Spyder (NPC Personalities)
    ↓ (queries)
TheSmithy (Game State)
    ↓ (queries)
Endless-Cascade (3D World State)
    ↓
Unified Distributed Atomspace (MORK)
    ↓
AI Gamemaster Reasoning
```

### Research Areas

#### Year 1 (2026)
- [ ] Rule representation: How to encode D&D/game rules symbolically?
- [ ] NL → Symbolic: LLM extracts actions/entities from player speech
- [ ] Symbolic → NL: Convert reasoning results to natural language
- [ ] Context management: What context does PLN need for good inferences?

#### Year 2 (2027)
- [ ] Learning from logs: Extract patterns from actual gameplay
- [ ] Unwritten rules: How to represent GM style, tone, preferences?
- [ ] Uncertainty handling: PLN with incomplete/contradictory information
- [ ] Multi-agent reasoning: Multiple NPCs with conflicting goals

#### Year 3 (2028)
- [ ] Real-time GMing: Can AI respond in <5 seconds for fluid gameplay?
- [ ] Creativity: Can AI generate surprising-yet-coherent story twists?
- [ ] Adaptation: Does AI learn player preferences over time?
- [ ] Integration: Full pipeline from player speech → AI response

### Success Metrics (Long-term)

- [ ] AI GM passes "Turing test" - players can't tell human from AI
- [ ] 90% of AI GM decisions are "in character" with learned style
- [ ] Players report AI GM is "fun to play with" (subjective, but key)
- [ ] AI handles edge cases gracefully (doesn't break when players do unexpected things)

### Deliverables

- ✅ Symbolic rule encoding framework
- ✅ PLN reasoning pipeline for game scenarios
- ✅ Learning system to extract patterns from logs
- ✅ NL ↔ Symbolic translation layer
- ✅ Prototype AI GM for testing

---

## Cross-Cutting Concerns

### Performance Monitoring (All Phases)

Track key metrics throughout:

| Metric | Target | Warning Threshold | Critical Threshold |
|--------|--------|-------------------|-------------------|
| Query latency | <500ms | >2s | >5s |
| Page load time | <2s | >5s | >10s |
| Database size | N/A | >10GB | >50GB |
| Concurrent users | 100+ | Response time degrades | System crashes |
| Uptime | 99.9% | <99% | <95% |

### Security & Privacy (All Phases)

- [ ] SSL/HTTPS enforced
- [ ] User authentication required
- [ ] Password hashing (bcrypt/scrypt)
- [ ] Regular backups (daily minimum)
- [ ] Audit logs for sensitive operations
- [ ] GDPR compliance (if applicable)

### Documentation (All Phases)

Maintain living documentation:
- [ ] Architecture diagrams (updated each phase)
- [ ] API documentation (Decko, MCP adapter, Atomspace)
- [ ] User guides (wiki navigation, graph visualizer)
- [ ] Admin runbooks (deployment, troubleshooting)
- [ ] Decision logs (why we chose X over Y)

### Team Collaboration (All Phases)

- [ ] Weekly reviews with players/collaborators
- [ ] Monthly retrospectives (what's working, what's not)
- [ ] Slack/Discord channel for async updates
- [ ] GitLab issues for bug tracking
- [ ] Design docs for major changes (reviewed before coding)

---

## Risk Management

### High-Risk Items

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| **Atomspace too slow for interactive use** | High | Medium | Phase 3 validation before commitment; hybrid PostgreSQL/Atomspace |
| **MCP adapter unstable** | High | Medium | Extensive testing in Phase 3; rollback to PostgreSQL |
| **MORK hosting unavailable/expensive** | Medium | Low | Research MORK early; budget for self-hosting |
| **Manual migration takes too long** | Medium | High | Automate where possible; prioritize critical content |
| **Players abandon wiki due to complexity** | High | Low | Focus on UX; simple interface hides complexity |
| **AI GM doesn't provide value** | Low | Medium | Start small; iterate based on playtesting |

### Mitigation Strategies

1. **De-risk early**: Phase 3 validates Atomspace before migration
2. **Incremental rollout**: Each phase delivers value independently
3. **Rollback plans**: Can revert to previous phase if needed
4. **User feedback loops**: Players test and provide feedback continuously
5. **Prototype first**: Test risky ideas (MORK, PLN) in isolation before integrating

---

## Decision Log

### Decision 1: Decko vs Custom Wiki
- **Decision**: Use Decko (Ruby-based wiki framework)
- **Rationale**: Proven framework, card-based model fits knowledge graph, extensible via mods
- **Alternative Considered**: Custom wiki built on Atomspace from scratch (too much work, unproven)

### Decision 2: PostgreSQL First, Atomspace Later
- **Decision**: Start with PostgreSQL, migrate to Atomspace only if validated
- **Rationale**: Need wiki ASAP, Atomspace unproven for interactive use, reduce risk
- **Alternative Considered**: Atomspace from day 1 (too risky, blocks immediate deployment)

### Decision 3: Manual MkDocs Migration
- **Decision**: Manually import content from 5 MkDocs repos
- **Rationale**: Allows review, cleanup, consolidation; automated import would carry over cruft
- **Alternative Considered**: Automated script (faster but no quality control)

### Decision 4: Standalone Graph Visualizer
- **Decision**: Build separate app, embed in Decko via iframe
- **Rationale**: Easier to develop independently, can swap visualization libraries, reusable
- **Alternative Considered**: Decko mod (tightly coupled, harder to iterate)

### Decision 5: Dual-Write Migration Strategy
- **Decision**: Run PostgreSQL + Atomspace in parallel before cutover
- **Rationale**: Zero downtime, verify consistency, easy rollback
- **Alternative Considered**: Big-bang migration (too risky, potential data loss)

---

## Open Questions

### Phase 1 (Immediate)
- [ ] What domain name to use? (affects SSL setup)
- [ ] How many user accounts needed initially? (affects onboarding work)
- [ ] Which MkDocs repo has the "canonical" content? (prioritize in migration)

### Phase 2 (Graph Visualizer)
- [ ] Which visualization library? (D3.js vs Cytoscape vs Vis.js)
- [ ] How to detect "unanticipated connections"? (algorithm design)
- [ ] Should graph be public or login-only? (privacy concern)

### Phase 3 (Atomspace)
- [ ] Does Hyperon MCP implementation support all Decko card operations?
- [ ] What's actual MCP overhead? (need benchmarks)
- [ ] Does MORK provide hosting or self-host? (cost/complexity impact)

### Phase 4 (Migration)
- [ ] How to handle Decko-specific features not in Atomspace? (mods, formats, etc.)
- [ ] Can Atomspace scale to 10,000+ cards? (need load testing)
- [ ] What's backup strategy for Atomspace? (PostgreSQL has pg_dump)

### Phase 5 (AI GM)
- [ ] How to represent "tone" and "style" symbolically? (fuzzy concept)
- [ ] Can PLN run in real-time (<5s) for interactive GMing?
- [ ] How to handle player creativity/rule-breaking? (AI needs flexibility)

---

## Next Actions (This Week)

### Immediate (Days 1-3)
1. [ ] Set up AWS account (if not already)
2. [ ] Deploy Decko to EC2 following AWS-DEPLOYMENT.md
3. [ ] Create basic card types (Game, Faction, Character, etc.)

### This Week (Days 4-7)
4. [ ] Start manual MkDocs migration (prioritize most important content)
5. [ ] Create 5 user accounts for alpha testers
6. [ ] Test Claude Code workflow (create/edit cards)
7. [ ] Share wiki URL with players for initial feedback

---

## Appendix: Technology Stack

### Phase 1 (Current)
- **Frontend**: Decko (Ruby on Rails)
- **Database**: PostgreSQL 13+
- **Hosting**: AWS EC2 (Ubuntu 22.04) + RDS
- **Web Server**: Nginx + Puma
- **SSL**: Let's Encrypt

### Phase 2 (Graph Visualizer)
- **Visualization**: D3.js / Cytoscape.js / Vis.js (TBD)
- **Framework**: React or Vue.js
- **API**: Decko REST API

### Phase 3-4 (Atomspace)
- **Knowledge Graph**: Hyperon Atomspace
- **Reasoning**: PLN (Probabilistic Logic Networks)
- **Protocol**: MCP (Model Context Protocol)
- **Distributed**: MORK (optional)

### Phase 5 (AI GM)
- **NL Processing**: LLM (GPT-4, Claude, or open-source)
- **Symbolic Reasoning**: Hyperon PLN
- **Integration**: MCP for LLM ↔ Atomspace

---

**Last Updated**: 2025-10-16
**Next Review**: End of Phase 1 (Week 2)
**Maintained By**: Lake + Claude Code
