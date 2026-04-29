# Atomspace Integration Architecture

**Project**: magi-archive Hyperon Atomspace Backend
**Timeline**: Phase 3-4 (Month 3-9, 2026)
**Status**: **Conceptual Sketch (Cluster-Pilot Reframed 2026-04-29)** — see "Cluster-Pilot Reframing" section below before treating any code block as runnable.
**Last Updated**: 2026-04-29

---

## Cluster-Pilot Reframing (2026-04-29)

The AtomSpace Backend Integration Cluster Pilot (cluster archive at `scripts/archive/atomspace_pilot/`) audited this document against current code in the four AtomSpace layers (Classical StorageNode, Hyperon Space, DAS, MORK native). Several premises in this document are now known to be **inaccurate or aspirational**, and the Phase 3 architecture has been narrowed. **Treat the rest of this document as a conceptual sketch, not as engineering specification, until corrected.** The synthesis card `Implementation Families+AtomSpace Backend Integration` (wiki) is the canonical post-pilot statement; this section summarizes the cluster-pilot deltas.

### Bottom-line corrections

1. **The literal `from hyperon import Atomspace, MCP` import is APOCRYPHAL.** Source 2 + Source 4 verified that the `hyperon` Python package does not export an `MCP` symbol. The MCP Adapter pseudocode below uses an API surface that does not exist. Treat all `MCP.Client(...)` / `mcp_client.connect()` / `pln_query(...)` calls as illustrative only.

2. **DECKO-MCP / ATOMSPACE-MCP disambiguation is locked.** The only deployed MCP API in this repo is **Decko MCP** (`mod/mcp_api/config/initializers/mcp_routes.rb`) — JWT-authenticated, full card CRUD + history + files + relations. Any "ATOMSPACE-MCP" reference in this document is conceptual, not real.

3. **`atomspace-pgres` is BACKING-STORE-ONLY and NOT Decko-compatible.** Source 2 R2.1: rigid Atom/Value schema with no card semantics, no permissions, no history. Do **NOT** recommend `atomspace-pgres` as a Decko seam.

4. **MORK is an 8-member workspace (not 7); PeTTa/MORK has been benchmarked to 400M atoms in RAM (NOT 500M+).** `mork_ffi/example_space.metta:13-17` documents 100M/200M/300M/400M successful loads with 500M reported as out-of-memory. The "500M+ atoms" framing was an OOM ceiling, not demonstrated capacity.

5. **DAS-MorkDB link/S-expression delete is BLOCKING-INTEGRATION.** `MorkDB.cc:268-270` hard-fails on link delete; `flush_pattern` + `re_index_patterns` provide only batch-rebuild workarounds. **Any architecture using DAS MorkDB as a MUTABLE backend is automatically out of compliance with Phase 3 acceptance gates** (preserve Decko card model, rollback / dual-write).

6. **`hyperon-experimental/python/sandbox/sql_space.py` + `python/sandbox/mork/mork.py` are SANDBOX, not integration seams.** `mork.py`'s `query()` returns empty BindingsSet; `add()` is `pass`. `sql_space.py` is a psycopg2 SELECT generator with no Decko schema/permission/history/file/RichText awareness.

7. **MORK server-branch 49-commit drift is a deployment risk, not a footnote.** DAS Dockerfile pins MORK `578a759` (2025-07-21); local `origin/server` HEAD as of 2026-04-29 is `5b04a1d` (2026-04-18) with deadlock and UTF-8 fixes in the gap. `das-toolbox` CLI defaults to image tags `1.0.5`. Three potentially-different references (image tag, Dockerfile pin, server-branch HEAD) must be reconciled before production.

### Phase 3 architecture lock-in (READONLY-ATOMSPACE-BRIDGE)

Phase 3 is a **READ-ONLY semantic mirror**, not a write-through replacement for PostgreSQL. Decko/Rails/PostgreSQL stays the source of truth. AtomSpace serves queries that PostgreSQL cannot trivially answer, with caching + periodic re-hydration. **NO write-through to DAS or MORK in Phase 3.** Two viable mechanisms (decision deferred to prototype benchmark against the <500ms fetch gate):

- (a) `atomspace-bridge` style import / small custom exporter (lower complexity).
- (b) `mork_ffi` for low-latency queries + `mork_loader.py` for periodic hydration (higher engineering effort but directly meets latency).

