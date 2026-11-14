#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Verify curl actually refuses an HTTP redirect before forwarding a POST body."""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from io import StringIO
from pathlib import Path
from threading import Thread
import subprocess
import sys
import tempfile
import unittest


class MockBulb(BaseHTTPRequestHandler):
    seen = []

    def do_GET(self):
        self.handle_request()

    def do_POST(self):
        self.handle_request()

    def handle_request(self):
        data = self.rfile.read(int(self.headers.get('Content-Length', 0)))
        type(self).seen.append((self.path, data))
        if self.path == '/redirect':
            self.send_response(302)
            self.send_header('Location', '/leak')
            self.end_headers()
        elif self.path == '/ok':
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'{"Status": {"Topic": "tasmota_CB0735"}}')
        else:
            self.send_response(500)
            self.end_headers()

    def log_message(self, *args):
        pass


class RedirectPolicy(unittest.TestCase):
    def test_자동_연결_비밀번호를_HTTP_리다이렉트로_재전송하지_않는다(self):
        with ThreadingHTTPServer(('127.0.0.1', 0), MockBulb) as server:
            thread = Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                with tempfile.TemporaryDirectory() as folder:
                    secret = 'test-only-sensitive-body'
                    path = Path(folder) / 'form'
                    path.write_text('cmnd=' + secret)
                    for verb in ('GET', 'POST'):
                        with self.subTest(verb=verb):
                            MockBulb.seen.clear()
                            cmd = [
                                'curl', '--fail', '--silent', '--show-error',
                                '--location', '--max-redirs', '0', '--noproxy', '*',
                                '--proto', '=http', '--connect-timeout', '2',
                                '--max-time', '3', '--max-filesize', '8192',
                                '--output', str(Path(folder) / 'response'),
                            ]
                            if verb == 'POST':
                                cmd.extend(['--header', 'Content-Type: application/x-www-form-urlencoded',
                                            '--data-binary', '@' + str(path)])
                            cmd.append(f'http://127.0.0.1:{server.server_port}/redirect')
                            result = subprocess.run(cmd, capture_output=True, text=True, timeout=6)
                            self.assertEqual(result.returncode, 47, result.stderr)
                            self.assertEqual(len(MockBulb.seen), 1)
                            self.assertEqual(MockBulb.seen[0][0], '/redirect')
                            if verb == 'POST':
                                self.assertIn(secret.encode(), MockBulb.seen[0][1])
                            self.assertFalse(any(url == '/leak' for url, _ in MockBulb.seen))
            finally:
                server.shutdown()
                thread.join(timeout=3)


if __name__ == '__main__':
    # unittest writes to stderr by default; ShellSpec requires it to be empty
    # on success. Preserve the full unittest report on actual failures.
    report = StringIO()
    result = unittest.TextTestRunner(stream=report, verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(RedirectPolicy)
    )
    if not result.wasSuccessful():
        sys.stderr.write(report.getvalue())
        raise SystemExit(1)
    print('PASS: HTTP 리다이렉트 중 추가 요청 및 비밀번호 재전송 차단')
