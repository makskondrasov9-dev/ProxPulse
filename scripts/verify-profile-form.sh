#!/bin/zsh
# Native button regression against an isolated HTTPS fixture; Python is a test-only dependency.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/swift-environment.sh
swift build "${package_flags[@]}"
binary_dir="$(swift build --show-bin-path)"
fixture="$PWD/.build/profile-form-tls"
mkdir -p "$fixture" Preview
rm -f "$fixture/port"
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$fixture/key.pem" -out "$fixture/cert.pem" -days 1 -subj /CN=localhost > "$fixture/certificate.log" 2>&1
python3 - "$fixture" <<'PY' &
import http.server, ssl, pathlib, json, sys
root = pathlib.Path(sys.argv[1])
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        authorization = self.headers.get('Authorization', '')
        fixtures = {
            'PVEAPIToken=fixture@pve!proxpulse=saved-token-not-a-uuid': 'saved',
            'PVEAPIToken=root@pam!proxpulse=new-token-not-a-uuid': 'new',
            'PVEAPIToken=fixture@pve!proxpulse=replacement-token': 'replacement',
        }
        # Record only fixture classification and path, never credentials.
        with (root/'requests.jsonl').open('a') as output:
            output.write(json.dumps({'kind': fixtures.get(authorization, 'unexpected'), 'path': self.path})+'\n')
        payload = b'{"data":null}'
        self.send_response(401)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)
    def log_message(self, *args): pass
server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(root/'cert.pem', root/'key.pem')
server.socket = context.wrap_socket(server.socket, server_side=True)
(root/'requests.jsonl').write_text('')
(root/'port').write_text(str(server.server_port))
server.serve_forever()
PY
fixture_pid=$!
trap 'kill "$fixture_pid" 2>/dev/null || true' EXIT
for attempt in {1..50}; do
    [[ -s "$fixture/port" ]] && break
    kill -0 "$fixture_pid"
    sleep 0.1
done
[[ -s "$fixture/port" ]]
"$binary_dir/ProxPulse" --verify-profile-form