The Phase 3 / Phase 4 diagrams below show **legacy aspirational architecture** retained for context. The reframed scope is read-only mirror; the dual-write / Atomspace-as-primary architecture is **out of scope for Phase 3** and **blocked for Phase 4** by the MorkDB delete gap and the absence of Decko-semantic mappings (history, RichText, files, permissions).

### Four-layer AtomSpace taxonomy

"AtomSpace" spans four implementation layers; resolve which layer is meant before drawing conclusions:

| # | Layer | Repos | Decko relevance |
|---|---|---|---|
| 1 | Classical StorageNode | `atomspace` + `atomspace-storage` + `atomspace-pgres` + `atomspace-rocks` + `atomspace-cog` + `atomspace-bridge` | Read-side SQL import ancestor; not Decko-write-ready |
| 2 | Hyperon Space | `hyperon-experimental` (`GroundingSpace` / `SpaceMut` / `DynSpace`) | MeTTa-facing demos; not primary Decko backend |
| 3 | DAS AtomDB + services | `singnet/das` (AtomDB + Query Engine + AttentionBroker; MorkDB) | Candidate later query/deployment layer; delete + server-pin caveats |
| 4 | MORK native substrate | `trueagi-io/MORK` + PathMap + `mork_ffi` + SDK + server branch | Performance substrate; requires adapter layer for Decko semantics |

---

## Executive Summary

This document outlines the architecture for integrating Hyperon Atomspace as the backend knowledge graph for magi-archive. **As reframed by the 2026-04-29 cluster pilot, Phase 3 is a read-only semantic mirror — Decko/Rails/PostgreSQL remains the source of truth.** The integration enables symbolic reasoning and semantic queries beyond what PostgreSQL can trivially answer; distributed knowledge management via MORK is design-stage.

**Key Decision**: This integration is **conditional** - only proceed if Phase 3 prototype proves Atomspace provides clear value over PostgreSQL **on a read-only mirror, with explicit caveats around PLN completeness (No-Go theorem)**.

---

## Rationale

### Why Atomspace?

**Current (PostgreSQL)**:
- Fast queries (~100ms)
- Proven reliability
- Simple data model (cards = rows)
- Limited to explicit relationships

**Future (Atomspace)**:
- Semantic reasoning (PLN)
- Inferred relationships
- Symbolic knowledge representation
- Distributed via MORK
- **BUT**: Potentially slower, more complex

**The Bet**: Reasoning capabilities outweigh latency cost

---

## Architecture Evolution

### Phase 1: PostgreSQL Only

```
┌────────────────────────────────┐
│  Decko Wiki (Rails)            │
│  ↓                             │
│  PostgreSQL                    │
│  - Cards as rows               │
│  - Relationships as foreign    │
│    keys or JSON                │
└────────────────────────────────┘
```

**Characteristics**:
- Simple, fast, proven
- Limited to SQL queries
- No reasoning capabilities

### Phase 3: Dual Backend (Prototype)

```
┌────────────────────────────────────────┐
│  Decko Wiki (Rails)                    │
│  ↓                                     │
│  PostgreSQL (Primary - Interactive)    │
│  ↓ (nightly export)                    │
│  ┌──────────────────────────────────┐ │
│  │  MCP Adapter                     │ │
│  │  (Card API ↔ Atomspace)         │ │
│  └──────────────┬───────────────────┘ │
│                 ↓                      │
│  Hyperon Atomspace (Experimental)     │
│  - PLN reasoning                      │
│  - Semantic queries                   │
│  - Read-only (testing)                │
└────────────────────────────────────────┘
```

**Characteristics**:
- PostgreSQL serves users (proven fast)
- Atomspace used for experimentation
- No production risk
- Measure Atomspace performance

### Phase 4: Atomspace Primary

```
┌─────────────────────────────────────────────┐
│  Decko Wiki (Rails)                         │
│  ↓                                          │
│  ┌───────────────────────────────────────┐ │
│  │  MCP Adapter                          │ │
│  │  - Translates Decko Card API          │ │
│  │  - Caches frequently accessed atoms   │ │
│  └──────────────┬────────────────────────┘ │
│                 ↓                           │
│  ┌──────────────────────────────────────┐  │
│  │  Hyperon Atomspace (Primary)         │  │
│  │  - Cards as ConceptNodes             │  │
│  │  - Relationships as Links            │  │
│  │  - PLN reasoning engine              │  │
│  │  ↓                                   │  │
│  │  MORK Distributed Backend (Optional) │  │
│  └──────────────────────────────────────┘  │
│                 ↓ (archive)                 │
│  PostgreSQL (Backup/Archive)                │
└─────────────────────────────────────────────┘
```

