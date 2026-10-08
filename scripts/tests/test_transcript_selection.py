"""Tests for the cross-provider transcript selection policy.

The policy these pin down: for a meeting captured by more than one
provider, ingest only the longest and most complete capture. The cases
here are the ones that actually decide behaviour on live exports —
length wins, completeness breaks near-ties, same-provider captures are
left alone, and the winner never depends on file order.
"""

import json
import subprocess
import sys
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SCRIPTS))

from pipeline.transcript_selection import (  # noqa: E402
    SCOPE_ALL, SCOPE_CROSS_PROVIDER, completeness_points, duplicate_groups,
    group_key, metrics, normalize_title, select,
)


def record(provider, chars, title="Magi Weekly", date="2026-06-01",
           tid=None, summary=1, action_items=1, participants=1, keywords=1,
           duration=60):
    return {
        "meeting_name": title,
        "date": date,
        "source_service": provider,
        "transcript_id": tid or f"{provider}-{chars}",
        "full_text": "word " * chars,
        "summary": "s" * summary,
        "action_items": ["a"] * action_items,
        "participants": ["p"] * participants,
        "keywords": ["k"] * keywords,
        "duration_minutes": duration,
    }


def entries(*records):
    return [{"record": r, "path": f"/x/{r['transcript_id']}.json",
             "provider": r["source_service"]} for r in records]


class NormalizationTest(unittest.TestCase):
    def test_case_and_punctuation_are_ignored(self):
        # Providers render the same calendar title with different
        # separators; those must not read as different meetings.
        self.assertEqual(normalize_title("Lake <> Sandra"),
                         normalize_title("lake - sandra"))
        self.assertEqual(normalize_title("Magi  Weekly!"),
                         normalize_title("magi weekly"))

    def test_distinct_titles_stay_distinct(self):
        # Normalization must not become fuzzy matching: merging two real
        # meetings silently discards a transcript.
        self.assertNotEqual(normalize_title("Magi Weekly"),
                            normalize_title("Magi Monthly"))

    def test_group_key_is_title_and_date(self):
        same_day = record("otter", 10)
        other_day = record("otter", 10, date="2026-06-08")
        self.assertNotEqual(group_key(same_day), group_key(other_day))

    def test_missing_fields_do_not_raise(self):
        self.assertEqual(group_key({}), ("", ""))
        self.assertEqual(normalize_title(None), "")


class CompletenessTest(unittest.TestCase):
    def test_points_count_present_signals(self):
        full = record("otter", 10)
        self.assertEqual(completeness_points(full), 5)

    def test_empty_signals_score_zero(self):
        bare = record("otter", 10, summary=0, action_items=0, participants=0,
                      keywords=0, duration=0)
        self.assertEqual(completeness_points(bare), 0)

    def test_metrics_report_chars_and_words(self):
        m = metrics(record("otter", 3))
        self.assertEqual(m["words"], 3)
        self.assertEqual(m["chars"], len("word " * 3))


