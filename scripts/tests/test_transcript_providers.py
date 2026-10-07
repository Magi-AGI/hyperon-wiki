#!/usr/bin/env python3
"""Offline tests for Fireflies pagination/live-filtering and Read AI OAuth.

No network calls and no credentials: the Fireflies transport is stubbed and
the Read AI tests cover pure URL/PKCE/token-handling logic.

Run:
    python scripts/tests/test_transcript_providers.py
"""

import os
import sys
import json
import time
import base64
import hashlib
import tempfile
import unittest
import urllib.parse
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from scripts.pipeline import transcript_sources as ts
from scripts.pipeline.transcript_sources import (
    TranscriptRecord,
    fireflies_list_transcripts,
    fireflies_get_transcript,
    fireflies_to_record,
    is_usable_transcript,
    save_transcripts_json,
    FIREFLIES_MAX_PAGE_SIZE,
)


def make_transcript(i, is_live=False, title=None, date="2026-05-01T10:00:00.000Z"):
    return {
        "id": f"T{i:04d}",
        "title": title or f"Meeting {i}",
        "date": 1746090000000,
        "dateString": date,
        "duration": 1800,
        "is_live": is_live,
        "organizer_email": "organizer@example.com",
        "participants": ["a@example.com"],
        "transcript_url": f"https://app.fireflies.ai/view/T{i:04d}",
        "summary": {
            "overview": "An overview.",
            "shorthand_bullet": ["point one"],
            "action_items": "do a thing\ndo another thing",
            "keywords": "alpha, beta",
        },
    }


class StubAPI:
    """Records requests and serves canned pages, mimicking the real API."""

    def __init__(self, transcripts, page_cap=FIREFLIES_MAX_PAGE_SIZE,
                 ignore_skip=False):
        self.transcripts = transcripts
        self.page_cap = page_cap
        self.ignore_skip = ignore_skip
        self.calls = []

    def __call__(self, query, variables=None, api_key=""):
        variables = variables or {}
        self.calls.append(dict(variables))

        if not api_key:
            raise AssertionError("transport called without an API key")

        if "GetTranscript" in query or "transcript(id" in query:
            tid = variables.get("id")
            for t in self.transcripts:
                if t["id"] == tid:
                    return {"data": {"transcript": t}}
            return {"errors": [{"message": "not found"}]}

        limit = variables.get("limit", 10)
        if limit > self.page_cap:
            return {"errors": [{"message": "Invalid argument(s) were provided"}]}

        rows = self.transcripts
        frm, to = variables.get("fromDate"), variables.get("toDate")
        if frm:
            rows = [r for r in rows if (r.get("dateString") or "") >= frm]
        if to:
            rows = [r for r in rows if (r.get("dateString") or "") <= to]

        skip = 0 if self.ignore_skip else variables.get("skip", 0)
        return {"data": {"transcripts": rows[skip:skip + limit]}}


