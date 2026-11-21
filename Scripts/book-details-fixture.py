#!/usr/bin/env python3
"""Loopback Jellyfin fixture for GusBookDetailUITests. No external requests."""

import argparse
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Event
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


class NavigationHandler(Handler):
    """Season choices and per-account profile failures or disappearing movies for navigation tests."""
    server_id = "49494949494949494949494949494949"
    libraries = [
        {"Id": "42000000000000000000000000000000", "Name": "Mixed Library", "CollectionType": "books"},
        {"Id": "49020000000000000000000000000000", "Name": "Music", "CollectionType": "music"},
        {"Id": "49030000000000000000000000000000", "Name": "Photos", "CollectionType": "photos"},
    ]
    series = {"Id": "49000000000000000000000000000000", "Name": "Navigation Series", "Type": "Series"}
    seasons = [{"Id": "49000000000000000000000000000001", "Name": "First Season", "Type": "Season", "IndexNumber": 1},
               {"Id": "49000000000000000000000000000002", "Name": "Second Season", "Type": "Season", "IndexNumber": 2}]
    items = [series, {"Id": "49020000000000000000000000000001", "Type": "MusicAlbum", "Name": "Fixture Album"},
             {"Id": "49030000000000000000000000000001", "Type": "PhotoAlbum", "Name": "Fixture Photos"}]
    pending_profiles = {}
    queue_movies = {}

    def do_POST(self):
        if self.path == "/Users/AuthenticateByName":
            body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            username = body.get("Username", "")
            user_id = username.removeprefix("queue-")
            user = self.user
            if len(user_id) == 32 and all(ch in "0123456789abcdef" for ch in user_id):
                if username.startswith("queue-"):
                    self.queue_movies.setdefault(user_id, True)
                else:
                    self.pending_profiles[user_id] = Event()
                user = {**user, "Id": user_id}
            return self.respond({"User": user, "AccessToken": "gus-navigation-fixture", "ServerId": self.server_id})
        if self.path.startswith("/fixture/remove-movie/"):
            movie_id = self.path.rsplit("/", 1)[-1]
            if movie_id not in self.queue_movies:
                return self.respond({}, 404)
            self.queue_movies[movie_id] = False
            return self.respond(None, 204)
        if self.path.startswith("/fixture/fail-profile/"):
            pending = self.pending_profiles.pop(self.path.rsplit("/", 1)[-1], None)
            if pending is None:
                return self.respond({}, 404)
            pending.set()
            return self.respond(None, 204)
        super().do_POST()

    def do_GET(self):
        url = urlsplit(self.path)
        if url.path == "/health":
            return self.respond({"fixture": "gus-navigation"})
        if url.path == "/UserViews" or url.path.endswith("/Views"):
            return self.respond({"Items": [{**library, "Type": "CollectionFolder"} for library in self.libraries],
                                 "TotalRecordCount": len(self.libraries)})
        parts = url.path.split("/")
        if len(parts) >= 3 and parts[-2] == "Items" and parts[-1] in self.queue_movies:
            movie_id = parts[-1]
            if self.queue_movies[movie_id]:
                return self.respond({"Id": movie_id, "Type": "Movie", "Name": "Recoverable Movie"})
            return self.respond({}, 404)
        if url.path.startswith("/Users/") and url.path.count("/") == 2:
            user_id = url.path.rsplit("/", 1)[-1].replace("-", "")
            if user_id in ("Me", self.user["Id"]):
                return self.respond(self.user)
            if user_id in self.queue_movies:
                return self.respond({**self.user, "Id": user_id})
            pending = self.pending_profiles.get(user_id)
            if pending is not None:
                pending.wait(timeout=60)
            return self.respond({}, 500)
        if url.path == f"/Shows/{self.series['Id']}/Seasons":
            return self.respond({"Items": self.seasons, "TotalRecordCount": len(self.seasons)})
        if url.path == f"/Shows/{self.series['Id']}/Episodes":
            query = {key.lower(): value[0] for key, value in parse_qs(url.query).items()}
            season_id = query.get("seasonid", "").replace("-", "")
            episodes = [{"Id": f"4901000000000000000000000000000{season['IndexNumber']}",
                         "Type": "Episode", "Name": "Episode of " + season["Name"],
                         "SeriesId": self.series["Id"], "SeasonId": season["Id"], "IndexNumber": 1}
                        for season in self.seasons if season["Id"] == season_id]
            return self.respond({"Items": episodes, "TotalRecordCount": len(episodes)})
        super().do_GET()


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
    """General search, typed related metadata lookup and account-filtered member queries."""
    genre = {"Id": "47000000000000000000000000000001", "Name": "Horror", "Type": "Genre",
             "ImageTags": {"Primary": "serverGenreImage"}}
    coastal = {"Id": "47000000000000000000000000000006", "Name": "Coastal Mystery", "Type": "Genre"}
    studio = {"Id": "47000000000000000000000000000005", "Name": "Lantern Pictures", "Type": "Studio"}
    beacon = {"Id": "47000000000000000000000000000007", "Name": "Beacon Works", "Type": "Studio"}
    actor = {"Id": "47000000000000000000000000000008", "Name": "Mara Lake", "Type": "Actor", "Role": "The Keeper"}
    director = {"Id": "47000000000000000000000000000009", "Name": "Rowan Vale", "Type": "Director"}
    members = [{"Id": "47000000000000000000000000000002", "Name": "The Lantern House", "Type": "Movie",
                "BackdropImageTags": ["lanternStill"],
                "Genres": ["Horror", "Coastal Mystery", "Unlisted Genre"], "GenreItems": [genre],
                "Studios": [studio, {"Name": "Beacon Works"}],
                "People": [actor, director, {"Name": "Jules North", "Type": "Actor", "Role": "Visitor"}]},
               {"Id": "47000000000000000000000000000003", "Name": "Night Radio", "Type": "Series"}]
    midnight_genre = {"Id": "47000000000000000000000000000004", "Name": "Midnight Mysteries", "Type": "Genre"}
    midnight_movies = [{"Id": f"4800{index:028d}", "Name": f"Midnight Story {index:02d}", "Type": "Movie"}
                       for index in range(1, 65)]
    # Keep the genre at result 48 and allow enough subsequent rows to clear the keyboard.
    items = [genre, *members, *midnight_movies[:47], midnight_genre, *midnight_movies[47:]]

    def do_GET(self):
        url = urlsplit(self.path)
        query = {key.lower(): value[0] for key, value in parse_qs(url.query).items()}
        if url.path.rstrip("/") in (f"/Items/{self.members[0]['Id']}/Images/Backdrop", f"/Items/{self.members[0]['Id']}/Images/Backdrop/0"):
            # Still from the Library of Congress public-domain copy of The Kiss (1896).
            # https://www.loc.gov/item/00694131/
            data = (Path(__file__).resolve().parents[1] / "Tests/Fixtures/RelatedMovieBackdrop.jpg").read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "image/jpeg")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        if url.path == f"/Items/{self.members[0]['Id']}/Similar":
            matches = self.members[1:]
        elif url.path.endswith("/Items") and "searchterm" in query:
            matches = [item for item in self.items if query["searchterm"].casefold() in item["Name"].casefold()]
        elif url.path in ("/Genres", "/Studios"):
            candidates = [self.genre, self.coastal] if url.path == "/Genres" else [self.studio, self.beacon]
            matches = [item for item in candidates if query.get("searchterm", "").casefold() in item["Name"].casefold()]
        elif url.path.endswith("/Items") and "genreids" in query:
            by_genre = {self.genre["Id"]: self.members, self.coastal["Id"]: self.members[:1] + self.midnight_movies[:48],
                        self.midnight_genre["Id"]: self.members[1:]}
            matches = by_genre.get(query["genreids"].replace("-", ""), [])
        elif url.path.endswith("/Items") and "studioids" in query:
            matches = self.members[:1] if query["studioids"].replace("-", "") in (self.studio["Id"], self.beacon["Id"]) else []
        elif url.path.endswith("/Items") and "personids" in query:
            by_person = {self.actor["Id"]: self.members, self.director["Id"]: self.members[:1]}
            matches = by_person.get(query["personids"].replace("-", ""), [])
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
    parser.add_argument("--navigation", action="store_true", help="Serve profile and season navigation cases on port 5062")
    args = parser.parse_args()
    port, handler = (5059, AdminHandler) if args.series_editor else (5058, Handler)
    if args.synopses:
        port, handler = 5060, SynopsisHandler
    if args.genres:
        port, handler = 5061, GenreHandler
    if args.navigation:
        port, handler = 5062, NavigationHandler
    ThreadingHTTPServer(("127.0.0.1", port), handler).serve_forever()
