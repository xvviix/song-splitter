"""
XVVIIX - local GPU/CPU engine.

Runs Demucs on the user's own machine and exposes a tiny HTTP API that the
website (hosted on GitHub Pages) can call. Audio never leaves the machine.

Started automatically by install-xvviix.bat / install-xvviix.sh.
"""

import json
import os
import re
import shutil
import subprocess
import sys
import threading
import uuid
from email.parser import BytesParser
from email.policy import default
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parent
UPLOADS = ROOT / "uploads"
OUTPUTS = ROOT / "outputs"
UPLOADS.mkdir(exist_ok=True)
OUTPUTS.mkdir(exist_ok=True)

HOST = os.environ.get("XVVIIX_HOST", "127.0.0.1")
PORT = int(os.environ.get("XVVIIX_PORT", "8765"))
MAX_UPLOAD = 500 * 1024 * 1024
ALLOWED_EXT = {".wav", ".mp3", ".flac", ".m4a", ".aac", ".ogg", ".aiff", ".aif"}
STEM_NAMES = {"vocals", "drums", "bass", "other"}
SAFE = re.compile(r"^[\w.\-]+$")
PROGRESS_RE = re.compile(r"(\d{1,3})%")

jobs = {}


def gpu_info():
    try:
        import torch

        if torch.cuda.is_available():
            return {"device": "cuda", "name": torch.cuda.get_device_name(0)}
    except Exception:
        pass
    return {"device": "cpu", "name": "CPU"}


DEVICE = gpu_info()


class Handler(BaseHTTPRequestHandler):
    server_version = "XVVIIX/2.0"

    def log_message(self, fmt, *args):
        # keep the console readable for non-technical users
        if "/api/health" not in (args[0] if args else ""):
            sys.stdout.write("  - %s\n" % (fmt % args))

    def _cors(self):
        origin = self.headers.get("Origin")
        if origin:
            self.send_header("Access-Control-Allow-Origin", origin)
            self.send_header("Vary", "Origin")
        else:
            self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Range")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, HEAD, OPTIONS")
        self.send_header("Access-Control-Expose-Headers", "Content-Length, Content-Range, Accept-Ranges")
        self.send_header("Access-Control-Max-Age", "86400")

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        self._cors()
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def send_json(self, data, code=200):
        raw = json.dumps(data).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    # ---------------- POST ----------------
    def do_POST(self):
        if self.path != "/api/split":
            self.send_json({"error": "Not found"}, 404)
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length <= 0:
                raise ValueError("Empty request")
            if length > MAX_UPLOAD:
                self.send_json({"error": "File larger than 500 MB"}, 413)
                return
            ctype = self.headers.get("Content-Type", "")
            if "multipart/form-data" not in ctype:
                raise ValueError("Expected multipart/form-data")

            body = self.rfile.read(length)
            msg = BytesParser(policy=default).parsebytes(
                f"Content-Type: {ctype}\r\nMIME-Version: 1.0\r\n\r\n".encode() + body
            )

            filename = filedata = None
            fields = {}
            for part in msg.iter_parts():
                name = part.get_param("name", header="content-disposition")
                if name == "file":
                    filename = part.get_filename()
                    filedata = part.get_payload(decode=True)
                elif name:
                    fields[name] = part.get_content()

            if not filename or not filedata:
                raise ValueError("No audio file received")
            ext = Path(filename).suffix.lower() or ".wav"
            if ext not in ALLOWED_EXT:
                raise ValueError(f'Unsupported file type "{ext}"')

            try:
                stems = json.loads(fields.get("stems", "[]"))
            except json.JSONDecodeError:
                stems = []
            stems = [s for s in stems if s in STEM_NAMES] or list(STEM_NAMES)

            job = str(uuid.uuid4())
            src = UPLOADS / (job + ext)
            src.write_bytes(filedata)
            jobs[job] = {"status": "queued", "progress": 0, "name": filename}
            threading.Thread(target=run_split, args=(job, src, stems), daemon=True).start()
            self.send_json({"job_id": job})
        except Exception as exc:
            self.send_json({"error": str(exc)}, 400)

    # ---------------- GET ----------------
    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        if self.path == "/api/health":
            self.send_json({
                "app": "XVVIIX",
                "version": "2.0",
                "engine": "demucs",
                "device": DEVICE["device"],
                "device_name": DEVICE["name"],
                "ok": True,
            })
            return

        if self.path.startswith("/api/status/"):
            job = self.path.rsplit("/", 1)[-1]
            self.send_json(jobs.get(job, {"error": "Unknown job"}))
            return

        if self.path.startswith("/api/download/"):
            self._download()
            return

        self.send_json({"error": "Not found"}, 404)

    def _download(self):
        path, _, query = self.path.partition("?")
        inline = "inline=1" in query
        parts = path.split("/")
        if len(parts) != 7:
            self.send_json({"error": "Invalid path"}, 400)
            return
        _, _, _, job, model, song, filename = [unquote(p) for p in parts]
        for c in (job, model, song, filename):
            if not SAFE.match(c) or ".." in c:
                self.send_json({"error": "Invalid path"}, 400)
                return

        root = OUTPUTS.resolve()
        target = (OUTPUTS / job / model / song / filename).resolve()
        try:
            target.relative_to(root)
        except ValueError:
            self.send_json({"error": "Invalid path"}, 400)
            return
        if not target.is_file():
            self.send_json({"error": "Not found"}, 404)
            return

        size = target.stat().st_size
        start, end, status = 0, size - 1, 200
        rng = self.headers.get("Range", "")
        m = re.match(r"bytes=(\d*)-(\d*)$", rng.strip()) if rng else None
        if m and size:
            s, e = m.group(1), m.group(2)
            if s:
                start = int(s)
                if e:
                    end = min(int(e), size - 1)
            elif e:
                start = max(0, size - int(e))
            if start > end or start >= size:
                self.send_response(416)
                self.send_header("Content-Range", f"bytes */{size}")
                self.end_headers()
                return
            status = 206

        length = end - start + 1
        self.send_response(status)
        self.send_header("Content-Type", "audio/wav")
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Disposition",
                         f'{"inline" if inline else "attachment"}; filename="{filename}"')
        self.send_header("Content-Length", str(length))
        if status == 206:
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.end_headers()
        if self.command == "HEAD":
            return
        with target.open("rb") as f:
            f.seek(start)
            left = length
            while left > 0:
                chunk = f.read(min(65536, left))
                if not chunk:
                    break
                self.wfile.write(chunk)
                left -= len(chunk)


