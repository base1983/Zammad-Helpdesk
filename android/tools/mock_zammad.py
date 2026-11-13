#!/usr/bin/env python3
"""A tiny fake Zammad for trying the debug build without a real server.

    python3 android/tools/mock_zammad.py          # listens on :8089

In the emulator's setup wizard use server `http://10.0.2.2:8089` and any token; if
that times out, run `adb reverse tcp:8089 tcp:8089` and use `http://127.0.0.1:8089`.
(Debug builds allow cleartext to those two addresses only; release builds never do.)
The colleague chat will report "unavailable": the relay validates the token
against a Zammad it can reach, which this mock is not.
"""
import json, re, sys
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

NOW = datetime.now(timezone.utc)
def ts(**delta): return (NOW + timedelta(**delta)).strftime("%Y-%m-%dT%H:%M:%S.000Z")

STATES = [{"id": i, "state_type_id": t, "name": n, "active": True} for i, t, n in
          [(1, 1, "new"), (2, 2, "open"), (3, 3, "pending reminder"), (4, 5, "closed"), (7, 4, "pending close")]]
PRIORITIES = [{"id": 1, "name": "1 low", "active": True}, {"id": 2, "name": "2 normal", "active": True},
              {"id": 3, "name": "3 high", "active": True}]
USERS = [
    {"id": 1, "login": "-", "firstname": "-", "lastname": "", "email": "", "active": False, "role_ids": []},
    {"id": 3, "login": "agent@example.com", "firstname": "Demo", "lastname": "Agent", "email": "agent@example.com",
     "active": True, "role_ids": [2], "organization_id": None},
    {"id": 4, "login": "colleague@example.com", "firstname": "Demo", "lastname": "Colleague",
     "email": "colleague@example.com", "active": True, "role_ids": [2]},
    {"id": 5, "login": "nicole@example.com", "firstname": "Nicole", "lastname": "Braun",
     "email": "nicole@example.com", "active": True, "role_ids": [3], "organization_id": 1},
]
TICKETS = []
def ticket(i, title, state, prio, owner, **extra):
    t = {"id": i, "number": str(14000 + i), "title": title, "group_id": 1, "state_id": state, "priority_id": prio,
         "owner_id": owner, "customer_id": 5, "organization_id": 1, "article_count": 2, "created_by_id": 5,
         "updated_by_id": 5, "created_at": ts(hours=-30 - i), "updated_at": ts(minutes=-7 * i)}
    t.update(extra); TICKETS.append(t)
ticket(1, "Printer on the 2nd floor keeps jamming", 2, 2, 3, escalation_at=ts(minutes=-95),
       first_response_escalation_at=ts(minutes=-95), close_escalation_at=ts(hours=20))
ticket(2, "VPN access for new colleague", 1, 3, 3, escalation_at=ts(minutes=35), update_escalation_at=ts(minutes=35))
ticket(3, "Invoice 2026-118 shows the wrong VAT number", 2, 2, 3, escalation_at=ts(hours=9),
       first_response_at=ts(hours=-20), first_response_in_min=42, close_escalation_at=ts(hours=9))
ticket(4, "Laptop battery drains within an hour", 3, 1, 3, pending_time=ts(days=2))
ticket(5, "Cannot log in to the customer portal", 1, 2, 1)
ticket(6, "Request: second monitor", 2, 1, 4)
HTML = ("<div>Hi support,</div><div><br></div><div>The <b>printer</b> on the 2nd floor jams on every "
        "double-sided job. See the list:</div><ul><li>Tray 2</li><li>A4, 80 g</li></ul>"
        "<div>More info: <a href=\"https://example.com/printer\">example.com/printer</a></div>"
        "<blockquote>Sent from my phone</blockquote>")
def articles(tid):
    return [
        {"id": tid * 10 + 1, "ticket_id": tid, "type_id": 1, "sender_id": 2, "from": "Nicole Braun <nicole@example.com>",
         "to": "support@example.com", "subject": "Help", "content_type": "text/html", "body": HTML, "internal": False,
         "type": "email", "sender": "Customer", "created_by_id": 5, "created_at": ts(hours=-30), "updated_at": ts(hours=-30),
         "attachments": [{"id": 77, "filename": "error.txt", "size": "28",
                          "preferences": {"Content-Type": "text/plain", "Mime-Type": "text/plain"}}]},
        {"id": tid * 10 + 2, "ticket_id": tid, "type_id": 10, "sender_id": 1, "from": "Demo Agent", "to": "",
         "subject": "", "content_type": "text/plain", "body": "Called the customer, will check on site tomorrow.",
         "internal": True, "type": "note", "sender": "Agent", "created_by_id": 3, "created_at": ts(hours=-3),
         "updated_at": ts(hours=-3), "attachments": []},
    ]

