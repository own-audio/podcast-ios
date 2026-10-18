"""Serves UITests/Fixtures/feed for the UI tests, with byte ranges: AVPlayer streams only from a
server that answers `Range` (Python's own http.server doesn't). Usage: python3 serve.py PORT DIR"""
import os, re, sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer


class RangeHandler(SimpleHTTPRequestHandler):
    extensions_map = {**SimpleHTTPRequestHandler.extensions_map, ".m4a": "audio/mp4", ".xml": "application/rss+xml"}
    def log_message(self, *args):
        pass

    def send_head(self):
        path = self.translate_path(self.path)
        match = re.match(r"bytes=(\d*)-(\d*)$", self.headers.get("Range", ""))
        if not match or not os.path.isfile(path):
            return super().send_head()
        size = os.path.getsize(path)
        start = int(match.group(1) or 0)
        end = min(int(match.group(2) or size - 1), size - 1)
        if start >= size:
            self.send_error(416)
            return None
        handle = open(path, "rb")
        handle.seek(start)
        self.send_response(206)
        self.send_header("Content-Type", self.guess_type(path))
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.send_header("Content-Length", str(end - start + 1))
        self.end_headers()
        self.remaining = end - start + 1
        return handle

    def copyfile(self, source, outputfile):
        remaining = getattr(self, "remaining", None)
        if remaining is None:
            return super().copyfile(source, outputfile)
        outputfile.write(source.read(remaining))

    def end_headers(self):
        if not self.headers.get("Range"):
            self.send_header("Accept-Ranges", "bytes")
        super().end_headers()


if __name__ == "__main__":
    port, directory = int(sys.argv[1]), sys.argv[2]
    os.chdir(directory)
    ThreadingHTTPServer(("127.0.0.1", port), RangeHandler).serve_forever()