class FirefliesPaginationTests(unittest.TestCase):
    def setUp(self):
        self._orig = ts._fireflies_request

    def tearDown(self):
        ts._fireflies_request = self._orig

    def install(self, stub):
        ts._fireflies_request = stub

    def test_walks_every_page_beyond_one_limit(self):
        stub = StubAPI([make_transcript(i) for i in range(1, 121)])
        self.install(stub)
        result = fireflies_list_transcripts("k")
        self.assertEqual(len(result), 120)
        self.assertEqual(len({t["id"] for t in result}), 120)
        # 50 + 50 + 20 -> three requests
        self.assertEqual([c["skip"] for c in stub.calls], [0, 50, 100])

    def test_never_requests_more_than_the_api_cap(self):
        stub = StubAPI([make_transcript(i) for i in range(1, 60)])
        self.install(stub)
        fireflies_list_transcripts("k", page_size=500)
        for call in stub.calls:
            self.assertLessEqual(call["limit"], FIREFLIES_MAX_PAGE_SIZE)

    def test_single_short_page_stops_immediately(self):
        stub = StubAPI([make_transcript(i) for i in range(1, 27)])
        self.install(stub)
        result = fireflies_list_transcripts("k")
        self.assertEqual(len(result), 26)
        self.assertEqual(len(stub.calls), 1)

    def test_live_transcripts_excluded_by_default(self):
        rows = [make_transcript(1), make_transcript(2, is_live=True),
                make_transcript(3)]
        self.install(StubAPI(rows))
        result = fireflies_list_transcripts("k")
        self.assertEqual({t["id"] for t in result}, {"T0001", "T0003"})

    def test_live_transcripts_included_on_request(self):
        rows = [make_transcript(1), make_transcript(2, is_live=True)]
        self.install(StubAPI(rows))
        result = fireflies_list_transcripts("k", include_live=True)
        self.assertEqual(len(result), 2)

    def test_missing_is_live_treated_as_unsafe(self):
        row = make_transcript(1)
        del row["is_live"]
        self.install(StubAPI([row]))
        self.assertEqual(fireflies_list_transcripts("k"), [])
        self.assertFalse(is_usable_transcript({}))
        self.assertFalse(is_usable_transcript({"is_live": None}))
        self.assertTrue(is_usable_transcript({"is_live": False}))

    def test_deduplicates_repeated_rows_across_pages(self):
        # A shifting result set can return the same row on two pages.
        rows = [make_transcript(i) for i in range(1, 51)]
        rows += [make_transcript(1), make_transcript(99)]
        self.install(StubAPI(rows))
        result = fireflies_list_transcripts("k")
        self.assertEqual(len(result), 51)
        self.assertEqual(len({t["id"] for t in result}), 51)

    def test_server_ignoring_skip_does_not_loop_forever(self):
        stub = StubAPI([make_transcript(i) for i in range(1, 51)],
                       ignore_skip=True)
        self.install(stub)
        result = fireflies_list_transcripts("k")
        self.assertEqual(len(result), 50)
        self.assertLess(len(stub.calls), 5)

    def test_date_window_backfill_is_passed_through(self):
        rows = [
            make_transcript(1, date="2026-01-15T10:00:00.000Z"),
            make_transcript(2, date="2026-06-15T10:00:00.000Z"),
            make_transcript(3, date="2026-09-15T10:00:00.000Z"),
        ]
        stub = StubAPI(rows)
        self.install(stub)
        result = fireflies_list_transcripts(
            "k",
            from_date="2026-05-01T00:00:00.000Z",
            to_date="2026-07-01T00:00:00.000Z",
        )
        self.assertEqual({t["id"] for t in result}, {"T0002"})
        self.assertEqual(stub.calls[0]["fromDate"], "2026-05-01T00:00:00.000Z")

    def test_graphql_errors_return_empty_not_crash(self):
        def failing(query, variables=None, api_key=""):
            return {"errors": [{"message": "Invalid API key"}]}
        self.install(failing)
        self.assertEqual(fireflies_list_transcripts("k"), [])

    def test_detail_fetch_rejects_live_transcript(self):
        rows = [make_transcript(7, is_live=True)]
        self.install(StubAPI(rows))
        self.assertEqual(fireflies_get_transcript("T0007", "k"), {})
        got = fireflies_get_transcript("T0007", "k", include_live=True)
        self.assertEqual(got["id"], "T0007")

    def test_api_key_required(self):
        with self.assertRaises(ValueError):
            self._orig("query { user { name } }", api_key="")


class RecordMappingTests(unittest.TestCase):
    def test_is_live_propagates_to_record(self):
        rec = fireflies_to_record(make_transcript(1, is_live=True))
        self.assertTrue(rec.is_live)
        self.assertIn("is_live", rec.to_dict())

    def test_prefers_iso_datestring_over_epoch(self):
        rec = fireflies_to_record(
            make_transcript(1, date="2026-03-04T12:00:00.000Z")
        )
        self.assertEqual(rec.date, "2026-03-04")

    def test_newline_action_items_split(self):
        rec = fireflies_to_record(make_transcript(1))
        self.assertEqual(rec.action_items,
                         ["do a thing", "do another thing"])
        self.assertEqual(rec.keywords, ["alpha", "beta"])