**Characteristics**:
- Atomspace is source of truth
- MCP adapter provides Decko interface
- PostgreSQL kept as backup initially
- Optional MORK for distributed/scale

---

## Data Model Mapping

### Decko Card → Atomspace Atoms

**Decko Card Structure**:
```ruby
Card {
  id: 42,
  name: "Character: Alice +Butterfly Galaxii",
  type: "Character",
  content: "A brave explorer...",
  pointers: {
    game: "Game: Butterfly Galaxii",
    factions: ["Faction: Rebels"]
  },
  created_at: "2025-10-16",
  updated_at: "2025-10-17"
}
```

**Atomspace Representation**:
```scheme
; Card as ConceptNode
(ConceptNode "Character:Alice+ButterflyGalaxii")

; Type relationship
(InheritanceLink
  (ConceptNode "Character:Alice+ButterflyGalaxii")
  (ConceptNode "Character"))

; Content as value
(StateLink
  (ConceptNode "Character:Alice+ButterflyGalaxii")
  (ConceptNode "content")
  (StringValue "A brave explorer..."))

; Relationships as EvaluationLinks
(EvaluationLink
  (PredicateNode "belongsToGame")
  (ListLink
    (ConceptNode "Character:Alice+ButterflyGalaxii")
    (ConceptNode "Game:ButterflyGalaxii")))

(EvaluationLink
  (PredicateNode "memberOfFaction")
  (ListLink
    (ConceptNode "Character:Alice+ButterflyGalaxii")
    (ConceptNode "Faction:Rebels")))

; Metadata
(StateLink
  (ConceptNode "Character:Alice+ButterflyGalaxii")
  (ConceptNode "created_at")
  (TimestampValue "2025-10-16T00:00:00Z"))
```

### Card Types as Type Hierarchy

```scheme
; Base card type
(ConceptNode "Card")

; Specific types inherit from base
(InheritanceLink (ConceptNode "Game") (ConceptNode "Card"))
(InheritanceLink (ConceptNode "Character") (ConceptNode "Card"))
(InheritanceLink (ConceptNode "Faction") (ConceptNode "Card"))
(InheritanceLink (ConceptNode "Mechanic") (ConceptNode "Card"))
(InheritanceLink (ConceptNode "Narrative") (ConceptNode "Card"))

; Further sub-typing (optional)
(InheritanceLink (ConceptNode "PlayerCharacter") (ConceptNode "Character"))
(InheritanceLink (ConceptNode "NPC") (ConceptNode "Character"))
```

### Relationships as Typed Links

**Pointer relationships**:
```scheme
; Game includes faction
(EvaluationLink
  (PredicateNode "includes")
  (ListLink
    (ConceptNode "Game:ButterflyGalaxii")
    (ConceptNode "Faction:Korvax")))

; Character appears in narrative
(EvaluationLink
  (PredicateNode "appearsIn")
  (ListLink
    (ConceptNode "Character:Alice")
    (ConceptNode "Narrative:TheGreatCollapse")))

; Mechanic relates to mechanic
(EvaluationLink
  (PredicateNode "relatesTo")
  (ListLink
    (ConceptNode "Mechanic:Crafting")
    (ConceptNode "Mechanic:Resources")))
```

**Nested relationships** (hierarchy):
```scheme
; Parent-child for nested cards
(MemberLink
  (ConceptNode "Game:ButterflyGalaxii/Factions")
  (ConceptNode "Game:ButterflyGalaxii"))

(MemberLink
  (ConceptNode "Game:ButterflyGalaxii/Species")
  (ConceptNode "Game:ButterflyGalaxii"))
```

---

## MCP Adapter Architecture