class SelectionTest(unittest.TestCase):
    def test_longest_wins_across_providers(self):
        selected, skipped, groups = select(
            entries(record("fireflies", 1000), record("read.ai", 500)))
        self.assertEqual(len(selected), 1)
        self.assertEqual(selected[0]["provider"], "fireflies")
        self.assertEqual(selected[0]["selection_reason"], "longest-transcript")
        self.assertEqual(len(skipped), 1)
        self.assertEqual(skipped[0]["skipped_because"], "shorter-transcript")
        self.assertTrue(groups[0]["collapsed"])

    def test_longest_wins_even_when_the_loser_is_more_complete(self):
        # This is the live Fireflies-vs-Read.ai shape: Read.ai writes a far
        # richer summary, Fireflies has materially more transcript. The
        # operator asked for the longest, so length must dominate once the
        # gap is outside the near-tie band.
        long_sparse = record("fireflies", 10000, summary=800, keywords=6)
        short_rich = record("read.ai", 6000, summary=12000, keywords=22)
        selected, skipped, _ = select(entries(long_sparse, short_rich))
        self.assertEqual(selected[0]["provider"], "fireflies")
        self.assertEqual(skipped[0]["provider"], "read.ai")

    def test_completeness_decides_a_near_tie(self):
        # Within 2% the transcripts are the same length in any meaningful
        # sense, so the capture carrying more structure should win.
        sparse = record("otter", 10000, summary=10, action_items=0, keywords=0)
        rich = record("read.ai", 9900, summary=500, action_items=9, keywords=8)
        selected, skipped, groups = select(entries(sparse, rich))
        self.assertEqual(selected[0]["provider"], "read.ai")
        self.assertEqual(selected[0]["selection_reason"],
                         "most-complete-within-length-band")
        self.assertEqual(skipped[0]["skipped_because"],
                         "less-complete-within-length-band")
        self.assertEqual(groups[0]["band_size"], 2)

    def test_near_tie_ratio_is_configurable(self):
        sparse = record("otter", 10000, summary=10, action_items=0, keywords=0)
        rich = record("read.ai", 9000, summary=500, action_items=9, keywords=8)
        # Outside the default band, length wins.
        selected, _, _ = select(entries(sparse, rich))
        self.assertEqual(selected[0]["provider"], "otter")
        # Widen the band and completeness takes over.
        selected, _, _ = select(entries(sparse, rich), near_tie_ratio=0.2)
        self.assertEqual(selected[0]["provider"], "read.ai")

    def test_same_provider_duplicates_are_kept_by_default(self):
        # Otter really does record split or rescheduled sessions under one
        # title; the ingest already names those distinctly, so the
        # conservative scope must not discard one.
        selected, skipped, groups = select(
            entries(record("otter", 1000, tid="a"),
                    record("otter", 900, tid="b")))
        self.assertEqual(len(selected), 2)
        self.assertEqual(skipped, [])
        self.assertFalse(groups[0]["collapsed"])
        self.assertEqual(groups[0]["reason"], "same-provider-group-kept")

    def test_scope_all_collapses_same_provider_duplicates(self):
        selected, skipped, _ = select(
            entries(record("otter", 1000, tid="a"),
                    record("otter", 900, tid="b")),
            scope=SCOPE_ALL)
        self.assertEqual(len(selected), 1)
        self.assertEqual(selected[0]["record"]["transcript_id"], "a")
        self.assertEqual(len(skipped), 1)

    def test_unique_meetings_pass_through(self):
        selected, skipped, groups = select(
            entries(record("otter", 100, title="A"),
                    record("read.ai", 100, title="B")))
        self.assertEqual(len(selected), 2)
        self.assertEqual(skipped, [])
        self.assertTrue(all(g["reason"] == "unique-meeting" for g in groups))

    def test_three_providers_keep_exactly_one(self):
        selected, skipped, _ = select(
            entries(record("otter", 300), record("fireflies", 900),
                    record("read.ai", 600)))
        self.assertEqual(len(selected), 1)
        self.assertEqual(selected[0]["provider"], "fireflies")
        self.assertEqual(len(skipped), 2)
        self.assertTrue(all(s["superseded_by"]["provider"] == "fireflies"
                            for s in skipped))

    def test_every_input_is_accounted_for(self):
        rows = entries(record("otter", 300), record("fireflies", 900),
                       record("read.ai", 600), record("otter", 50, title="Solo"))
        selected, skipped, _ = select(rows)
        self.assertEqual(len(selected) + len(skipped), len(rows))
        ids = {e["record"]["transcript_id"] for e in selected + skipped}
        self.assertEqual(ids, {r["record"]["transcript_id"] for r in rows})

    def test_skipped_records_carry_winner_provenance(self):
        _selected, skipped, _ = select(
            entries(record("fireflies", 1000, tid="win"),
                    record("read.ai", 500, tid="lose")))
        provenance = skipped[0]["superseded_by"]
        self.assertEqual(provenance["transcript_id"], "win")
        self.assertEqual(provenance["provider"], "fireflies")
        self.assertIn("chars", provenance)
        self.assertIn("path", provenance)

    def test_selection_is_independent_of_input_order(self):
        rows = [record("otter", 500, tid="a"), record("fireflies", 500, tid="b"),
                record("read.ai", 500, tid="c")]
        first, _, _ = select(entries(*rows))
        second, _, _ = select(entries(*reversed(rows)))
        self.assertEqual(first[0]["record"]["transcript_id"],
                         second[0]["record"]["transcript_id"])

    def test_exact_tie_is_broken_by_transcript_id(self):
        selected, _, groups = select(
            entries(record("otter", 500, tid="zzz"),
                    record("read.ai", 500, tid="aaa")))
        self.assertEqual(selected[0]["record"]["transcript_id"], "aaa")
        self.assertEqual(groups[0]["reason"], "tie-broken-by-transcript-id")

    def test_selection_does_not_mutate_input_records(self):
        source = record("fireflies", 1000)
        before = json.dumps(source, sort_keys=True)
        select(entries(source, record("read.ai", 500)))
        self.assertEqual(json.dumps(source, sort_keys=True), before)

    def test_unknown_scope_is_rejected(self):
        with self.assertRaises(ValueError):
            select(entries(record("otter", 10)), scope="whatever")

    def test_empty_input_is_not_an_error(self):
        selected, skipped, groups = select([])
        self.assertEqual((selected, skipped, groups), ([], [], []))

    def test_missing_full_text_scores_zero_length(self):
        selected, _, _ = select(
            entries(record("otter", 0, tid="empty"), record("read.ai", 10)))
        self.assertEqual(selected[0]["provider"], "read.ai")


