#!/usr/bin/env python3
"""Synthetic Seerr UI fixture; binds only to 127.0.0.1 and stores state in memory.

Run beside the isolated Jellyfin demo server before the tvOS remote tests:
    python3 Scripts/tvos-seerr-fixture.py --port 5059

This intentionally models a small API contract, not a production Seerr instance.
It uses no production credentials, external artwork, or outbound network requests.
"""

import argparse
import copy
import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit


MOVIE_ID = 950000001
SHOW_ID = 950000002
USER = {"id": 12, "displayName": "Gus Fixture Manager", "permissions": 48}
SESSION = "gus-fixture-session"
LOCK = threading.RLock()
STATE = {"requests": [], "events": [], "uncertainNext": False}


def media(media_id, media_type):
    related = [record for record in STATE["requests"] if record["media"]["tmdbId"] == media_id]
    active = [record for record in related if record["status"] != 3]
    status = 3 if any(record["status"] == 2 for record in active) else 2 if active else 1
    result = {"id": 100 if media_type == "movie" else 101, "tmdbId": media_id, "mediaType": media_type, "status": status}
    if media_type == "tv":
        result["tvdbId"] = 950000003
        result["seasons"] = [
            {"seasonNumber": number, "status": status if any(
                any(season["seasonNumber"] == number for season in record.get("seasons", []))
                for record in active
            ) else 1}
            for number in [1, 2]
        ]
    return result


def record_model(record):
    result = copy.deepcopy(record)
    result["media"] = media(record["media"]["tmdbId"], record["type"])
    return result