def search(query):
    result = TICKETS
    m = re.search(r"owner_id:(\d+)", query)
    if m: result = [t for t in result if t["owner_id"] == int(m.group(1))]
    m = re.search(r"state_id:\(([^)]*)\)", query)
    if m:
        ids = {int(x) for x in re.findall(r"\d+", m.group(1))}
        result = [t for t in result if t["state_id"] in ids]
    else:
        m = re.search(r"state_id:(\d+)", query)
        if m: result = [t for t in result if t["state_id"] == int(m.group(1))]
    if "escalation_at:" in query:
        result = [t for t in result if t.get("escalation_at") and t["escalation_at"] < ts()]
    m = re.search(r"number:(\d+)", query)
    if m: result = [t for t in result if t["number"] == m.group(1)]
    if not re.search(r"(owner_id|state_id|escalation_at|number):", query):
        result = [t for t in result if query.lower() in t["title"].lower()]
    return result

class Handler(BaseHTTPRequestHandler):
    def reply(self, body, status=200, raw=None, ctype="application/json"):
        data = raw if raw is not None else json.dumps(body).encode()
        self.send_response(status); self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data))); self.end_headers(); self.wfile.write(data)

    def route(self, method):
        url = urlparse(self.path); path = url.path.replace("/api/v1/", "", 1).strip("/"); q = parse_qs(url.query)
        length = int(self.headers.get("Content-Length") or 0)
        body = json.loads(self.rfile.read(length) or b"{}") if length else {}
        if not (self.headers.get("Authorization") or "").startswith("Token token="):
            return self.reply({"error": "Authentication required"}, 401)
        page = int(q.get("page", ["1"])[0])
        if path == "users/me": return self.reply(USERS[1])
        if path == "ticket_states": return self.reply(STATES)
        if path == "ticket_priorities": return self.reply(PRIORITIES)
        if path == "users": return self.reply(USERS if page == 1 else [])
        if path == "users/search":
            needle = q.get("query", [""])[0].lower()
            return self.reply([u for u in USERS if needle in (u["firstname"] + u["lastname"] + u["email"]).lower()])
        if path == "roles":
            return self.reply([{"id": 1, "name": "Admin", "active": True}, {"id": 2, "name": "Agent", "active": True},
                               {"id": 3, "name": "Customer", "active": True}])
        if path == "groups": return self.reply([{"id": 1, "name": "Users", "active": True}])
        if path == "organizations":
            return self.reply([{"id": 1, "name": "Zammad Foundation"}] if page == 1 else [])
        if path == "time_accounting/types": return self.reply([{"id": 1, "name": "Support", "active": True}])
        if path == "tickets/search":
            found = search(q.get("query", [""])[0])
            return self.reply({"total_count": len(found)} if "only_total_count" in q else found)
        m = re.fullmatch(r"tickets/(\d+)", path)
        if m:
            t = next((t for t in TICKETS if t["id"] == int(m.group(1))), None)
            if not t: return self.reply({"error": "Not found"}, 404)
            if method == "PUT": t.update({k: v for k, v in body.items() if v is not None}); t["updated_at"] = ts()
            return self.reply(t)
        m = re.fullmatch(r"ticket_articles/by_ticket/(\d+)", path)
        if m: return self.reply(articles(int(m.group(1))))
        m = re.fullmatch(r"tickets/(\d+)/time_accountings", path)
        if m:
            return self.reply({"id": 1, "ticket_id": int(m.group(1)), "time_unit": body.get("time_unit", "0"),
                               "created_by_id": 3, "created_at": ts()} if method == "POST" else [])
        if path == "ticket_articles" and method == "POST":
            return self.reply(dict(articles(body.get("ticket_id", 1))[1], body=body.get("body", "")), 201)
        if path == "tickets" and method == "POST":
            ticket(len(TICKETS) + 1, body.get("title", "New"), body.get("state_id", 1), body.get("priority_id", 2),
                   body.get("owner_id") or 1)
            return self.reply(TICKETS[-1], 201)
        if path.startswith("ticket_attachment/"): return self.reply(None, raw=b"E-042 paper jam in duplex unit\n", ctype="text/plain")
        if path in ("mentions", "tags/add"): return self.reply({}, 201)
        return self.reply({"error": f"mock: no route for {method} {path}"}, 404)

    def do_GET(self): self.route("GET")
    def do_POST(self): self.route("POST")
    def do_PUT(self): self.route("PUT")
    def log_message(self, fmt, *args): sys.stderr.write("mock: " + fmt % args + "\n")

if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8089
    print(f"Mock Zammad on http://0.0.0.0:{port} (emulator: http://10.0.2.2:{port})")
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