class SaveTranscriptsTests(unittest.TestCase):
    def test_same_title_same_day_does_not_overwrite(self):
        recs = [
            TranscriptRecord(meeting_name="Standup", date="2026-05-01",
                             source_service="fireflies.ai", summary="",
                             action_items=[], transcript_id="AAAAAAAA1111",
                             full_text="first"),
            TranscriptRecord(meeting_name="Standup", date="2026-05-01",
                             source_service="fireflies.ai", summary="",
                             action_items=[], transcript_id="BBBBBBBB2222",
                             full_text="second"),
        ]
        with tempfile.TemporaryDirectory() as td:
            out = save_transcripts_json(recs, Path(td))
            files = sorted(p.name for p in out.glob("*.json")
                           if p.name != "export_summary.json")
            self.assertEqual(len(files), 2, f"overwrote a record: {files}")
            texts = {json.loads((out / f).read_text())["full_text"]
                     for f in files}
            self.assertEqual(texts, {"first", "second"})

    def test_summary_counts_and_range(self):
        recs = [
            TranscriptRecord(meeting_name="A", date="2026-01-02",
                             source_service="fireflies.ai", summary="",
                             action_items=[], transcript_id="X1"),
            TranscriptRecord(meeting_name="B", date="2026-09-30",
                             source_service="fireflies.ai", summary="",
                             action_items=[], transcript_id="X2",
                             is_live=True),
        ]
        with tempfile.TemporaryDirectory() as td:
            out = save_transcripts_json(recs, Path(td))
            summary = json.loads((out / "export_summary.json").read_text())
            self.assertEqual(summary["total_transcripts"], 2)
            self.assertEqual(summary["files_written"], 2)
            self.assertEqual(summary["live_transcripts"], 1)
            self.assertEqual(summary["date_range"]["earliest"], "2026-01-02")
            self.assertEqual(summary["date_range"]["latest"], "2026-09-30")


# ---------------------------------------------------------------------------
# Read AI OAuth
# ---------------------------------------------------------------------------

from scripts import readai_oauth as ro


class PKCETests(unittest.TestCase):
    def test_verifier_shape_is_rfc7636_compliant(self):
        for length in (43, 64, 128):
            v = ro.generate_code_verifier(length)
            self.assertEqual(len(v), length)
            self.assertRegex(v, r"^[A-Za-z0-9\-._~]+$")

    def test_verifier_length_bounds_enforced(self):
        for bad in (42, 129, 0):
            with self.assertRaises(ValueError):
                ro.generate_code_verifier(bad)

    def test_verifiers_are_unique(self):
        self.assertEqual(len({ro.generate_code_verifier() for _ in range(50)}),
                         50)

    def test_challenge_matches_s256_definition(self):
        v = ro.generate_code_verifier()
        expected = base64.urlsafe_b64encode(
            hashlib.sha256(v.encode("ascii")).digest()
        ).decode().rstrip("=")
        self.assertEqual(ro.code_challenge_for(v), expected)

    def test_challenge_is_unpadded(self):
        self.assertNotIn("=", ro.code_challenge_for(ro.generate_code_verifier()))

    def test_challenge_rejects_malformed_verifier(self):
        for bad in ("short", "has spaces in it " * 4, "!" * 50):
            with self.assertRaises(ValueError):
                ro.code_challenge_for(bad)

    def test_known_rfc7636_appendix_b_vector(self):
        # RFC 7636 Appendix B worked example.
        verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        self.assertEqual(
            ro.code_challenge_for(verifier),
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
        )