> **⚠ CONCEPTUAL SKETCH — APOCRYPHAL API.** The Python below uses `from hyperon import Atomspace, MCP` and `MCP.Client(...)` calls that **do not exist in the real `hyperon` package** (Source 2 + Source 4 audit, 2026-04-29). The real MCP integration in this repo is **Decko MCP** (`mod/mcp_api/`), not an "Atomspace-MCP". Treat all `MCP.Client(...)`, `mcp_client.connect()`, and `pln_query(...)` calls in the code below as illustrative pseudocode only. The `_sanitize` helper that strips `+`, `:`, and spaces is also lossy for Decko card names (Decko cards routinely contain `+` joiners and `:` type prefixes); a real adapter must preserve canonical names rather than mangle them. Phase 3 architecture is **READONLY-ATOMSPACE-BRIDGE** — the WRITE OPERATIONS section below is out of scope for Phase 3 and blocked for Phase 4 by the DAS-MorkDB delete gap (`MorkDB.cc:268-270` hard-fails). The READ OPERATIONS shape is closer to a real Phase 3 surface but still uses the apocryphal API and would need to route through Decko MCP + a real read seam (atomspace-bridge import or mork_ffi/mork_loader).

### Purpose

The MCP (Model Context Protocol) Adapter would, in principle, translate between:
- **Decko Card API** (Rails/Ruby) ↔ **Hyperon Atomspace** (symbolic atoms)

In practice (post-cluster-pilot), Phase 3 uses **Decko MCP for extraction + a read-only mirror loader** rather than an "Atomspace MCP" client. See "Cluster-Pilot Reframing" section above for the locked-in architecture.

### Components (CONCEPTUAL SKETCH)