def run_split(job, src, stems):
    out = OUTPUTS / job
    out.mkdir(exist_ok=True)
    jobs[job].update(status="processing", progress=5)
    model = "htdemucs"
    try:
        cmd = [sys.executable, "-m", "demucs", "-n", model, "--out", str(out), str(src)]
        if DEVICE["device"] == "cuda":
            cmd += ["-d", "cuda"]
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                text=True, bufsize=1)
        for line in proc.stdout:
            hit = PROGRESS_RE.search(line)
            if hit:
                jobs[job]["progress"] = max(5, min(95, int(hit.group(1))))
        proc.wait()
        if proc.returncode != 0:
            raise RuntimeError("Demucs could not process this file.")

        folder = out / model / src.stem
        found = {p.stem: p for p in folder.glob("*.wav") if p.is_file()}
        chosen = {k: v for k, v in found.items() if k in stems} or found
        files = {k: f"/api/download/{job}/{model}/{src.stem}/{v.name}" for k, v in chosen.items()}
        jobs[job].update(status="complete", progress=100, files=files)
    except Exception as exc:
        jobs[job].update(status="error", error=str(exc))
    finally:
        try:
            src.unlink(missing_ok=True)
        except Exception:
            pass


def main():
    line = "=" * 58
    print(line)
    print("   XVVIIX - Local Engine")
    print(line)
    print(f"   Device  : {DEVICE['name']}")
    print(f"   Address : http://{HOST}:{PORT}")
    print(line)
    print()
    print("   READY - go back to the website, it connects automatically.")
    print("   Keep this window open. Press Ctrl+C to stop.")
    print()
    try:
        ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
    except KeyboardInterrupt:
        print("\n   Engine stopped.")


if __name__ == "__main__":
    main()