class AuthorizeURLTests(unittest.TestCase):
    def creds(self):
        return {
            "client_id": "client-abc",
            "redirect_uri": ro.DEFAULT_REDIRECT_URI,
            "scope": ro.DEFAULT_SCOPE,
            "authorization_endpoint": "https://authn.read.ai/oauth2/auth",
        }

    def parse(self, url):
        parts = urllib.parse.urlsplit(url)
        return parts, dict(urllib.parse.parse_qsl(parts.query))

    def test_contains_all_required_oauth21_params(self):
        v = ro.generate_code_verifier()
        url = ro.build_authorize_url(self.creds(), v, "state-xyz")
        parts, q = self.parse(url)
        self.assertEqual(parts.netloc, "authn.read.ai")
        self.assertEqual(parts.path, "/oauth2/auth")
        self.assertEqual(q["response_type"], "code")
        self.assertEqual(q["client_id"], "client-abc")
        self.assertEqual(q["state"], "state-xyz")
        self.assertEqual(q["code_challenge"], ro.code_challenge_for(v))

    def test_code_challenge_method_always_explicit(self):
        # RFC 7636 defaults the method to "plain" when omitted, which would
        # silently downgrade PKCE.
        url = ro.build_authorize_url(self.creds(),
                                     ro.generate_code_verifier(), "s")
        _, q = self.parse(url)
        self.assertEqual(q["code_challenge_method"], "S256")

    def test_verifier_never_appears_in_url(self):
        v = ro.generate_code_verifier()
        url = ro.build_authorize_url(self.creds(), v, "s")
        self.assertNotIn(v, url)

    def test_resource_indicator_included_when_given(self):
        url = ro.build_authorize_url(self.creds(),
                                     ro.generate_code_verifier(), "s",
                                     resource=ro.READAI_MCP_RESOURCE)
        _, q = self.parse(url)
        self.assertEqual(q["resource"], ro.READAI_MCP_RESOURCE)

    def test_resource_omitted_when_not_given(self):
        url = ro.build_authorize_url(self.creds(),
                                     ro.generate_code_verifier(), "s")
        _, q = self.parse(url)
        self.assertNotIn("resource", q)

    def test_offline_access_scope_requested(self):
        # Without offline_access Read AI issues no refresh token.
        self.assertIn("offline_access", ro.DEFAULT_SCOPE)


class CredentialStoreTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self._prev = os.environ.get("READAI_CREDENTIAL_DIR")
        os.environ["READAI_CREDENTIAL_DIR"] = self.tmp.name

    def tearDown(self):
        if self._prev is None:
            os.environ.pop("READAI_CREDENTIAL_DIR", None)
        else:
            os.environ["READAI_CREDENTIAL_DIR"] = self._prev
        self.tmp.cleanup()

    def test_roundtrip(self):
        ro.save_credentials({"client_id": "abc"})
        self.assertEqual(ro.load_credentials()["client_id"], "abc")

    def test_missing_file_returns_empty(self):
        self.assertEqual(ro.load_credentials(), {})

    def test_refuses_to_write_inside_a_git_repo(self):
        repo = Path(self.tmp.name) / "repo"
        (repo / ".git").mkdir(parents=True)
        os.environ["READAI_CREDENTIAL_DIR"] = str(repo / "creds")
        with self.assertRaises(SystemExit):
            ro.save_credentials({"client_id": "abc"})

    def test_default_dir_is_outside_the_repo(self):
        os.environ.pop("READAI_CREDENTIAL_DIR", None)
        d = str(ro.credential_dir()).replace("\\", "/").lower()
        self.assertNotIn("magi-agi", d)
        self.assertNotIn("hyperon-wiki", d)

    def test_rotated_refresh_token_is_persisted(self):
        ro.save_credentials({"client_id": "c", "refresh_token": "old"})
        creds = ro.load_credentials()
        ro._store_token_response(creds, {
            "access_token": "at-new",
            "refresh_token": "rotated",
            "expires_in": 599,
        })
        stored = ro.load_credentials()
        self.assertEqual(stored["refresh_token"], "rotated")
        self.assertEqual(stored["access_token"], "at-new")
        self.assertGreater(stored["expires_at"], time.time())

    def test_absent_refresh_token_does_not_clear_existing(self):
        # Read AI may omit refresh_token; blanking it would break the chain.
        ro.save_credentials({"client_id": "c", "refresh_token": "keepme"})
        creds = ro.load_credentials()
        ro._store_token_response(creds, {"access_token": "at",
                                         "expires_in": 599})
        self.assertEqual(ro.load_credentials()["refresh_token"], "keepme")

    def test_expiry_computed_with_skew_margin(self):
        ro.save_credentials({"client_id": "c"})
        creds = ro.load_credentials()
        ro._store_token_response(creds, {"access_token": "at",
                                         "expires_in": 599})
        stored = ro.load_credentials()
        # A 599s token must be treated as stale before it actually expires.
        self.assertLess(stored["expires_at"] - ro.EXPIRY_SKEW_SECONDS,
                        stored["expires_at"])
        self.assertGreater(ro.EXPIRY_SKEW_SECONDS, 0)

    def test_status_prints_no_token_material(self):
        import io
        import contextlib
        ro.save_credentials({
            "client_id": "c", "client_secret": "SUPERSECRET",
            "access_token": "AT-SECRET", "refresh_token": "RT-SECRET",
            "expires_at": int(time.time()) + 300,
        })
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            ro.cmd_status()
        out = buf.getvalue()
        for secret in ("SUPERSECRET", "AT-SECRET", "RT-SECRET"):
            self.assertNotIn(secret, out)
        self.assertIn("present", out)