```python
# mcp_adapter/decko_atomspace_adapter.py
# WARNING: APOCRYPHAL API — `MCP` is not a real hyperon export.
# Retained as conceptual sketch only; do not run.

from hyperon import Atomspace, MCP  # NOTE: MCP symbol does not exist in hyperon package
from typing import Dict, List, Optional
import json

class DeckoAtomspaceAdapter:
    """Bidirectional adapter between Decko and Atomspace"""

    def __init__(self, atomspace_url: str):
        self.mcp_client = MCP.Client(atomspace_url)
        self.atomspace = self.mcp_client.connect()

    # ========== READ OPERATIONS ==========

    def fetch_card(self, name: str) -> Optional[Dict]:
        """Fetch card by name from Atomspace"""
        # Query Atomspace
        concept = self.atomspace.query(f"""
            (ConceptNode "{self._sanitize(name)}")
        """)

        if not concept:
            return None

        # Convert atom to card structure
        return self._atom_to_card(concept)

    def search_cards(self, query: Dict) -> List[Dict]:
        """Search cards by type, content, or relationships"""

        if 'type' in query:
            # Search by type
            atoms = self.atomspace.query(f"""
                (GetLink
                  (InheritanceLink
                    (Variable "$card")
                    (ConceptNode "{query['type']}")))
            """)

        elif 'content_match' in query:
            # Semantic content search (requires vector embeddings)
            # TODO: Implement semantic similarity search
            pass

        elif 'related_to' in query:
            # Find cards related to another card
            atoms = self.atomspace.query(f"""
                (GetLink
                  (EvaluationLink
                    (Variable "$predicate")
                    (ListLink
                      (Variable "$card")
                      (ConceptNode "{query['related_to']}"))))
            """)

        return [self._atom_to_card(a) for a in atoms]

    # ========== WRITE OPERATIONS ==========

    def create_card(self, card_data: Dict) -> Dict:
        """Create new card in Atomspace"""

        name = card_data['name']
        card_type = card_data['type']
        content = card_data.get('content', '')

        # Create ConceptNode
        self.atomspace.add_node('ConceptNode', self._sanitize(name))

        # Add type relationship
        self.atomspace.add_link('InheritanceLink', [
            ('ConceptNode', self._sanitize(name)),
            ('ConceptNode', card_type)
        ])

        # Add content
        if content:
            self.atomspace.add_link('StateLink', [
                ('ConceptNode', self._sanitize(name)),
                ('ConceptNode', 'content'),
                ('StringValue', content)
            ])

        # Add relationships (pointers)
        if 'pointers' in card_data:
            for predicate, targets in card_data['pointers'].items():
                if not isinstance(targets, list):
                    targets = [targets]

                for target in targets:
                    self.atomspace.add_link('EvaluationLink', [
                        ('PredicateNode', predicate),
                        ('ListLink', [
                            ('ConceptNode', self._sanitize(name)),
                            ('ConceptNode', self._sanitize(target))
                        ])
                    ])

        # Add metadata
        from datetime import datetime
        self.atomspace.add_link('StateLink', [
            ('ConceptNode', self._sanitize(name)),
            ('ConceptNode', 'created_at'),
            ('TimestampValue', datetime.now().isoformat())
        ])

        return self.fetch_card(name)

    def update_card(self, name: str, updates: Dict) -> Dict:
        """Update existing card"""

        # Update content
        if 'content' in updates:
            # Remove old content state
            self._remove_state(name, 'content')

            # Add new content
            self.atomspace.add_link('StateLink', [
                ('ConceptNode', self._sanitize(name)),
                ('ConceptNode', 'content'),
                ('StringValue', updates['content'])
            ])

        # Update relationships
        if 'pointers' in updates:
            # Remove old pointers
            self._remove_all_pointers(name)

            # Add new pointers
            for predicate, targets in updates['pointers'].items():
                if not isinstance(targets, list):
                    targets = [targets]

                for target in targets:
                    self.atomspace.add_link('EvaluationLink', [
                        ('PredicateNode', predicate),
                        ('ListLink', [
                            ('ConceptNode', self._sanitize(name)),
                            ('ConceptNode', self._sanitize(target))
                        ])
                    ])

        # Update timestamp
        from datetime import datetime
        self._remove_state(name, 'updated_at')
        self.atomspace.add_link('StateLink', [
            ('ConceptNode', self._sanitize(name)),
            ('ConceptNode', 'updated_at'),
            ('TimestampValue', datetime.now().isoformat())
        ])

        return self.fetch_card(name)

    def delete_card(self, name: str) -> bool:
        """Delete card from Atomspace"""
        # Remove all atoms related to this card
        concept = ('ConceptNode', self._sanitize(name))

        # Remove all links containing this concept
        self.atomspace.remove_atom(concept, recursive=True)

        return True

    # ========== PLN REASONING ==========

    def infer_relationships(self, card_name: str) -> List[Dict]:
        """Use PLN to infer implicit relationships"""

        # Query for potential relationships based on content similarity,
        # co-occurrence, shared attributes, etc.

        inferred = self.atomspace.pln_query(f"""
            (InferenceLink
              (ConceptNode "{self._sanitize(card_name)}")
              (Variable "$related_card")
              (Variable "$relationship_type"))
        """)

        return [
            {
                'target': r['$related_card'],
                'type': r['$relationship_type'],
                'strength': r.truth_value.strength,
                'confidence': r.truth_value.confidence
            }
            for r in inferred
        ]

    def semantic_search(self, query_text: str, limit: int = 10) -> List[Dict]:
        """Semantic search using content embeddings and PLN"""

        # Convert query to embedding
        # Compare with card content embeddings
        # Use PLN to rank by semantic similarity

        # TODO: Implement with vector similarity + PLN
        pass

    # ========== HELPER METHODS ==========

    def _atom_to_card(self, atom) -> Dict:
        """Convert Atomspace atom to Decko card dict"""

        name = self._desanitize(atom.name)

        # Get type
        card_type = self._get_type(atom)

        # Get content
        content = self._get_state(atom, 'content') or ''

        # Get pointers (relationships)
        pointers = self._get_all_pointers(atom)

        # Get metadata
        created_at = self._get_state(atom, 'created_at')
        updated_at = self._get_state(atom, 'updated_at')

        return {
            'name': name,
            'type': card_type,
            'content': content,
            'pointers': pointers,
            'created_at': created_at,
            'updated_at': updated_at
        }

    def _sanitize(self, name: str) -> str:
        """Convert card name to Atomspace-safe format"""
        # Remove special characters, spaces to underscores
        return name.replace(' ', '_').replace(':', '_').replace('+', '_')

    def _desanitize(self, atom_name: str) -> str:
        """Convert Atomspace atom name back to card name"""
        # Reverse sanitization
        # (May need to store original name as metadata)
        return atom_name.replace('_', ' ')

    def _get_type(self, atom) -> str:
        """Get card type from InheritanceLink"""
        result = self.atomspace.query(f"""
            (InheritanceLink
              (ConceptNode "{atom.name}")
              (Variable "$type"))
        """)
        return result[0]['$type'] if result else 'Unknown'

    def _get_state(self, atom, key: str):
        """Get state value (content, metadata)"""
        result = self.atomspace.query(f"""
            (StateLink
              (ConceptNode "{atom.name}")
              (ConceptNode "{key}")
              (Variable "$value"))
        """)
        return result[0]['$value'] if result else None

    def _remove_state(self, atom_name: str, key: str):
        """Remove a state link"""
        self.atomspace.remove_link('StateLink', [
            ('ConceptNode', self._sanitize(atom_name)),
            ('ConceptNode', key),
            ('Variable', '$value')
        ])

    def _get_all_pointers(self, atom) -> Dict:
        """Get all relationship pointers"""
        result = self.atomspace.query(f"""
            (EvaluationLink
              (Variable "$predicate")
              (ListLink
                (ConceptNode "{atom.name}")
                (Variable "$target")))
        """)

        pointers = {}
        for r in result:
            pred = r['$predicate']
            target = self._desanitize(r['$target'])

            if pred not in pointers:
                pointers[pred] = []
            pointers[pred].append(target)

        return pointers

    def _remove_all_pointers(self, atom_name: str):
        """Remove all relationship links for a card"""
        self.atomspace.remove_link('EvaluationLink', [
            ('Variable', '$predicate'),
            ('ListLink', [
                ('ConceptNode', self._sanitize(atom_name)),
                ('Variable', '$target')
            ])
        ])
```

