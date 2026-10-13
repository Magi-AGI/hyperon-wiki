#!/usr/bin/env python3
"""Unit tests for the Python port of the ingest card-naming helpers.

The port in scripts/pipeline/transcript_card_names.py must agree with
scripts/ingest_transcripts.rb. These tests pin the behaviours the offline
acceptance verdict depends on, especially the recurring-meeting shape that
made the old checkers report false collisions:

    two distinct Otter conversations of "MeTTa Study Group" on 2025-05-30

Run: python scripts/tests/test_transcript_card_names.py
"""

import sys
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from pipeline.transcript_card_names import (  # noqa: E402
    PARENT_CARD,
    assign_card_names,
    name_key,
    sanitize_name_part,
)


def rec(name, date, tid):
    return {"meeting_name": name, "date": date, "transcript_id": tid}


class SanitizeNamePart(unittest.TestCase):
    def test_name_joint_and_path_separator_become_dashes(self):
        self.assertEqual(sanitize_name_part("A+B"), "A-B")
        self.assertEqual(sanitize_name_part("A/B"), "A-B")

    def test_markup_and_nest_syntax_stripped(self):
        self.assertEqual(sanitize_name_part('a[b]{c}|d<e>f#g"h'), "a-b-c-d-e-f-g-h")

    def test_whitespace_collapsed_and_trimmed(self):
        self.assertEqual(sanitize_name_part("  MeTTa   Study  Group "), "MeTTa Study Group")

    def test_runs_of_dashes_collapse(self):
        self.assertEqual(sanitize_name_part("a---b"), "a-b")

    def test_leading_reserved_prefixes_removed(self):
        self.assertEqual(sanitize_name_part("*foo"), "foo")
        self.assertEqual(sanitize_name_part("~bar"), "bar")

    def test_empty_becomes_none(self):
        for value in ("", "   ", "---", None):
            self.assertIsNone(sanitize_name_part(value))

    def test_real_otter_titles_survive(self):
        self.assertEqual(sanitize_name_part("MORKification Weekly"), "MORKification Weekly")
        self.assertEqual(
            sanitize_name_part("Meeting / Elowyn AI"), "Meeting - Elowyn AI"
        )


class NameKey(unittest.TestCase):
    def test_camel_case_split_matches_spaced_form(self):
        self.assertEqual(name_key("RawData"), name_key("Raw Data"))

    def test_case_and_punctuation_normalized(self):
        # Decko's key splits camelCase runs, so "MeTTa" keys as "me_tta".
        # Verified against ingest_transcripts.rb via dump_ruby_card_names.rb.
        self.assertEqual(name_key("MeTTa Study Group"), "me_tta_study_group")
        self.assertEqual(name_key("MeTTa Study Group"), name_key("MeTTa-Study-Group"))

    def test_parts_preserved(self):
        self.assertEqual(
            name_key("Raw Data+transcripts+Foo+2025-01-01"),
            "raw_data+transcripts+foo+2025_01_01",
        )

    def test_leading_trailing_separators_trimmed(self):
        self.assertEqual(name_key("--foo--"), "foo")