def catalog_item(media_id):
    is_movie = media_id == MOVIE_ID
    media_type = "movie" if is_movie else "tv"
    info = media(media_id, media_type)
    info["requests"] = [record_model(record) for record in STATE["requests"] if record["media"]["tmdbId"] == media_id]
    item = {
        "id": media_id,
        "mediaType": media_type,
        "title" if is_movie else "name": "Gus Fixture Movie" if is_movie else "Gus Fixture Show",
        "releaseDate" if is_movie else "firstAirDate": "2026-01-01",
        "overview": "A synthetic title used to verify Gus discovery and request workflows.",
        "voteAverage": 7.5,
        "runtime": 108 if is_movie else None,
        "backdropPath": "/gus-fictional-fixture.png",
        "credits": {"cast": [{"id": 950000004, "name": "Gus Fixture Actor", "character": "The Navigator"}], "crew": [{"id": 950000004, "name": "Gus Fixture Actor", "job": "Director"}]},
        "mediaInfo": info,
        "releases": {"results": [{"iso_3166_1": "US", "release_dates": [{"certification": "PG", "type": 3}]}]},
    }
    if not is_movie:
        item["externalIds"] = {"tvdbId": 950000003}
        item["contentRatings"] = {"results": [{"iso_3166_1": "US", "rating": "TV-PG"}]}
        item["seasons"] = [
            {"seasonNumber": number, "name": f"Season {number}", "episodeCount": 8}
            for number in [1, 2]
        ]
    return item


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        # Never log request bodies or cookies, even for synthetic credentials.
        pass

    def respond(self, value, status=200, cookie=None):
        body = json.dumps(value).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        if cookie:
            self.send_header("Set-Cookie", cookie)
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        with LOCK:
            self.handle_get()

    def handle_get(self):
        parsed = urlsplit(self.path)
        path, query = parsed.path, parse_qs(parsed.query)
        if path == "/__fixture/health":
            return self.respond({"fixture": "gus-discover", "version": 1})
        if path == "/__fixture/state":
            return self.respond(copy.deepcopy(STATE))
        STATE["events"].append({"method": "GET", "path": path})
        if path == "/api/v1/status":
            return self.respond({"version": "3.3.0"})
        if path == "/api/v1/settings/public":
            return self.respond({"initialized": True, "localLogin": True, "mediaServerLogin": True, "mediaServerType": 2, "enableSpecialEpisodes": False, "partialRequestsEnabled": True, "applicationTitle": "Gus Synthetic Seerr", "movie4kEnabled": False, "series4kEnabled": False})
        if not self.authenticated():
            return self.respond({}, 401)
        if path == "/api/v1/settings/discover":
            return self.respond([{"id": kind, "type": kind, "order": index, "enabled": True, "isBuiltIn": True} for index, kind in enumerate([4, 5, 9])])
        if path == "/api/v1/user/12/quota":
            return self.respond({kind: {"days": 7, "limit": 10, "used": len(STATE["requests"]), "remaining": 10-len(STATE["requests"]), "restricted": False} for kind in ["movie", "tv"]})
        if path.startswith("/api/v1/person/"):
            if path.endswith("/combined_credits"):
                return self.respond({"cast": [catalog_item(MOVIE_ID)], "crew": [catalog_item(SHOW_ID)]})
            return self.respond({"id": 950000004, "name": "Gus Fixture Actor", "biography": "A fictional performer used only for local validation."})
        if "/season/" in path:
            number = int(path.split("/")[-1])
            return self.respond({"seasonNumber": number, "name": f"Season {number}", "episodeCount": 1, "episodes": [{"id": 1, "episodeNumber": 1, "name": "The Fixture", "overview": "Synthetic episode metadata."}]})
        if path.endswith("/recommendations") or path.endswith("/similar"):
            return self.respond({"page": 1, "totalPages": 1, "totalResults": 1, "results": [catalog_item(SHOW_ID if "/movie/" in path else MOVIE_ID)]})
        if path == "/api/v1/auth/me":
            return self.respond(USER)
        if path in ["/api/v1/discover/trending", "/api/v1/discover/movies", "/api/v1/discover/tv", "/api/v1/search"]:
            ids = [SHOW_ID] if path.endswith("/tv") else [MOVIE_ID] if path.endswith("/movies") else [MOVIE_ID, SHOW_ID]
            items = [catalog_item(media_id) for media_id in ids]
            search = query.get("query", [""])[0].lower()
            items = [item for item in items if search in item.get("title", item.get("name", "")).lower()]
            return self.respond({"page": 1, "totalPages": 1, "totalResults": len(items), "results": items})
        if path == f"/api/v1/movie/{MOVIE_ID}":
            return self.respond(catalog_item(MOVIE_ID))
        if path == f"/api/v1/tv/{SHOW_ID}":
            return self.respond(catalog_item(SHOW_ID))
        if path in ["/api/v1/request", "/api/v1/user/12/requests"]:
            records = STATE["requests"]
            if query.get("filter") == ["pending"]:
                records = [record for record in records if record["status"] == 1]
            if "requestedBy" in query:
                records = [record for record in records if str(record["requestedBy"]["id"]) == query["requestedBy"][0]]
            skip = max(0, int(query.get("skip", ["0"])[0]))
            take = max(1, int(query.get("take", ["20"])[0]))
            return self.respond({"pageInfo": {"pages": max(1, (len(records) + take - 1) // take), "pageSize": take, "results": len(records), "page": skip // take + 1}, "results": [record_model(record) for record in records[skip:skip + take]]})
        if path.startswith("/api/v1/request/"):
            record = self.find_record(path.split("/")[-1])
            return self.respond(record_model(record) if record else {}, 200 if record else 404)
        return self.respond({}, 404)

    def do_POST(self):
        with LOCK:
            self.handle_post()

    def handle_post(self):
        path = urlsplit(self.path).path
        try:
            body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", "0"))) or b"{}")
        except (ValueError, json.JSONDecodeError):
            return self.respond({}, 400)
        if path == "/__fixture/reset":
            STATE["requests"].clear()
            STATE["events"].clear()
            STATE["uncertainNext"] = bool(body.get("uncertainNext", False))
            return self.respond({"reset": True})
        STATE["events"].append({"method": "POST", "path": path})
        if path in ["/api/v1/auth/local", "/api/v1/auth/jellyfin"]:
            valid_user = body.get("email") == "fixture@example.invalid" if path.endswith("/local") else body.get("username") == "fixture"
            if not valid_user or body.get("password") != "gus-fixture-only":
                return self.respond({}, 401)
            return self.respond(USER, cookie=f"connect.sid={SESSION}; Path=/; HttpOnly; SameSite=Lax")
        if not self.authenticated():
            return self.respond({}, 401)
        if path == "/api/v1/auth/logout":
            return self.respond({}, cookie="connect.sid=; Path=/; Max-Age=0")
        if path == "/api/v1/request":
            media_id, media_type = body.get("mediaId"), body.get("mediaType")
            if (media_id, media_type) not in [(MOVIE_ID, "movie"), (SHOW_ID, "tv")]:
                return self.respond({}, 400)
            if any(record["media"]["tmdbId"] == media_id and record["status"] != 3 for record in STATE["requests"]):
                return self.respond({}, 409)
            record = {"id": len(STATE["requests"]) + 1, "status": 1, "type": media_type, "media": {"tmdbId": media_id, "mediaType": media_type}, "requestedBy": USER, "createdAt": "2026-10-25T12:00:00.000Z", "is4k": False, "seasons": [{"seasonNumber": number} for number in (body.get("seasons") or [])]}
            STATE["requests"].append(record)
            if STATE["uncertainNext"]:
                STATE["uncertainNext"] = False
                return self.respond({}, 500)
            return self.respond(record_model(record), 201)
        parts = path.split("/")
        if len(parts) == 6 and parts[1:4] == ["api", "v1", "request"] and parts[5] in ["approve", "decline"]:
            record = self.find_record(parts[4])
            if not record:
                return self.respond({}, 404)
            if record["status"] != 1:
                return self.respond({}, 409)
            record["status"] = 2 if parts[5] == "approve" else 3
            return self.respond(record_model(record))
        return self.respond({}, 404)

    def do_DELETE(self):
        with LOCK:
            if not self.authenticated():
                return self.respond({}, 401)
            path = urlsplit(self.path).path
            STATE["events"].append({"method": "DELETE", "path": path})
            if path.startswith("/api/v1/request/"):
                record = self.find_record(path.split("/")[-1])
                if record and record["status"] == 1:
                    STATE["requests"].remove(record)
                    return self.respond({}, 200)
                return self.respond({}, 404)
            return self.respond({}, 404)

    def authenticated(self):
        return f"connect.sid={SESSION}" in self.headers.get("Cookie", "")

    @staticmethod
    def find_record(record_id):
        return next((record for record in STATE["requests"] if str(record["id"]) == record_id), None)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=5056)
    arguments = parser.parse_args()
    server = ThreadingHTTPServer(("127.0.0.1", arguments.port), Handler)
    print(f"Gus Discover synthetic fixture listening on http://127.0.0.1:{arguments.port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
