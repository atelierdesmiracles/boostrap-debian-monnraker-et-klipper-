#!/usr/bin/env bash
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Pin upstream source revisions for reproducible builds.
KLIPPER_REF="${KLIPPER_REF:-master}"
MOONRAKER_REF="${MOONRAKER_REF:-master}"
# Release builds should pass immutable commit SHAs instead of moving branch names.
MAINSAIL_VERSION="${MAINSAIL_VERSION:-v2.19.0}"
MAINSAIL_RELEASE_URL="https://github.com/mainsail-crew/mainsail/releases/download/${MAINSAIL_VERSION}/mainsail.zip"

apt-get update
apt-get install -y --no-install-recommends \
  systemd systemd-sysv dbus ca-certificates curl git wget unzip nginx-light \
  python3 python3-venv python3-dev python3-pip \
  build-essential gcc g++ make cmake pkg-config \
  libffi-dev libjpeg-dev zlib1g-dev libusb-1.0-0-dev \
  libopenjp2-7 libtiff6 libatlas-base-dev \
  avrdude dfu-util stm32flash \
  util-linux usbutils udev sudo locales tzdata xz-utils

if [[ -f /etc/locale.gen ]]; then
  sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen || true
  locale-gen en_US.UTF-8 || true
fi

getent group klipper >/dev/null || groupadd --system klipper
id -u klipper >/dev/null 2>&1 || useradd --system --create-home --home-dir /home/klipper --shell /usr/sbin/nologin --gid klipper klipper
for group in dialout tty; do
  getent group "$group" >/dev/null || groupadd --system "$group"
  usermod -aG "$group" klipper
done

install -d -o klipper -g klipper \
  /home/klipper/printer_data/config \
  /home/klipper/printer_data/logs \
  /home/klipper/printer_data/gcodes \
  /home/klipper/printer_data/comms
install -d -o root -g root /opt /var/www/mainsail

git clone --depth 1 --branch "$KLIPPER_REF" https://github.com/Klipper3d/klipper.git /opt/klipper
git clone --depth 1 --branch "$MOONRAKER_REF" https://github.com/Arksine/moonraker.git /opt/moonraker

python3 -m venv /opt/klipper-venv
/opt/klipper-venv/bin/pip install --no-cache-dir --upgrade pip wheel
/opt/klipper-venv/bin/pip install --no-cache-dir -r /opt/klipper/scripts/klippy-requirements.txt

python3 -m venv /opt/moonraker-venv
/opt/moonraker-venv/bin/pip install --no-cache-dir --upgrade pip wheel
/opt/moonraker-venv/bin/pip install --no-cache-dir -r /opt/moonraker/scripts/moonraker-requirements.txt
chown -R root:root /opt/klipper /opt/klipper-venv /opt/moonraker /opt/moonraker-venv

cat > /home/klipper/printer_data/config/moonraker.conf <<'EOF'
[server]
host: 127.0.0.1
port: 7125
klippy_uds_address: /home/klipper/printer_data/comms/klippy.sock

[file_manager]
enable_object_processing: True

[authorization]
trusted_clients:
  127.0.0.1
  ::1/128
cors_domains:
  localhost
  *.local
  *.lan
EOF

cat > /home/klipper/printer_data/config/printer.cfg <<'EOF'
# Miracle Klipper starter configuration.
# Hardware-specific values are intentionally left unset.
# Before starting Klipper, configure [mcu] serial and all printer pin sections.
[mcu]
# Run: ls -l /dev/serial/by-id/
# serial: /dev/serial/by-id/REPLACE_WITH_YOUR_DEVICE

[virtual_sdcard]
path: /home/klipper/printer_data/gcodes

[display_status]
[pause_resume]
EOF
chown -R klipper:klipper /home/klipper/printer_data

cat > /etc/systemd/system/klipper.service <<'EOF'
[Unit]
Description=Klipper host firmware service
After=network.target
Wants=network.target

[Service]
Type=simple
User=klipper
Group=klipper
SupplementaryGroups=dialout tty
WorkingDirectory=/home/klipper
Environment=PYTHONUNBUFFERED=1
ExecStart=/opt/klipper-venv/bin/python /opt/klipper/klippy/klippy.py /home/klipper/printer_data/config/printer.cfg -l /home/klipper/printer_data/logs/klippy.log -a /home/klipper/printer_data/comms/klippy.sock
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/moonraker.service <<'EOF'
[Unit]
Description=Moonraker API service
After=network.target klipper.service
Wants=network.target

[Service]
Type=simple
User=klipper
Group=klipper
SupplementaryGroups=dialout tty
WorkingDirectory=/opt/moonraker
Environment=PYTHONUNBUFFERED=1
ExecStart=/opt/moonraker-venv/bin/python /opt/moonraker/moonraker/moonraker.py -c /home/klipper/printer_data/config/moonraker.conf -l /home/klipper/printer_data/logs/moonraker.log
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
curl -fL --retry 3 --retry-delay 2 "$MAINSAIL_RELEASE_URL" -o "$TMP_DIR/mainsail.zip"
unzip -q "$TMP_DIR/mainsail.zip" -d /var/www/mainsail
test -s /var/www/mainsail/index.html || { echo "Mainsail archive did not contain index.html" >&2; exit 1; }
chown -R root:root /var/www/mainsail

cat > /etc/nginx/sites-available/mainsail <<'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    root /var/www/mainsail;
    index index.html;
    # Configure a suitable cap for your workload; do not disable limits by default.
    client_max_body_size 2g;

    location / {
        try_files $uri $uri/ /index.html;
    }

    location /websocket {
        proxy_pass http://127.0.0.1:7125/websocket;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 3600s;
    }

    location ~ ^/(printer|api|access|machine|server)/ {
        proxy_pass http://127.0.0.1:7125;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF

rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/mainsail /etc/nginx/sites-enabled/mainsail
nginx -t
systemctl enable klipper.service moonraker.service nginx.service

apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
echo "Miracle Klipper rootfs setup completed; configure printer.cfg for the target printer."