class DiscoveryURLTests(unittest.TestCase):
    def test_rfc9728_protected_resource_path_shape(self):
        # RFC 9728 inserts the well-known segment between host and path.
        self.assertEqual(
            ro.PROTECTED_RESOURCE_METADATA_URL,
            "https://api.read.ai/.well-known/oauth-protected-resource/mcp",
        )

    def test_resource_identifiers_are_absolute_without_fragment(self):
        for uri in (ro.READAI_MCP_RESOURCE, ro.READAI_REST_RESOURCE):
            parts = urllib.parse.urlsplit(uri)
            self.assertEqual(parts.scheme, "https")
            self.assertFalse(parts.fragment)


# ---------------------------------------------------------------------------
# Read AI REST export: pagination, normalisation, token handling
# ---------------------------------------------------------------------------

def make_readai_meeting(i, start_ms=1790614437657, title=None, turns=None,
                        with_rich=False):
    meeting = {
        "id": f"01M3MEZZRS3GBVD60CPWH8C{i:03d}",
        "start_time_ms": start_ms,
        "end_time_ms": start_ms + 3600000,
        "scheduled_start_time_ms": start_ms,
        "scheduled_end_time_ms": start_ms + 3600000,
        "title": title or f"Read Meeting {i}",
        "participants": [
            {"name": "Alice", "email": "a@example.com",
             "invited": True, "attended": True},
            {"name": "Bob", "email": None, "invited": False, "attended": True},
            {"name": None, "email": None, "invited": True, "attended": False},
        ],
        "owner": {"name": "Alice", "email": "a@example.com"},
        "report_url": f"https://app.read.ai/analytics/meetings/{i}",
        "platform": "zoom",
        "platform_id": "123456789",
        "folders": ["01FOLDER"],
        "live_enabled": True,
        "access_level": "owner",
    }
    if turns is not None:
        meeting["transcript"] = {
            "speakers": [{"name": "Alice"}, {"name": "Bob"}],
            "text": "flat blob",
            "turns": turns,
        }
    if with_rich:
        meeting.update({
            "summary": "Overall summary.",
            "chapter_summaries": [
                {"title": "Intro", "description": "Greetings."},
                {"title": "Design", "description": "Decisions."},
            ],
            "action_items": ["Ship it", "Write docs"],
            "key_questions": ["Is it ready?"],
            "topics": ["architecture", "timeline"],
            "metrics": {"read_score": 80, "sentiment": "positive",
                        "engagement": 0.5},
        })
    return meeting


