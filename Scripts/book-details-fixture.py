#!/usr/bin/env python3
"""Loopback Jellyfin fixture for GusBookDetailUITests. No external requests."""

import argparse
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit
from uuid import uuid4

USER = {"Id": "11111111111111111111111111111111", "Name": "Book Fixture"}
SERVER = "77777777777777777777777777777777"
BOOK = {
    "Id": "42000000000000000000000000000001", "Type": "Book",
    "Name": "Fixture Printed Book", "ProductionYear": 2024, "CanDownload": True,
    "Overview": ("First printed paragraph. The station librarian finds a book due back a century earlier. "
                 "Its notes send her through the closed wing, where every shelf holds a different account "
                 "of the same voyage. She must discover which account the missing reader wanted her to find."
                 "<p>Each map describes a different route.</p><p>One page bears the seal of her own library.</p>"
                 "\\n\\nSecond printed paragraph."),
    "RunTimeTicks": 10000000, "UserData": {"PlaybackPositionTicks": 2500000, "PlayedPercentage": 25},
    "Genres": ["Fantasy", "Adventure"],
    "Studios": [{"Name": "Fixture Studio"}],
    "People": [{"Name": "Fixture Author", "Type": "Author"}, {"Name": "Fixture Illustrator", "Type": "Illustrator"}],
}
AUDIOBOOK = {
    "Id": "42000000000000000000000000000002", "Type": "AudioBook",
    "Name": "Fixture Audiobook", "ProductionYear": 2025,
    "Overview": ("A spoken opening. A radio operator hears a familiar voice on a silent channel. "
                 "As she follows the signal along the coast, the story unfolds through recordings, "
                 "letters and fragments of the last broadcast from the island lighthouse."
                 "<p>She follows the boats inland.</p><p>The final tape names the keeper.</p>"
                 "\\n\\nA second paragraph."),
    "RunTimeTicks": 72000000000, "UserData": {"PlaybackPositionTicks": 18000000000, "PlayedPercentage": 25},
    "Genres": ["Movie, TV & Video Game Tie-Ins, Adventure, Contemporary Fantasy"],
    "People": [{"Name": "Fixture Author", "Type": "Author"}, {"Name": "Fixture Reader", "Type": "Narrator"}],
}


def volume(template, number, title, index):
    return {**template, "Id": f"4200000000000000000000000000{number:04d}",
            "Name": title, "SeriesName": "Fixture Saga", "IndexNumber": index,
            "Overview": "A short synopsis.", "UserData": {"Played": False}}


ITEMS = [BOOK, AUDIOBOOK, volume(BOOK, 3, "Second Volume", 2),
         volume(BOOK, 4, "First Volume", 1), volume(AUDIOBOOK, 5, "Spoken Volume", 1)]