### Ruby Integration (Rails/Decko)

```ruby
# lib/atomspace_backend.rb

class AtomspaceBackend
  def initialize
    @adapter = HTTParty.post(
      'http://localhost:5000/mcp',  # MCP adapter service
      body: { action: 'connect' }.to_json,
      headers: { 'Content-Type' => 'application/json' }
    )
  end

  def fetch(name)
    response = HTTParty.post(
      'http://localhost:5000/mcp',
      body: { action: 'fetch_card', name: name }.to_json,
      headers: { 'Content-Type' => 'application/json' }
    )

    Card.new(JSON.parse(response.body))
  end

  def create(card_data)
    response = HTTParty.post(
      'http://localhost:5000/mcp',
      body: { action: 'create_card', card_data: card_data }.to_json,
      headers: { 'Content-Type' => 'application/json' }
    )

    Card.new(JSON.parse(response.body))
  end

  # ... similar methods for update, delete, search
end
```

---

## MORK Native Substrate (formerly described here as "Distributed Backend")

> **⚠ CLUSTER-PILOT CORRECTION (2026-04-29).** MORK proper is a high-performance **single-process triemap substrate** (8-member Rust workspace at HEAD `4cef6f7`, foundational dependency on PathMap as a sibling repo), NOT a "distributed Atomspace backend." Distribution is provided by **DAS** (`singnet/das`) on a separate axis. MORK does have a `server` branch that exposes an HTTP API (the `mork-server` deployment line; `MORK-rejuve-bio` fork is the most documented server variant), but the server branch is single-process per server, not a self-clustering distributed engine. PeTTa/MORK has been benchmarked up to **400M atoms in RAM** (`mork_ffi/example_space.metta:13-17` documents successful 100M/200M/300M/400M loads with 500M reported as out-of-memory); earlier 500M+ framings treated the OOM ceiling as demonstrated capacity. The "horizontal scaling / replication / partitioning" framing in this section is **aspirational** and does not match current code. The diagrams below describe DAS-style distribution, not MORK-native distribution.

### What is MORK?

MORK is Hyperon's high-performance **single-process triemap substrate** (Rust kernel + Polyglot FFI + SDK; foundational PathMap dependency). Within Hyperon, distribution is layered on top via DAS (which can use MORK as one of its AtomDB backends). The framing below conflates DAS distribution with MORK distribution — read it as "DAS+MorkDB distributed deployment" rather than "MORK distributed backend":
- **Horizontal scaling** (DAS-side, via Redis+MongoDB sharding or DAS service partitioning)
- **Replication** (DAS-side; CRDT join-semilattices are proposed for the State Management Platform but not yet implemented)
- **Partitioning** (DAS-side; per-context routing via the AttentionBroker)

### Architecture