class ReadAIPaginationTests(unittest.TestCase):
    """Read AI pages with an opaque cursor; page/offset params are ignored."""

    def _recorder(self, pages):
        calls = []

        def fake_request(url, token_provider):
            token_provider()  # exercise the per-request token path
            calls.append(url)
            query = urllib.parse.parse_qs(urllib.parse.urlsplit(url).query)
            cursor = (query.get("cursor") or [None])[0]
            for index, page in enumerate(pages):
                page_cursor = (None if index == 0
                               else pages[index - 1]["data"][-1]["id"])
                if cursor == page_cursor:
                    return page
            raise AssertionError(f"unexpected cursor {cursor!r}")

        return fake_request, calls

    def test_walks_every_cursor_page(self):
        pages = [
            {"object": "list", "url": "/v1/meetings", "has_more": True,
             "data": [make_readai_meeting(i) for i in range(0, 10)]},
            {"object": "list", "url": "/v1/meetings", "has_more": True,
             "data": [make_readai_meeting(i) for i in range(10, 20)]},
            {"object": "list", "url": "/v1/meetings", "has_more": False,
             "data": [make_readai_meeting(20)]},
        ]
        fake, calls = self._recorder(pages)
        out = ts.readai_list_meetings(lambda: "tok", api_request=fake)

        self.assertEqual(len(out), 21)
        self.assertEqual(len({m["id"] for m in out}), 21)
        self.assertEqual(len(calls), 3)
        # First request carries no cursor; later ones chain off the last id.
        self.assertNotIn("cursor=", calls[0])
        self.assertIn("cursor=" + pages[0]["data"][-1]["id"], calls[1])

    def test_stops_when_has_more_false_even_with_full_page(self):
        pages = [{"object": "list", "url": "/v1/meetings", "has_more": False,
                  "data": [make_readai_meeting(i) for i in range(10)]}]
        fake, calls = self._recorder(pages)
        out = ts.readai_list_meetings(lambda: "tok", api_request=fake)
        self.assertEqual(len(out), 10)
        self.assertEqual(len(calls), 1)

    def test_page_size_clamped_to_api_cap(self):
        captured = []

        def fake(url, token_provider):
            captured.append(url)
            return {"has_more": False, "data": []}

        ts.readai_list_meetings(lambda: "tok", limit=500, api_request=fake)
        self.assertIn(f"limit={ts.READAI_MAX_PAGE_SIZE}", captured[0])
        self.assertEqual(ts.READAI_MAX_PAGE_SIZE, 10)

    def test_stalled_cursor_does_not_loop_or_duplicate(self):
        """A server that ignores the cursor must not yield infinite repeats."""
        same = {"object": "list", "url": "/v1/meetings", "has_more": True,
                "data": [make_readai_meeting(i) for i in range(10)]}
        calls = []

        def fake(url, token_provider):
            calls.append(url)
            return same

        out = ts.readai_list_meetings(lambda: "tok", api_request=fake,
                                      max_pages=50)
        self.assertEqual(len(out), 10)
        self.assertEqual(len({m["id"] for m in out}), 10)
        self.assertLess(len(calls), 4)

    def test_date_filters_are_sent_as_start_datetime_bounds(self):
        captured = []

        def fake(url, token_provider):
            captured.append(url)
            return {"has_more": False, "data": []}

        ts.readai_list_meetings(lambda: "tok",
                                start_datetime_gte="2026-01-01T00:00:00Z",
                                start_datetime_lte="2026-02-01T23:59:59Z",
                                api_request=fake)
        query = urllib.parse.parse_qs(
            urllib.parse.urlsplit(captured[0]).query)
        self.assertEqual(query["start_datetime_gte"],
                         ["2026-01-01T00:00:00Z"])
        self.assertEqual(query["start_datetime_lte"],
                         ["2026-02-01T23:59:59Z"])


