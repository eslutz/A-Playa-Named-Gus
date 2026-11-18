#!/usr/bin/env python3
"""Loopback Jellyfin fixture for GusBookDetailUITests. No external requests."""

import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

USER = {"Id": "11111111111111111111111111111111", "Name": "Book Fixture"}
SERVER = "77777777777777777777777777777777"
BOOK = {
    "Id": "42000000000000000000000000000001", "Type": "Book",
    "Name": "Fixture Printed Book", "ProductionYear": 2024,
    "Overview": "First printed paragraph.\\n\\nSecond printed paragraph.",
    "RunTimeTicks": 10000000, "UserData": {"PlaybackPositionTicks": 2500000, "PlayedPercentage": 25},
    "Genres": ["Fantasy", "Adventure"],
    "Studios": [{"Name": "Fixture Studio"}],
    "People": [{"Name": "Fixture Author", "Type": "Author"}, {"Name": "Fixture Illustrator", "Type": "Illustrator"}],
}
AUDIOBOOK = {
    "Id": "42000000000000000000000000000002", "Type": "AudioBook",
    "Name": "Fixture Audiobook", "ProductionYear": 2025,
    "Overview": "A spoken opening.\\n\\nA second paragraph.",
    "RunTimeTicks": 72000000000, "UserData": {"PlaybackPositionTicks": 18000000000, "PlayedPercentage": 25},
    "Genres": ["Movie, TV & Video Game Tie-Ins, Adventure, Contemporary Fantasy"],
    "People": [{"Name": "Fixture Author", "Type": "Author"}, {"Name": "Fixture Reader", "Type": "Narrator"}],
}
ITEMS = [BOOK, AUDIOBOOK]


class Handler(BaseHTTPRequestHandler):
    def respond(self, response, status=200):
        data = json.dumps(response).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        if self.path == "/Users/AuthenticateByName":
            self.rfile.read(int(self.headers.get("Content-Length", 0)))
            self.respond({"User": USER, "AccessToken": "gus-book-fixture", "ServerId": SERVER})
        else:
            self.respond({}, 404)

    def do_GET(self):
        url = urlsplit(self.path)
        path = url.path
        query = {key.lower(): values for key, values in parse_qs(url.query).items()}
        if path == "/health":
            self.respond({"fixture": "gus-book-details"})
        elif path == "/System/Info/Public":
            self.respond({"Id": SERVER, "ServerName": "Book Fixture", "Version": "10.11.11"})
        elif path in ("/Users/Me", "/Users/" + USER["Id"]):
            self.respond(USER)
        elif path == "/UserViews" or path.endswith("/Views"):
            self.respond({"Items": [{"Id": "42000000000000000000000000000000", "Name": "Mixed Library", "Type": "CollectionFolder", "CollectionType": "books"}], "TotalRecordCount": 1})
        elif path.endswith("/Latest"):
            self.respond(ITEMS)
        elif path.endswith("/SpecialFeatures"):
            self.respond([])
        elif path.endswith(("/Items", "/Resume", "/NextUp", "/Similar", "/AdditionalParts")):
            kinds = [kind for value in query.get("includeitemtypes", []) for kind in value.split(",")]
            items = [item for item in ITEMS if item["Type"] in kinds]
            limit = int(query.get("limit", ["60"])[0])
            offset = int(query.get("startindex", ["0"])[0])
            self.respond({"Items": items[offset:offset + limit], "TotalRecordCount": len(items), "StartIndex": offset})
        else:
            item = next((item for item in ITEMS if path.endswith("/Items/" + item["Id"])), None)
            self.respond(item or {}, 200 if item else 404)


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", 5058), Handler).serve_forever()