```
┌───────────────────────────────────────────────────┐
│              Decko + MCP Adapter                  │
└────────────────────┬──────────────────────────────┘
                     ↓
┌───────────────────────────────────────────────────┐
│           MORK Coordination Layer                 │
│  - Query routing                                  │
│  - Consistency management                         │
│  - Load balancing                                 │
└──────────┬──────────────┬──────────────┬──────────┘
           ↓              ↓              ↓
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│ Atomspace 1  │  │ Atomspace 2  │  │ Atomspace 3  │
│  (Games)     │  │ (Factions)   │  │ (Characters) │
└──────────────┘  └──────────────┘  └──────────────┘
```

### Partitioning Strategy

**By card type**:
- Node 1: Games, Mechanics
- Node 2: Factions, Species
- Node 3: Characters, Narratives

**By game/project**:
- Node 1: Butterfly Galaxii
- Node 2: GodsGame
- Node 3: MAGI lore

**Hybrid**:
- Frequently accessed cards: Replicated across all nodes
- Rarely accessed: Single node with backup

### Open Questions

- [ ] Does MORK provide managed hosting? (SaaS)
- [ ] Or self-host on AWS/GCP? (cost/complexity)
- [ ] What's network latency between nodes?
- [ ] How to handle consistency conflicts?
- [ ] Backup strategy for distributed system?

---

## Performance Considerations

### Latency Budget

| Operation | PostgreSQL | Atomspace (Target) | Atomspace (Acceptable) | Atomspace (Unacceptable) |
|-----------|------------|--------------------|-----------------------|--------------------------|
| Fetch card | ~100ms | <500ms | <2s | >5s |
| Search (type) | ~150ms | <1s | <3s | >10s |
| Create card | ~200ms | <1s | <3s | >10s |
| PLN inference | N/A | <2s | <5s | >15s |
| Semantic search | N/A | <3s | <10s | >30s |

### Caching Strategy

**MCP Adapter Cache**:
```python
from functools import lru_cache
from datetime import datetime, timedelta

class CachedAtomspaceAdapter(DeckoAtomspaceAdapter):
    """Add caching layer to reduce Atomspace queries"""

    def __init__(self, atomspace_url: str, cache_ttl: int = 300):
        super().__init__(atomspace_url)
        self.cache_ttl = timedelta(seconds=cache_ttl)
        self.cache = {}

    @lru_cache(maxsize=1000)
    def fetch_card(self, name: str):
        """Fetch with LRU cache"""
        cache_key = f"card:{name}"

        if cache_key in self.cache:
            entry = self.cache[cache_key]
            if datetime.now() - entry['timestamp'] < self.cache_ttl:
                return entry['data']

        # Cache miss or expired
        card = super().fetch_card(name)

        self.cache[cache_key] = {
            'data': card,
            'timestamp': datetime.now()
        }

        return card

    def invalidate_cache(self, name: str):
        """Invalidate cache on update/delete"""
        cache_key = f"card:{name}"
        if cache_key in self.cache:
            del self.cache[cache_key]
```

**Cache Invalidation**:
- On card update: invalidate that card's cache
- On relationship change: invalidate related cards
- Periodic refresh: every 5 minutes (configurable)

### Optimization Opportunities

1. **Batch Queries**: Fetch multiple cards in one Atomspace query
2. **Lazy Loading**: Only fetch card content when displayed (not in search results)
3. **Indexing**: Pre-compute common queries (cards by type, by game, etc.)
4. **Materialized Views**: Cache PLN inference results

---

## Migration Strategy (Phase 4)

### Dual-Write Implementation

```ruby
# lib/dual_write_adapter.rb

class DualWriteAdapter
  def initialize
    @pg = PostgreSQLBackend.new
    @atomspace = AtomspaceBackend.new
  end

  def create_card(card_data)
    # Write to both backends
    pg_card = @pg.create(card_data)
    atom_card = @atomspace.create(card_data)

    # Verify consistency
    unless cards_equal?(pg_card, atom_card)
      Rails.logger.error("Consistency error: PG != Atomspace for #{card_data['name']}")
      # Rollback or alert
    end

    pg_card  # Return PostgreSQL result (primary)
  end

  def fetch_card(name)
    # Read from primary (Atomspace in Phase 4)
    card = @atomspace.fetch(name)

    # Verify against shadow (PostgreSQL)
    pg_card = @pg.fetch(name)
    unless cards_equal?(card, pg_card)
      Rails.logger.warn("Drift detected: Atomspace != PG for #{name}")
    end

    card
  end

  private

  def cards_equal?(card1, card2)
    card1['name'] == card2['name'] &&
    card1['type'] == card2['type'] &&
    card1['content'] == card2['content']
    # ... (compare all fields)
  end
end
```