class AssignCardNames(unittest.TestCase):
    def test_unique_meeting_keeps_bare_title(self):
        plans = assign_card_names([rec("MORKification Weekly", "2026-10-05", "abc")])
        self.assertEqual(
            plans[0]["card_name"],
            f"{PARENT_CARD}+MORKification Weekly+2026-10-05",
        )
        self.assertEqual(plans[0]["label_reason"], "meeting_name")

    def test_same_meeting_different_dates_both_keep_bare_title(self):
        plans = assign_card_names([
            rec("MeTTa Study Group", "2025-05-30", "a"),
            rec("MeTTa Study Group", "2025-06-27", "b"),
        ])
        self.assertEqual([p["label_reason"] for p in plans],
                         ["meeting_name", "meeting_name"])

    def test_duplicate_meeting_same_date_disambiguated_by_transcript_id(self):
        plans = assign_card_names([
            rec("MeTTa Study Group", "2025-05-30", "IgyiPw1I"),
            rec("MeTTa Study Group", "2025-05-30", "MOTpcs6Q"),
        ])
        for p in plans:
            self.assertEqual(p["label_reason"], "meeting_name+transcript_id")
        self.assertEqual(
            plans[0]["card_name"],
            f"{PARENT_CARD}+MeTTa Study Group (IgyiPw1I)+2025-05-30",
        )
        self.assertEqual(len({p["card_key"] for p in plans}), 2)

    def test_three_way_same_date_collision_all_unique(self):
        plans = assign_card_names([
            rec("MeTTa Study Group", "2025-06-27", "_CC34AOw"),
            rec("MeTTa Study Group", "2025-06-27", "pLHSg8qo"),
            rec("MeTTa Study Group", "2025-06-27", "V0WoFUeI"),
        ])
        self.assertEqual(len({p["card_key"] for p in plans}), 3)

    def test_missing_title_falls_back_to_transcript_id(self):
        plans = assign_card_names([rec(None, "2025-12-12", "9UT9btWw")])
        self.assertEqual(plans[0]["label"], "9UT9btWw")

    def test_missing_title_and_id_falls_back_to_unknown_meeting(self):
        plans = assign_card_names([rec(None, "2025-12-12", None)])
        self.assertEqual(plans[0]["label"], "Unknown Meeting")

    def test_missing_date_becomes_unknown_date(self):
        plans = assign_card_names([rec("Foo", None, "x")])
        self.assertTrue(plans[0]["card_name"].endswith("+unknown-date"))

    def test_identical_id_and_title_still_gets_distinct_keys(self):
        # A genuinely degenerate export: same title, date and id twice. The
        # candidate ladder must still produce two distinct keys rather than
        # silently overwriting: the first takes "<title> (<id>)", the second
        # falls through to the bare transcript id.
        plans = assign_card_names([
            rec("Foo", "2025-01-01", "same"),
            rec("Foo", "2025-01-01", "same"),
        ])
        self.assertEqual(len({p["card_key"] for p in plans}), 2)
        self.assertEqual([p["label_reason"] for p in plans],
                         ["meeting_name+transcript_id", "transcript_id"])

    def test_plan_order_matches_input_order(self):
        records = [rec(f"M{i}", "2025-01-01", f"id{i}") for i in range(5)]
        plans = assign_card_names(records)
        self.assertEqual([p["record"]["transcript_id"] for p in plans],
                         [r["transcript_id"] for r in records])

    def test_title_with_name_joint_cannot_create_extra_parts(self):
        plans = assign_card_names([rec("A+B", "2025-01-01", "x")])
        self.assertEqual(plans[0]["card_name"].count("+"),
                         PARENT_CARD.count("+") + 2)


class RubyParity(unittest.TestCase):
    """The port must agree with ingest_transcripts.rb, not merely look right.

    Skipped when ruby is unavailable so the suite still runs on hosts without
    it; the parity claim is only ever made when it was actually checked.
    """

    CASES = [
        # The real recurring-meeting collisions from the Otter full export.
        rec("MeTTa Study Group", "2025-05-30", "IgyiPw1I"),
        rec("MeTTa Study Group", "2025-05-30", "MOTpcs6Q"),
        rec("MeTTa Study Group", "2025-06-27", "_CC34AOw"),
        rec("MeTTa Study Group", "2025-06-27", "pLHSg8qo"),
        rec("MeTTa Study Group", "2025-06-27", "V0WoFUeI"),
        rec("MeTTa Study Group", "2025-07-25", "8giofpSI"),
        rec("MeTTa Study Group", "2025-07-25", "SDbuA2PE"),
        rec("MeTTa Study Group", "2025-08-22", "-HvuR6Wg"),
        rec("MeTTa Study Group", "2025-08-22", "aCDOsjmk"),
        # Non-colliding, plus the awkward shapes.
        rec("MORKification Weekly", "2026-10-05", "5up9-tlE"),
        rec("Meeting / Elowyn AI", "2026-10-05", "TYZQBljI"),
        rec("Lake's Meeting Notes", "2025-12-12", "qaH1Fp1E"),
        rec(None, "2025-12-12", "9UT9btWw"),
        rec(None, "2025-12-13", None),
        rec("A+B", "2025-01-01", "x"),
        rec("*starred", "2025-01-02", "y"),
        rec("Foo", "2025-01-03", "same"),
        rec("Foo", "2025-01-03", "same"),
    ]

    def test_matches_ruby_implementation(self):
        if not shutil.which("ruby"):
            self.skipTest("ruby not available")
        dumper = Path(__file__).resolve().parent / "dump_ruby_card_names.rb"
        with tempfile.TemporaryDirectory() as tmp:
            payload = Path(tmp) / "records.json"
            payload.write_text(json.dumps(self.CASES), encoding="utf-8")
            proc = subprocess.run(
                ["ruby", str(dumper), str(payload)],
                capture_output=True, text=True, timeout=120,
            )
            self.assertEqual(proc.returncode, 0, proc.stderr)
            expected = json.loads(proc.stdout)

        actual = assign_card_names(self.CASES)
        self.assertEqual(len(expected), len(actual))
        for i, (exp, act) in enumerate(zip(expected, actual)):
            for field in ("card_name", "card_key", "label", "label_reason"):
                self.assertEqual(
                    exp[field], act[field],
                    f"record {i} field {field}: ruby={exp[field]!r} "
                    f"python={act[field]!r}",
                )


if __name__ == "__main__":
    unittest.main(verbosity=2)