class ReadAIExpandQueryTests(unittest.TestCase):
    def test_expand_uses_bracketed_repeated_parameter(self):
        """`expand=` (unbracketed) returns HTTP 200 with no rich content."""
        query = ts.readai_expand_query(["transcript", "summary"])
        self.assertEqual(query, "expand[]=transcript&expand[]=summary")

    def test_default_sections_request_transcript_but_not_recording(self):
        self.assertIn("transcript", ts.READAI_EXPAND_SECTIONS)
        # A signed recording URL is credential-like and must not be persisted.
        self.assertNotIn("recording_download", ts.READAI_EXPAND_SECTIONS)

    def test_get_meeting_builds_expanded_url(self):
        seen = {}

        def fake(url, token_provider):
            seen["url"] = url
            return {}

        ts.readai_get_meeting("01ABC", lambda: "tok", api_request=fake)
        self.assertIn("/v1/meetings/01ABC?", seen["url"])
        self.assertIn("expand[]=transcript", seen["url"])


class ReadAINormalisationTests(unittest.TestCase):
    def test_turns_become_ordered_speaker_sentences(self):
        turns = [
            {"start_time_ms": 3000, "end_time_ms": 4000,
             "speaker": {"name": "Bob"}, "text": "Bye."},
            {"start_time_ms": 1000, "end_time_ms": 2000,
             "speaker": {"name": "Alice"}, "text": "Hello."},
        ]
        record = ts.readai_to_record(
            make_readai_meeting(1, turns=turns, with_rich=True))

        self.assertEqual(record.source_service, "read.ai")
        self.assertEqual([s["speaker_name"] for s in record.sentences],
                         ["Alice", "Bob"])
        # Chronological order, not API order.
        self.assertTrue(record.full_text.startswith("Alice: Hello."))
        self.assertIn("Bob: Bye.", record.full_text)

    def test_missing_speaker_name_falls_back_to_unknown(self):
        turns = [{"start_time_ms": 1, "end_time_ms": 2, "speaker": None,
                  "text": "Anon."}]
        record = ts.readai_to_record(make_readai_meeting(2, turns=turns))
        self.assertEqual(record.sentences[0]["speaker_name"], "Unknown")

    def test_epoch_ms_maps_to_utc_iso_date_and_duration(self):
        meeting = make_readai_meeting(3, start_ms=1790614437657, turns=[])
        record = ts.readai_to_record(meeting)
        self.assertEqual(record.date, "2026-09-28")
        self.assertEqual(record.duration_minutes, 60)

    def test_rich_sections_fold_into_summary_and_keywords(self):
        record = ts.readai_to_record(
            make_readai_meeting(4, turns=[], with_rich=True))
        self.assertIn("Overall summary.", record.summary)
        self.assertIn("Intro", record.summary)
        self.assertIn("Is it ready?", record.summary)
        self.assertEqual(record.action_items, ["Ship it", "Write docs"])
        self.assertEqual(record.keywords, ["architecture", "timeline"])

    def test_live_enabled_does_not_mark_record_live(self):
        """`live_enabled` is a feature flag, not an in-progress capture."""
        meeting = make_readai_meeting(5, turns=[])
        self.assertTrue(meeting["live_enabled"])
        record = ts.readai_to_record(meeting)
        self.assertFalse(record.is_live)

    def test_participants_drop_nameless_entries(self):
        record = ts.readai_to_record(make_readai_meeting(6, turns=[]))
        self.assertEqual(record.participants, ["Alice", "Bob"])

    def test_flat_text_used_when_turns_absent(self):
        meeting = make_readai_meeting(7, turns=[])
        meeting["transcript"]["turns"] = []
        record = ts.readai_to_record(meeting)
        self.assertEqual(record.full_text, "flat blob")

    def test_untitled_meeting_still_yields_a_card_name(self):
        meeting = make_readai_meeting(8, turns=[])
        meeting["title"] = None
        record = ts.readai_to_record(meeting)
        self.assertEqual(record.meeting_name, "Untitled Read AI Meeting")
        self.assertIn("Raw Data+transcripts+", record.card_name())

    def test_has_transcript_detects_download_disabled_meetings(self):
        self.assertFalse(ts.readai_has_transcript({"transcript": None}))
        self.assertFalse(ts.readai_has_transcript(
            {"transcript": {"turns": [], "text": ""}}))
        self.assertTrue(ts.readai_has_transcript(
            {"transcript": {"turns": [{"text": "hi"}]}}))


