"""Offline regression tests for the Mattermost export path.

No network, no credentials, no real Mattermost server: `mattermostdriver` is
stubbed and the API responses are fixtures. Run with:

    python -m unittest discover -s scripts/tests

Each test here pins a defect found in review. Read the docstrings before
changing the exporter's output shape.
"""

import json
import sys
import tempfile
import types
import unittest
from datetime import datetime, timezone
from pathlib import Path

SCRIPTS_DIR = Path(__file__).resolve().parents[1]
REPO_ROOT = SCRIPTS_DIR.parent

# `mattermostdriver` is not needed to exercise the export logic, and requiring
# it would make these tests depend on an install step. Stub it before import.
if "mattermostdriver" not in sys.modules:
    stub = types.ModuleType("mattermostdriver")
    stub.Driver = object
    sys.modules["mattermostdriver"] = stub

sys.path.insert(0, str(SCRIPTS_DIR))
sys.path.insert(0, str(REPO_ROOT))

from mattermost_exporter import MattermostExporter  # noqa: E402
from scripts.pipeline.sources import mattermost_channel_to_raw_text  # noqa: E402


def ts(iso: str) -> int:
    """ISO date -> Mattermost millisecond timestamp."""
    return int(datetime.fromisoformat(iso).replace(tzinfo=timezone.utc).timestamp() * 1000)


class FakeDriver:
    """Minimal stand-in for mattermostdriver.Driver, fed from fixtures."""

    def __init__(self, posts, order, team_name="hyperon"):
        outer = self

        class Posts:
            def get_posts_for_channel(self, channel_id, params=None):
                # One page, then an empty page to end the loop.
                if params and params.get("page", 0) > 0:
                    return {"posts": {}, "order": []}
                return {"posts": outer._posts, "order": outer._order}

        class Teams:
            def get_team(self, team_id):
                return {"name": outer._team_name}

        class Users:
            def get_user(self, user_id):
                return {"id": user_id, "username": f"user_{user_id}"}

        self._posts = posts
        self._order = order
        self._team_name = team_name
        self.posts = Posts()
        self.teams = Teams()
        self.users = Users()


def build_exporter(posts, order):
    """An exporter with its connection already stubbed out."""
    exporter = MattermostExporter.__new__(MattermostExporter)
    exporter.host = "fixture.invalid"
    exporter.driver = FakeDriver(posts, order)
    exporter.user_cache = {"u1": "alice", "u2": "bob"}
    exporter.my_user_id = "me"
    exporter.my_username = "me"
    return exporter


class ExportChannelPathTest(unittest.TestCase):
    """The exporter must report where it wrote, not leave callers guessing.

    `export_channel` strips punctuation when building the on-disk name, so a
    caller that rediscovers the file by globbing the display name finds
    nothing. That returned zero channels to the pipeline in review.
    """

    def test_returns_written_path_for_punctuated_channel_name(self):
        posts = {
            "p1": {"id": "p1", "user_id": "u1", "create_at": ts("2026-01-02"),
                   "message": "hello", "metadata": {}},
        }
        exporter = build_exporter(posts, ["p1"])
        channel = {
            "id": "c1", "name": "qa-general", "type": "O", "team_id": "t1",
            "display_name": "Q&A / general?",
        }

        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            json_file = exporter.export_channel(channel, out, download_files=False)

            self.assertIsNotNone(json_file, "export_channel must return the path it wrote")
            self.assertTrue(Path(json_file).is_file())

            # The returned path round-trips; the old wildcard approach does not.
            data = json.loads(Path(json_file).read_text(encoding="utf-8"))
            self.assertEqual(data["channel"]["display_name"], "Q&A / general?")

            legacy_name = channel["display_name"].replace("/", "_").replace("\\", "_")
            legacy_hits = list(out.rglob(f"*{legacy_name}*.json"))
            self.assertEqual(
                legacy_hits, [],
                "fixture must reproduce the rediscovery failure this test guards",
            )


class OrphanReplyTest(unittest.TestCase):
    """A date filter must not silently swallow replies.

    When `after` excludes a thread root but keeps its replies, both consumers
    render replies only underneath a retained root — so the replies vanish.
    They are promoted to top level and labelled instead.
    """

    def _export(self):
        posts = {
            "root": {"id": "root", "user_id": "u1", "create_at": ts("2026-01-01"),
                     "message": "the original question", "metadata": {}},
            "reply": {"id": "reply", "user_id": "u2", "create_at": ts("2026-03-01"),
                      "message": "LATE REPLY BODY", "root_id": "root", "metadata": {}},
        }
        exporter = build_exporter(posts, ["reply", "root"])
        channel = {"id": "c1", "name": "general", "type": "O", "team_id": "t1",
                   "display_name": "general"}

        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        json_file = exporter.export_channel(
            channel, Path(tmp.name), download_files=False,
            after=datetime(2026, 2, 1, tzinfo=timezone.utc),
        )
        return json.loads(Path(json_file).read_text(encoding="utf-8"))

    def test_orphan_reply_is_retained_and_marked(self):
        data = self._export()

        ids = [p["id"] for p in data["posts"]]
        self.assertEqual(ids, ["reply"], "root is before the cutoff; reply is after")

        orphan = data["posts"][0]
        self.assertTrue(orphan.get("orphan_reply"))
        self.assertNotIn("is_reply", orphan, "must not stay hidden under an absent root")
        self.assertEqual(orphan["root_id"], "root", "root reference kept for provenance")
        self.assertEqual(data["channel"]["orphan_reply_count"], 1)
        self.assertEqual(data["threads"], {}, "no thread group for an absent root")

    def test_orphan_reply_appears_in_rendered_raw_text(self):
        text = mattermost_channel_to_raw_text(self._export())
        self.assertIn("LATE REPLY BODY", text, "retained message must not be dropped")
        self.assertIn("outside export window", text, "and must be marked as orphaned")