class DuplicateGroupsTest(unittest.TestCase):
    def test_cross_provider_duplicates_are_reported(self):
        offenders = duplicate_groups(
            [record("otter", 10), record("read.ai", 10)])
        self.assertEqual(len(offenders), 1)

    def test_same_provider_duplicates_are_clean_under_default_scope(self):
        rows = [record("otter", 10, tid="a"), record("otter", 10, tid="b")]
        self.assertEqual(duplicate_groups(rows), {})
        self.assertEqual(len(duplicate_groups(rows, scope=SCOPE_ALL)), 1)

    def test_selected_output_has_no_duplicates_left(self):
        selected, _, _ = select(
            entries(record("otter", 300), record("fireflies", 900),
                    record("read.ai", 600)))
        self.assertEqual(
            duplicate_groups(selected, scope=SCOPE_CROSS_PROVIDER), {})


class EndToEndTest(unittest.TestCase):
    """Drive the real CLI and acceptance script over files on disk."""

    def setUp(self):
        import tempfile
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)

    def write_export(self, name, records):
        export = self.root / name
        export.mkdir()
        for rec in records:
            (export / f"{rec['transcript_id']}.json").write_text(
                json.dumps(rec), encoding="utf-8")
        return export

    def run_script(self, script, *args):
        return subprocess.run(
            [sys.executable, str(SCRIPTS / script), *map(str, args)],
            capture_output=True, text=True)

    def test_cli_selects_and_acceptance_passes(self):
        a = self.write_export("prov_a", [
            record("fireflies", 1000, tid="ff-dup"),
            record("fireflies", 100, title="Only Fireflies", tid="ff-solo"),
        ])
        b = self.write_export("prov_b", [
            record("read.ai", 400, tid="ra-dup"),
            record("read.ai", 100, title="Only Readai", tid="ra-solo"),
        ])
        out = self.root / "selected"

        build = self.run_script("select_transcripts.py", out, a, b)
        self.assertEqual(build.returncode, 0, build.stdout + build.stderr)

        manifest = json.loads((out / "selection_manifest.json").read_text())
        self.assertEqual(manifest["totals"]["input_records"], 4)
        self.assertEqual(manifest["totals"]["selected_records"], 3)
        self.assertEqual(manifest["totals"]["skipped_records"], 1)
        self.assertEqual(manifest["skipped"][0]["transcript_id"], "ra-dup")
        self.assertEqual(
            manifest["skipped"][0]["superseded_by"]["transcript_id"], "ff-dup")

        # Sources must survive untouched: selection is not destructive.
        self.assertEqual(len(list(a.glob("*.json"))), 2)
        self.assertEqual(len(list(b.glob("*.json"))), 2)

        check = self.run_script("acceptance_transcript_selection.py", out)
        self.assertEqual(check.returncode, 0, check.stdout + check.stderr)
        self.assertIn("PASS", check.stdout)

    def test_dry_run_writes_nothing(self):
        export = self.write_export("prov", [record("otter", 10, tid="x")])
        out = self.root / "nope"
        result = self.run_script(
            "select_transcripts.py", out, export, "--dry-run")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(out.exists())
        self.assertIn("DRY RUN", result.stdout)

    def test_acceptance_fails_on_a_tampered_manifest(self):
        # The checker must re-derive the policy, not trust the manifest.
        a = self.write_export("prov_a", [record("fireflies", 1000, tid="ff")])
        b = self.write_export("prov_b", [record("read.ai", 400, tid="ra")])
        out = self.root / "selected"
        self.run_script("select_transcripts.py", out, a, b)

        manifest_path = out / "selection_manifest.json"
        manifest = json.loads(manifest_path.read_text())
        # Claim the short capture won, without changing the files.
        manifest["selected"][0]["transcript_id"] = "ra"
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

        check = self.run_script("acceptance_transcript_selection.py", out)
        self.assertEqual(check.returncode, 1)
        self.assertIn("FAIL", check.stdout)

    def test_acceptance_fails_when_a_duplicate_is_smuggled_in(self):
        a = self.write_export("prov_a", [record("fireflies", 1000, tid="ff")])
        b = self.write_export("prov_b", [record("read.ai", 400, tid="ra")])
        out = self.root / "selected"
        self.run_script("select_transcripts.py", out, a, b)

        # Drop the losing capture back into the selected set.
        (out / "ra.json").write_text(
            json.dumps(record("read.ai", 400, tid="ra")), encoding="utf-8")
        check = self.run_script("acceptance_transcript_selection.py", out)
        self.assertEqual(check.returncode, 1)
        self.assertIn("not in manifest", check.stdout)

    def test_acceptance_rejects_a_missing_manifest(self):
        bare = self.root / "bare"
        bare.mkdir()
        check = self.run_script("acceptance_transcript_selection.py", bare)
        self.assertEqual(check.returncode, 1)


if __name__ == "__main__":
    unittest.main()