class Handler(BaseHTTPRequestHandler):
    user = USER
    server_id = SERVER
    version = "10.11.11"
    items = ITEMS

    def respond(self, response, status=200):
        data = b"" if status == 204 else json.dumps(response).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        if self.path == "/Users/AuthenticateByName":
            self.rfile.read(int(self.headers.get("Content-Length", 0)))
            self.respond({"User": self.user, "AccessToken": "gus-book-fixture", "ServerId": self.server_id})
        else:
            self.respond({}, 404)

    def do_GET(self):
        url = urlsplit(self.path)
        path = url.path
        query = {key.lower(): values for key, values in parse_qs(url.query).items()}
        if path == "/health":
            self.respond({"fixture": "gus-book-details"})
        elif path.endswith("/Download"):
            book = next((item for item in self.items if item["Type"] == "Book" and path == "/Items/" + item["Id"] + "/Download"), None)
            if not book:
                return self.respond({}, 404)
            if "gus-book-fixture" not in self.headers.get("Authorization", "") or "api_key" in query:
                return self.respond({}, 401)
            # Original, valid EPUB bytes. The real server sends a filename with Content-Disposition.
            data = (Path(__file__).resolve().parents[1] / "Tests/APlayaNamedGusTests/Fixtures/ReaderOwnership.epub").read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "application/epub+zip")
            self.send_header("Content-Disposition", 'attachment; filename="Fixture original edition.epub"')
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        elif path == "/System/Info/Public":
            self.respond({"Id": self.server_id, "ServerName": "Book Fixture", "Version": self.version})
        elif path in ("/Users/Me", "/Users/" + self.user["Id"]):
            self.respond(self.user)
        elif path == "/UserViews" or path.endswith("/Views"):
            self.respond({"Items": [{"Id": "42000000000000000000000000000000", "Name": "Mixed Library", "Type": "CollectionFolder", "CollectionType": "books"}], "TotalRecordCount": 1})
        elif path.endswith("/Latest"):
            self.respond(self.items)
        elif path.endswith("/SpecialFeatures"):
            self.respond([])
        elif path.endswith(("/Items", "/Resume", "/NextUp", "/Similar", "/AdditionalParts")):
            kinds = [kind for value in query.get("includeitemtypes", []) for kind in value.split(",")]
            items = [item for item in self.items if item["Type"] in kinds]
            if not kinds and query.get("parentid") == ["42000000000000000000000000000000"]:
                items = self.items
            limit = int(query.get("limit", ["60"])[0])
            offset = int(query.get("startindex", ["0"])[0])
            self.respond({"Items": items[offset:offset + limit], "TotalRecordCount": len(items), "StartIndex": offset})
        else:
            item = next((item for item in self.items if path.endswith("/Items/" + item["Id"])), None)
            self.respond(item or {}, 200 if item else 404)


class AdminHandler(Handler):
    """Disposable series-edit account. Each sign-in begins with the original catalog."""
    user = {**USER, "Policy": {"IsAdministrator": True, "AuthenticationProviderId": "fixture",
                               "PasswordResetProviderId": "fixture"}}
    server_id = "88888888888888888888888888888888"
    version = "12.4.0"
    collections = {}

    def do_GET(self):
        url = urlsplit(self.path)
        query = {k.lower(): v for k, v in parse_qs(url.query).items()}
        if url.path == "/UserViews" or url.path.endswith("/Views"):
            views = [
                {"Id": "42000000000000000000000000000000", "Name": "Mixed Library", "CollectionType": "books"},
                {"Id": "43000000000000000000000000000000", "Name": "Movie Library", "CollectionType": "movies"},
                {"Id": "44000000000000000000000000000000", "Name": "Collections", "CollectionType": "boxsets"},
            ]
            return self.respond({"Items": [{**view, "Type": "CollectionFolder"} for view in views],
                                 "TotalRecordCount": len(views)})
        collection_id = url.path.rsplit("/", 1)[-1].replace("-", "")
        if "/Items/" in url.path and collection_id in self.collections:
            return self.respond(self.collections[collection_id][0])
        if url.path.endswith("/Items"):
            parent = query.get("parentid", [""])[0].replace("-", "")
            if "BoxSet" in query.get("includeitemtypes", []):
                items = [header for header, _ in self.collections.values()]
            elif parent in self.collections:
                members = self.collections[parent][1]
                items = [item for item in self.items if item["Id"] in members]
            else:
                return super().do_GET()
            offset = int(query.get("startindex", ["0"])[0])
            limit = int(query.get("limit", ["60"])[0])
            return self.respond({"Items": items[offset:offset + limit], "TotalRecordCount": len(items)})
        super().do_GET()

    def do_POST(self):
        url = urlsplit(self.path)
        path = url.path
        if path == "/Users/AuthenticateByName":
            type(self).items = [dict(item) for item in ITEMS]
            empty_id = "44000000000000000000000000000001"
            type(self).collections = {empty_id: ({"Id": empty_id, "Type": "BoxSet",
                                                  "Name": "Empty Collection", "CanDelete": True}, set())}
            return super().do_POST()
        if path == "/Collections" or path.startswith("/Collections/"):
            query = {k.lower(): v for k, v in parse_qs(url.query).items()}
            members = {i.replace("-", "") for ids in query.get("ids", []) for i in ids.split(",") if i}
            if not members.issubset({item["Id"] for item in self.items}):
                return self.respond({}, 400)
            if path == "/Collections":
                collection_id = uuid4().hex
                header = {"Id": collection_id, "Type": "BoxSet", "Name": query["name"][0], "CanDelete": True}
                self.collections[collection_id] = (header, members)
                return self.respond({"Id": collection_id})
            parts = path.strip("/").split("/")
            if len(parts) != 3 or parts[2] != "Items":
                return self.respond({}, 404)
            collection = self.collections.get(parts[1].replace("-", ""))
            if collection is None:
                return self.respond({}, 404)
            collection[1].update(members)
            return self.respond(None, 204)
        book = next((item for item in self.items if path == "/Items/" + item["Id"]
                     and item["Type"] == "Book"), None)
        if book is None:
            return self.respond({}, 404)
        update = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        if "SeriesName" not in update or update != {**book, "SeriesName": update["SeriesName"]}:
            return self.respond({}, 400)
        # Exercise a server that accepts the second edit but fails to persist it.
        interrupted = "Interrupted Series"
        if update["SeriesName"] != interrupted or not any(item.get("SeriesName") == interrupted for item in self.items):
            book["SeriesName"] = update["SeriesName"]
        self.respond(None, 204)