class IntactThreadTest(unittest.TestCase):
    """The orphan path must not disturb normal threading."""

    def test_reply_with_retained_root_still_nests(self):
        posts = {
            "root": {"id": "root", "user_id": "u1", "create_at": ts("2026-03-01"),
                     "message": "question", "metadata": {}},
            "reply": {"id": "reply", "user_id": "u2", "create_at": ts("2026-03-02"),
                      "message": "answer", "root_id": "root", "metadata": {}},
        }
        exporter = build_exporter(posts, ["reply", "root"])
        channel = {"id": "c1", "name": "general", "type": "O", "team_id": "t1",
                   "display_name": "general"}

        with tempfile.TemporaryDirectory() as tmp:
            json_file = exporter.export_channel(channel, Path(tmp), download_files=False)
            data = json.loads(Path(json_file).read_text(encoding="utf-8"))

        reply = next(p for p in data["posts"] if p["id"] == "reply")
        self.assertTrue(reply.get("is_reply"))
        self.assertNotIn("orphan_reply", reply)
        self.assertEqual(data["channel"]["orphan_reply_count"], 0)
        self.assertIn("root", data["threads"])

        text = mattermost_channel_to_raw_text(data)
        self.assertIn("answer", text)
        self.assertNotIn("outside export window", text)


class DuplicateDisplayNameTest(unittest.TestCase):
    """Two channels may share a display name; neither may be overwritten.

    Mattermost display names are not unique. The on-disk directory used to be
    derived purely from the display name, so the second channel with a given
    name silently clobbered the first one's JSON — the run reported N channels
    while only N-1 survived, and the loser's code snippets were stranded in the
    winner's directory. Observed live: two channels both named `test` produced
    186 reported / 185 on disk plus 42 orphaned `*_code.txt` files.
    """

    def test_colliding_display_names_both_survive(self):
        channels = [
            {"id": "cid_aaa", "name": "test-jan1", "type": "O", "team_id": "t1",
             "display_name": "test"},
            {"id": "cid_bbb", "name": "test-other", "type": "O", "team_id": "t1",
             "display_name": "test"},
        ]
        per_channel = {
            "cid_aaa": {"p1": {"id": "p1", "user_id": "u1", "create_at": ts("2026-01-01"),
                               "message": "FIRST BODY\n```\ncode_a\n```", "metadata": {}}},
            "cid_bbb": {"p2": {"id": "p2", "user_id": "u2", "create_at": ts("2026-01-02"),
                               "message": "SECOND BODY\n```\ncode_b\n```", "metadata": {}}},
        }

        class PerChannelDriver(FakeDriver):
            def __init__(self, mapping):
                super().__init__({}, [])
                outer = self

                class Posts:
                    def get_posts_for_channel(self, channel_id, params=None):
                        if params and params.get("page", 0) > 0:
                            return {"posts": {}, "order": []}
                        posts = mapping.get(channel_id, {})
                        return {"posts": posts, "order": list(posts.keys())}

                self.posts = Posts()

        exporter = build_exporter({}, [])
        exporter.driver = PerChannelDriver(per_channel)

        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            written = [Path(exporter.export_channel(c, out, download_files=False))
                       for c in channels]

            self.assertTrue(all(p.is_file() for p in written),
                            "neither export may be overwritten by the other")
            self.assertEqual(
                len({p.parent for p in written}), 2,
                "colliding display names must land in separate directories",
            )

            ids, bodies = [], []
            for path in written:
                data = json.loads(path.read_text(encoding="utf-8"))
                ids.append(data["channel"]["id"])
                bodies.append(data["posts"][0]["message"].splitlines()[0])

            self.assertEqual(sorted(ids), ["cid_aaa", "cid_bbb"])
            self.assertEqual(sorted(bodies), ["FIRST BODY", "SECOND BODY"])

            # Code snippets must belong only to their own channel's directory.
            for path in written:
                data = json.loads(path.read_text(encoding="utf-8"))
                declared = {p["code_file"] for p in data["posts"] if p.get("code_file")}
                on_disk = {f.name for f in path.parent.glob("*_code.txt")}
                self.assertEqual(declared, on_disk,
                                 f"orphaned/missing code files in {path.parent.name}")

    def test_same_channel_reuses_its_directory(self):
        """Re-exporting one channel must not spawn a duplicate directory."""
        posts = {"p1": {"id": "p1", "user_id": "u1", "create_at": ts("2026-01-01"),
                        "message": "hello", "metadata": {}}}
        exporter = build_exporter(posts, ["p1"])
        channel = {"id": "c1", "name": "general", "type": "O", "team_id": "t1",
                   "display_name": "general"}

        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            first = Path(exporter.export_channel(channel, out, download_files=False))
            second = Path(exporter.export_channel(channel, out, download_files=False))

            self.assertEqual(first, second, "same channel id must reuse its directory")
            self.assertEqual(
                [p.name for p in out.iterdir() if p.is_dir()], ["general"],
            )


if __name__ == "__main__":
    unittest.main()
