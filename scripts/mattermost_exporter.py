#!/usr/bin/env python3
"""Non-interactive Mattermost exporter for the Hyperon Wiki ingestion pipeline.

This module is the Hyperon Wiki's own copy of the exporter. It exists so the
Mattermost ingestion path is self-contained: nothing here reaches outside this
repository. Earlier revisions imported an equivalent class from a sibling
checkout, which made the tooling incomplete on its own.

Deliberately non-interactive. There is no prompting, no browser-cookie
scraping, and no config-file persistence — credentials arrive as an argument or
an environment variable and are never written to disk. See
`docs/INGESTION-WORKFLOWS.md`.

Consumers:
    scripts/export_mattermost.py
    scripts/pipeline/sources.py

Requires:
    pip install mattermostdriver
"""

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Optional

from mattermostdriver import Driver

__all__ = ["MattermostExporter"]


class MattermostExporter:
    """Exports Mattermost channels to the JSON format the ingesters expect.

    The output shape is consumed by `scripts/ingest_mattermost.rb` and by
    `scripts/pipeline/`. Changing the JSON structure means changing those too.
    """

    def __init__(self, host: str, token: Optional[str] = None,
                 username: Optional[str] = None, password: Optional[str] = None):
        self.host = host
        self.driver = self._connect(host, token, username, password)
        self.user_cache: Dict[str, str] = {}
        self.my_user_id: str = ""
        self.my_username: str = ""

    def _connect(self, host: str, token: Optional[str],
                 username: Optional[str], password: Optional[str]) -> Driver:
        """Establish a connection to the Mattermost server."""
        driver = Driver({
            "url": host,
            "port": 443,
            "token": token,
            "username": username,
            "password": password,
            "scheme": "https",
        })
        try:
            driver.login()
            print(f"OK Connected to {host}")
            return driver
        except Exception as exc:
            print(f"FAILED Connection to {host}: {exc}")
            raise

    def initialize_user_data(self) -> None:
        """Load the current user and build the user-id → username cache."""
        my_user = self.driver.users.get_user("me")
        self.my_username = my_user["username"]
        self.my_user_id = my_user["id"]
        print(f"OK Logged in as {self.my_username} ({self.my_user_id})")

        print("Loading users...", end=" ", flush=True)
        page = 0
        while True:
            users = self.driver.users.get_users(params={"per_page": 200, "page": page})
            if not users:
                break
            for user in users:
                self.user_cache[user["id"]] = user["username"]
            page += 1
        print(f"OK {len(self.user_cache)} users loaded")

    def get_username(self, user_id: str) -> str:
        """Return a username for a user ID, fetching and caching on a miss."""
        if user_id not in self.user_cache:
            try:
                user = self.driver.users.get_user(user_id)
                self.user_cache[user_id] = user["username"]
            except Exception:
                # A deleted or inaccessible account must not abort an export.
                self.user_cache[user_id] = f"unknown_user_{user_id[:8]}"
        return self.user_cache[user_id]

    def _organize_threads(self, posts: List[Dict]) -> Dict[str, List[Dict]]:
        """Group reply posts under their root post ID, each sorted by time.

        Orphan replies — those whose root fell outside a date filter — are
        skipped here on purpose. They are promoted to top level instead, so
        they are still rendered; grouping them under an absent root would make
        them invisible to every consumer.
        """
        threads: Dict[str, List[Dict]] = {}
        for post in posts:
            root_id = post.get("root_id")
            if not root_id or post.get("orphan_reply"):
                continue
            threads.setdefault(root_id, []).append({
                "id": post["id"],
                "idx": post["idx"],
                "username": post["username"],
                "created": post["created"],
                "message": post["message"],
            })

        for root_id in threads:
            threads[root_id].sort(key=lambda reply: reply["created"])

        return threads

    def list_teams(self) -> List[Dict]:
        """Return every team the authenticated user belongs to."""
        print("Loading teams...", end=" ", flush=True)
        teams = self.driver.teams.get_user_teams(self.my_user_id)
        print(f"OK {len(teams)} teams found")
        return teams

    def list_channels(self, team_id: str) -> List[Dict]:
        """Return the authenticated user's channels for a team."""
        print("Loading channels...", end=" ", flush=True)
        channels = self.driver.channels.get_channels_for_user(self.my_user_id, team_id)

        # Direct-message channels are named by user-id pair, which is unreadable.
        for channel in channels:
            if channel["type"] == "D":
                user_ids = channel["name"].split("__")
                other_id = user_ids[1] if user_ids[0] == self.my_user_id else user_ids[0]
                channel["display_name"] = f"DM: {self.get_username(other_id)}"

        channels.sort(key=lambda c: c["display_name"].lower())
        print(f"OK {len(channels)} channels found")
        return channels

    def export_channel(self, channel: Dict, output_dir: Path,
                       download_files: bool = True,
                       after: Optional[datetime] = None,
                       before: Optional[datetime] = None) -> Path:
        """Export one channel to `<output_dir>/<safe name>/<safe name>.json`.

        Posts are written oldest-first with a stable `idx`. Fenced code blocks
        are split into sibling `NNNN_code.txt` files, and attachments are
        downloaded alongside when `download_files` is set.

        Returns the path of the JSON file written. Callers must use this rather
        than reconstructing it from the channel's display name — the on-disk
        name has punctuation stripped, so a name like `Q&A / general` will not
        round-trip.
        """
        channel_name = channel["display_name"].replace("/", "_").replace("\\", "_")
        print(f"\n{'=' * 60}")
        print(f"Exporting: {channel_name}")
        print(f"{'=' * 60}")

        after_ts = after.timestamp() if after else None
        before_ts = before.timestamp() if before else None

        all_posts: List[Dict] = []
        page = 0
        while True:
            print(f"  Fetching page {page}...", end=" ", flush=True)
            response = self.driver.posts.get_posts_for_channel(
                channel["id"],
                params={"per_page": 200, "page": page},
            )

            if not response["posts"]:
                print("done")
                break

            page_posts = [response["posts"][post_id] for post_id in response["order"]]
            all_posts.extend(page_posts)
            print(f"OK {len(page_posts)} posts")
            page += 1

        print(f"  Total posts: {len(all_posts)}")

        safe_name = "".join(c for c in channel_name if c.isalnum() or c in " _-").strip()
        channel_dir = output_dir / safe_name
        channel_dir.mkdir(parents=True, exist_ok=True)

        processed_posts: List[Dict] = []
        for idx, post in enumerate(reversed(all_posts)):
            created_ts = post["create_at"] / 1000

            if (before_ts and created_ts > before_ts) or (after_ts and created_ts < after_ts):
                continue

            username = self.get_username(post["user_id"])
            created = datetime.fromtimestamp(created_ts, timezone.utc).isoformat().replace("+00:00", "Z")

            post_data = {
                "idx": idx,
                "id": post["id"],
                "created": created,
                "username": username,
                "message": post["message"],
            }

            if post.get("root_id"):
                post_data["root_id"] = post["root_id"]
                post_data["is_reply"] = True

            message = post["message"]
            if message.count("```") >= 2:
                start = message.find("```") + 3
                end = message.rfind("```")
                code = message[start:end].strip()
                if code:
                    code_file = channel_dir / f"{idx:04d}_code.txt"
                    code_file.write_text(code, encoding="utf-8")
                    post_data["code_file"] = code_file.name

            if "files" in post.get("metadata", {}):
                filenames = []
                for file_info in post["metadata"]["files"]:
                    filename = f"{idx:04d}_{file_info['name']}"
                    filenames.append(file_info["name"])

                    if download_files:
                        try:
                            print(f"  Downloading: {file_info['name']}...", end=" ", flush=True)
                            file_data = self.driver.files.get_file(file_info["id"])

                            file_path = channel_dir / filename
                            if isinstance(file_data, dict):
                                file_path.write_text(json.dumps(file_data, indent=2))
                            else:
                                file_path.write_bytes(file_data.content)
                            print("OK")
                        except Exception as exc:
                            # One unreachable attachment must not lose the channel.
                            print(f"FAILED {exc}")

                post_data["files"] = filenames

            processed_posts.append(post_data)

        # A date filter can drop a thread root while keeping its replies. Both
        # consumers render replies only underneath a retained root, so those
        # replies would vanish. Promote them to top level and label them, so
        # nothing is silently lost and the missing context is visible.
        retained_ids = {p["id"] for p in processed_posts}
        orphan_count = 0
        for post_data in processed_posts:
            if post_data.get("is_reply") and post_data["root_id"] not in retained_ids:
                del post_data["is_reply"]
                post_data["orphan_reply"] = True
                orphan_count += 1

        try:
            team_info = self.driver.teams.get_team(channel["team_id"])
            team_name = team_info["name"]
        except Exception:
            team_name = "unknown"

        threads = self._organize_threads(processed_posts)
        thread_count = len([p for p in processed_posts if p.get("is_reply")])

        export_data = {
            "channel": {
                "id": channel["id"],
                "name": channel["name"],
                "display_name": channel["display_name"],
                "type": channel["type"],
                "team": team_name,
                "team_id": channel["team_id"],
                "header": channel.get("header", ""),
                "purpose": channel.get("purpose", ""),
                "exported_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
                "post_count": len(processed_posts),
                "thread_count": thread_count,
                "orphan_reply_count": orphan_count,
            },
            "posts": processed_posts,
            "threads": threads,
        }

        json_file = channel_dir / f"{safe_name}.json"
        json_file.write_text(
            json.dumps(export_data, indent=2, ensure_ascii=False),
            encoding="utf-8",
        )

        print(f"OK Exported to: {json_file}")
        print(f"  Posts: {len(processed_posts)}")
        if thread_count > 0:
            print(f"  Thread replies: {thread_count} across {len(threads)} threads")
        if orphan_count > 0:
            print(f"  Orphan replies (root outside date filter): {orphan_count}")

        return json_file