class ReadAITokenHandlingTests(unittest.TestCase):
    def test_token_resolved_per_request_not_once_per_export(self):
        """~10-minute tokens expire mid-walk, so every call re-resolves."""
        minted = []

        def provider():
            minted.append(len(minted))
            return f"tok-{len(minted)}"

        pages = [
            {"has_more": True,
             "data": [make_readai_meeting(i) for i in range(10)]},
            {"has_more": False, "data": [make_readai_meeting(10)]},
        ]
        state = {"n": 0}

        def fake(url, token_provider):
            token_provider()
            page = pages[state["n"]]
            state["n"] = min(state["n"] + 1, len(pages) - 1)
            return page

        ts.readai_list_meetings(provider, api_request=fake)
        self.assertEqual(len(minted), 2)

    def test_http_error_message_omits_bearer_token(self):
        import urllib.error
        import io

        def boom(*args, **kwargs):
            raise urllib.error.HTTPError(
                "https://api.read.ai/v1/meetings", 401, "Unauthorized", {},
                io.BytesIO(b'{"detail":"expired"}'))

        original = ts.urllib.request.urlopen
        ts.urllib.request.urlopen = boom
        try:
            with self.assertRaises(RuntimeError) as ctx:
                ts._readai_request("https://api.read.ai/v1/meetings",
                                   lambda: "SUPERSECRETTOKEN")
        finally:
            ts.urllib.request.urlopen = original

        message = str(ctx.exception)
        self.assertNotIn("SUPERSECRETTOKEN", message)
        self.assertIn("401", message)
        self.assertIn("/v1/meetings", message)


class ReadAIExportArtifactTests(unittest.TestCase):
    def test_export_refuses_to_write_inside_the_repository(self):
        from scripts import export_readai as er
        repo_root = Path(er.__file__).resolve().parents[1]
        with self.assertRaises(SystemExit):
            er._assert_outside_repo(repo_root / "publication_texts" / "x")

    def test_default_output_dir_is_outside_the_repository(self):
        from scripts import export_readai as er
        repo_root = Path(er.__file__).resolve().parents[1]
        out = er.default_output_dir()
        with self.assertRaises(ValueError):
            out.resolve().relative_to(repo_root)
        self.assertIn("readai_", out.name)

    def test_iso_bounds_cover_whole_days(self):
        from scripts import export_readai as er
        self.assertEqual(er._iso_bound("2026-01-02"), "2026-01-02T00:00:00Z")
        self.assertEqual(er._iso_bound("2026-01-02", end_of_day=True),
                         "2026-01-02T23:59:59Z")
        self.assertEqual(er._iso_bound(""), "")

    def test_saved_records_contain_no_credential_material(self):
        turns = [{"start_time_ms": 1, "end_time_ms": 2,
                  "speaker": {"name": "Alice"}, "text": "Hello."}]
        record = ts.readai_to_record(
            make_readai_meeting(9, turns=turns, with_rich=True))
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            save_transcripts_json([record], out)
            blob = "\n".join(p.read_text(encoding="utf-8")
                             for p in out.glob("*.json"))
        for marker in ("access_token", "refresh_token", "Bearer",
                       "client_secret"):
            self.assertNotIn(marker, blob)
        self.assertIn("read.ai", blob)


if __name__ == "__main__":
    unittest.main(verbosity=2)