### Rollback Plan

**If Atomspace fails in production**:

```ruby
# config/initializers/backend.rb

# Feature flag to switch backends
BACKEND = ENV['CARD_BACKEND'] || 'postgresql'  # or 'atomspace'

if BACKEND == 'atomspace'
  Card.backend = AtomspaceBackend.new
elsif BACKEND == 'postgresql'
  Card.backend = PostgreSQLBackend.new
elsif BACKEND == 'dual_write'
  Card.backend = DualWriteAdapter.new
else
  raise "Unknown backend: #{BACKEND}"
end
```

**Rollback procedure**:
1. Set `ENV['CARD_BACKEND'] = 'postgresql'`
2. Restart Rails app
3. All requests now use PostgreSQL
4. Atomspace untouched (for debugging)
5. Fix issue, retry migration

---

## Success Metrics

### Phase 3 (Prototype)

Atomspace is viable if:
- [ ] Query latency <2s for 90% of operations
- [ ] PLN reasoning finds 5+ insights not visible in PostgreSQL
- [ ] MCP adapter has <10% overhead vs direct Atomspace access
- [ ] Export script runs reliably (0 errors in 10 consecutive runs)
- [ ] Handles 1000+ cards without performance degradation

### Phase 4 (Production)

Migration is successful if:
- [ ] Zero data loss during cutover
- [ ] Query latency ≤ PostgreSQL baseline (within 2x)
- [ ] 100% uptime during transition
- [ ] Players don't notice backend swap (transparent)
- [ ] Atomspace handles production load (100+ concurrent users)
- [ ] Reasoning features provide measurable value (user feedback)

---

## Risks & Mitigation

| Risk | Impact | Mitigation |
|------|--------|------------|
| **Atomspace too slow** | High | Phase 3 validation; hybrid approach; caching |
| **MCP overhead high** | Medium | Benchmark early; optimize adapter; consider direct Atomspace API |
| **MORK unavailable/expensive** | Medium | Research alternatives; budget for self-hosting |
| **Data consistency issues** | High | Dual-write validation; automated consistency checks |
| **Rollback complexity** | Medium | Feature flags; maintain PostgreSQL backup; tested rollback procedure |

---

## Open Research Questions

1. **Symbolic vs Embedding**: How to represent card content? Pure symbolic or hybrid with embeddings?
2. **PLN Performance**: Can PLN inference run in real-time (<2s) for interactive use?
3. **Consistency Model**: Eventual consistency (MORK) vs strong consistency? Trade-offs?
4. **Query Language**: Use Atomese directly or create higher-level query DSL?
5. **Versioning**: How to handle card history/versioning in Atomspace?

---

## Next Steps (Phase 3)

### Month 3-4: Setup & Export

- [ ] Install Hyperon locally
- [ ] Test Hyperon MCP server
- [ ] Create Decko → Atomspace export script
- [ ] Validate data integrity after export

### Month 4-5: Performance Benchmarking

- [ ] Measure query latency (fetch, search, create)
- [ ] Compare PostgreSQL vs Atomspace for common operations
- [ ] Test with 100, 1000, 10000 cards

### Month 5-6: Reasoning Evaluation

- [ ] Test PLN inference on game knowledge graph
- [ ] Evaluate semantic search capabilities
- [ ] Identify insights not possible with PostgreSQL

### Decision Point (End Month 6)

**Go/No-Go**: Proceed to Phase 4 (migration) or keep PostgreSQL?

---

**Last Updated**: 2026-04-29 (Cluster-Pilot Reframing applied; conceptual-sketch banners added; Phase 3 narrowed to READONLY-ATOMSPACE-BRIDGE; apocryphal API flagged)
**Next Review**: Phase 3 kickoff (Month 3)
**Maintained By**: Lake + Claude Code

**Cluster-pilot canonical record**: `scripts/archive/atomspace_pilot/source*/findings_reconciled_crossmodel.txt` (sources 1–4); synthesis card `Implementation Families+AtomSpace Backend Integration` on the wiki.
