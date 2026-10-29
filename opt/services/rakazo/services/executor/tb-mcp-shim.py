"""Forward MCP requests to the Thunderbird MCP add-on with its current token.

The add-on listens on 127.0.0.1 and wants a Bearer token that changes each time
Thunderbird starts; Executor can import an MCP server only when it needs no
sign-in. This listens on another loopback port and adds the token, read afresh
from the add-on's connection file for every request.

Usage: tb-mcp-shim ADDRESS PORT
"""
import http.server, json, sys, urllib.request, urllib.error

LISTEN = (sys.argv[1], int(sys.argv[2]))
CONN = "/tmp/thunderbird-mcp/connection.json"

class Shim(http.server.BaseHTTPRequestHandler):
    # Keep-alive: Executor's client reuses its connection between requests, and
    # an HTTP/1.0 server closing it after each response makes that a race.
    protocol_version = "HTTP/1.1"

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("content-length") or 0))
        try:
            c = json.load(open(CONN))
        except (OSError, ValueError):
            return self.send_error(503, "Thunderbird is not running")
        req = urllib.request.Request(
            f"http://127.0.0.1:{c['port']}/", data=body, method="POST",
            headers={"Authorization": f"Bearer {c['token']}",
                     "Content-Type": self.headers.get("content-type", "application/json"),
                     "Accept": self.headers.get("accept", "application/json")})
        try:
            r = urllib.request.urlopen(req, timeout=300)
            status, ctype, data = r.status, r.headers.get("content-type", ""), r.read()
        except urllib.error.HTTPError as e:
            status, ctype, data = e.code, e.headers.get("content-type", ""), e.read()
        except OSError:
            return self.send_error(502, "Thunderbird MCP did not answer")
        self.send_response(status)
        if ctype:
            self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):  # no server-sent event stream
        self.send_error(405)

    def log_message(self, fmt, *args):
        sys.stderr.write("%s %s\n" % (self.address_string(), fmt % args))

http.server.ThreadingHTTPServer(LISTEN, Shim).serve_forever()
