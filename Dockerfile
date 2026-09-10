FROM ubuntu:22.04

USER root

RUN apt-get update && \
    apt-get install -y curl bash python3 ca-certificates sudo && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN cat <<'EOF' > /app/entrypoint.sh
#!/bin/bash
set -e

PORT="${PORT:-8080}"

echo "[*] کاربر فعلی: $(whoami) (UID: $(id -u))"

echo "[*] در حال نصب sshx ..."
curl -sSf https://sshx.io/get | sh

echo "[*] در حال اجرای sshx ..."
sshx > /tmp/sshx.log 2>&1 &
SSHX_PID=$!

echo "[*] منتظر دریافت لینک sshx ..."
LINK=""
for i in $(seq 1 30); do
  LINK=$(grep -oE 'https://sshx\.io/[A-Za-z0-9/#_-]+' /tmp/sshx.log | head -n1 || true)
  if [ -n "$LINK" ]; then
    break
  fi
  sleep 1
done

if [ -z "$LINK" ]; then
  echo "[!] لینک sshx پیدا نشد. خروجی لاگ:"
  cat /tmp/sshx.log
  exit 1
fi

echo "[+] sshx با موفقیت بالا اومد"
echo "[+] آدرس: $LINK"
echo "$LINK" > /tmp/sshx_link.txt

echo "[*] راه‌اندازی سرور ریدایرکت روی پورت $PORT ..."
python3 - <<'PYEOF'
import http.server
import socketserver
import os

with open('/tmp/sshx_link.txt') as f:
    link = f.read().strip()

port = int(os.environ.get('PORT', 8080))

class RedirectHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(302)
        self.send_header('Location', link)
        self.end_headers()
    def log_message(self, format, *args):
        pass

with socketserver.TCPServer(("0.0.0.0", port), RedirectHandler) as httpd:
    print(f"[+] هر کسی به پورت {port} وصل بشه، به {link} فوروارد میشه")
    httpd.serve_forever()
PYEOF

wait $SSHX_PID
EOF

RUN chmod +x /app/entrypoint.sh

USER 0

ENTRYPOINT ["/app/entrypoint.sh"]
