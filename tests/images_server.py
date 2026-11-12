#!/usr/bin/env python3
"""Exercise image uploads and signed downloads against a disposable local S3 server."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, unquote, urlsplit
from xml.sax.saxutils import escape

class S3(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *_args):
        pass

    def reply(self, code, body=b"", content_type="application/xml"):
        if isinstance(body, str):
            body = body.encode()
        self.send_response(code)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Content-Type", content_type)
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        url = urlsplit(self.path)
        query = parse_qs(url.query)
        if "prefix" in query:
            prefix = query["prefix"][0]
            self.server.listings += 1
            if prefix.startswith("denied/"):
                self.reply(403, "<Error><Code>AccessDenied</Code><Message>list denied</Message></Error>")
                return
            contents = "".join(f"<Contents><Key>{escape(key)}</Key><Size>{len(data)}</Size></Contents>"
                               for key, (data, _) in self.server.objects.items() if key.startswith(prefix))
            self.reply(200, f"<ListBucketResult><IsTruncated>false</IsTruncated>{contents}</ListBucketResult>")
            return
        key = unquote(url.path).split("/", 2)[-1]
        if key not in self.server.objects:
            self.reply(404)
            return
        if "X-Amz-Signature" in query:
            assert len(query["X-Amz-Signature"][0]) == 64
            assert query["X-Amz-Expires"] == ["90"]
        else:
            assert self.headers["Authorization"].startswith("AWS4-HMAC-SHA256 ")
            self.server.comparisons += 1
        data, content_type = self.server.objects[key]
        self.reply(200, data, content_type)

    def do_PUT(self):
        key = unquote(urlsplit(self.path).path).split("/", 2)[-1]
        data = self.rfile.read(int(self.headers["Content-Length"]))
        self.server.puts += 1
        self.server.objects[key] = (data, self.headers["Content-Type"])
        self.reply(200)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--library", required=True, type=Path)
    parser.add_argument("--tclsh", default="tclsh9.1")
    args = parser.parse_args()
    env = dict(os.environ, AWS_EC2_METADATA_DISABLED="true", AWS_REQUEST_CHECKSUM_CALCULATION="when_required")
    with ThreadingHTTPServer(("127.0.0.1", 0), S3) as server:
        server.objects, server.puts, server.listings, server.comparisons = {}, 0, 0, 0
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with tempfile.TemporaryDirectory(prefix="static-images-") as directory:
                result = subprocess.run([args.tclsh, str(Path(__file__).with_name("images-http.tcl")),
                                         str(args.library.resolve()), f"http://127.0.0.1:{server.server_port}",
                                         directory], env=env, timeout=60)
            if result.returncode:
                return result.returncode
            assert server.puts == 5, f"expected four paths plus one changed image, got {server.puts} PUTs"
            assert server.listings == 13
            assert server.comparisons == 8
            assert sorted(server.objects) == ["test/images/café & image.svg", "test/images/copy.png", "test/images/diagram.svg", "test/images/pixel.png"]
            assert sorted(type_ for _, type_ in server.objects.values()) == ["image/png", "image/png", "image/svg+xml", "image/svg+xml"]
            print("S3 HTTP checks passed: binary uploads, MIME types, path keys, change detection, signed downloads and failures")
            return 0
        finally:
            server.shutdown()
            thread.join()

if __name__ == "__main__":
    raise SystemExit(main())