class SynopsisHandler(Handler):
    """Short and long rights-cleared descriptions for the responsive detail tests."""
    items = [
        {"Id": "46000000000000000000000000000001", "Name": "A New City", "Type": "Series",
         "Overview": ("When a family moves from their farm to an unfamiliar city, every errand becomes an "
                      "adventure. Between meeting their neighbors and learning the bus routes, the children "
                      "find unexpected reminders of home in their new neighborhood.")},
        {"Id": "46000000000000000000000000000002", "Name": "The Backyard Launch", "Type": "Episode",
         "Overview": "The children build a backyard rocket to help their neighbor reach for the stars."},
    ]


class GenreHandler(Handler):
    """Model Jellyfin 12's general search result and its genre-ID member query."""
    genre = {"Id": "47000000000000000000000000000001", "Name": "Horror", "Type": "Genre",
             "ImageTags": {"Primary": "serverGenreImage"}}
    members = [{"Id": "47000000000000000000000000000002", "Name": "The Lantern House", "Type": "Movie"},
               {"Id": "47000000000000000000000000000003", "Name": "Night Radio", "Type": "Series"}]
    items = [genre, *members]

    def do_GET(self):
        url = urlsplit(self.path)
        query = {key.lower(): value[0] for key, value in parse_qs(url.query).items()}
        if url.path.endswith("/Items") and "searchterm" in query:
            matches = [item for item in self.items if query["searchterm"].casefold() in item["Name"].casefold()]
        elif url.path.endswith("/Items") and "genreids" in query:
            matches = self.members if query["genreids"].replace("-", "") == self.genre["Id"] else []
        else:
            return super().do_GET()
        offset = int(query.get("startindex", 0))
        limit = int(query.get("limit", 60))
        self.respond({"Items": matches[offset:offset + limit], "TotalRecordCount": len(matches), "StartIndex": offset})


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--series-editor", action="store_true", help="Serve the editable 12.4 fixture on port 5059")
    parser.add_argument("--synopses", action="store_true", help="Serve the responsive synopsis fixture on port 5060")
    parser.add_argument("--genres", action="store_true", help="Serve Jellyfin genre search on port 5061")
    args = parser.parse_args()
    port, handler = (5059, AdminHandler) if args.series_editor else (5058, Handler)
    if args.synopses:
        port, handler = 5060, SynopsisHandler
    if args.genres:
        port, handler = 5061, GenreHandler
    ThreadingHTTPServer(("127.0.0.1", port), handler).serve_forever()
