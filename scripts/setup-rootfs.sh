#!/usr/bin/env bash
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates curl git wget unzip nginx-light sudo \
  python3 python3-venv python3-dev python3-pip \
  build-essential gcc g++ make cmake pkg-config \
  libffi-dev libjpeg-dev zlib1g-dev libusb-1.0-0-dev \
  libopenjp2-7 libtiff6 libatlas-base-dev \
  avrdude dfu-util stm32flash \
  util-linux usbutils udev \
  locales tzdata xz-utils

# Ensure a predictable UTF-8 locale.
sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen || true
locale-gen en_US.UTF-8 || true

# Dedicated service identities; do not run the applications as root.
getent group klipper >/dev/null || groupadd --system klipper
id -u klipper >/dev/null 2>&1 || useradd --system --create-home --home-dir /home/klipper --shell /usr/sbin/nologin --gid klipper klipper
getent group dialout >/dev/null || groupadd --system dialout
usermod -aG dialout klipper
getent group tty >/dev/null || groupadd --system tty
usermod -aG tty klipper

install -d -o klipper -g klipper /home/klipper/printer_data/config /home/klipper/printer_data/logs /home/klipper/printer_data/gcodes
install -d -o root -g root /opt
install -d -o root -g root /var/www/mainsail

# Klipper source and isolated Python environment.
if [[ ! -d /opt/klipper/.git ]]; then
  git clone --depth 1 https://github.com/Klipper3d/klipper.git /opt/klipper
else
  git -C /opt/klipper fetch --depth 1 origin
  git -C /opt/klipper reset --hard FETCH_HEAD
fi
python3 -m venv /opt/klipper-venv
/opt/klipper-venv/bin/pip install --upgrade pip wheel
/opt/klipper-venv/bin/pip install -r /opt/klipper/scripts/klippy-requirements.txt
chown -R root:root /opt/klipper /opt/klipper-venv

# Moonraker source and isolated Python environment.
if [[ ! -d /opt/moonraker/.git ]]; then
  git clone --depth 1 https://github.com/Arksine/moonraker.git /opt/moonraker
else
  git -C /opt/moonraker fetch --depth 1 origin
  git -C /opt/moonraker reset --hard FETCH_HEAD
fi
python3 -m venv /opt/moonraker-venv
/opt/moonraker-venv/bin/pip install --upgrade pip wheel
/opt/moonraker-venv/bin/pip install -r /opt/moonraker/scripts/moonraker-requirements.txt
chown -R root:root /opt/moonraker /opt/moonraker-venv

# Default Moonraker configuration. Users can extend it for their printer.
if [[ ! -f /home/klipper/printer_data/config/moonraker.conf ]]; then
  cat > /home/klipper/printer_data/config/moonraker.conf <<'EOF'
[server]
host: 0.0.0.0
port: 7125
klippy_uds_address: /home/klipper/printer_data/comms/klippy.sock

[file_manager]
enable_object_processing: True

[authorization]
trusted_clients:
  127.0.0.0/8
  192.168.0.0/16
  10.0.0.0/8
  172.16.0.0/12
cors_domains:
  *.local
  *.lan
EOF
fi

# Minimal printer config: deliberately requires hardware-specific serial/MCU settings.
if [[ ! -f /home/klipper/printer_data/config/printer.cfg ]]; then
  cat > /home/klipper/printer_data/config/printer.cfg <<'EOF'
# Miracle Klipper starter configuration.
# Configure the MCU serial path and all printer-specific pins before use.
[mcu]
# Run: ls -l /dev/serial/by-id/
# serial: /dev/serial/by-id/REPLACE_WITH_YOUR_DEVICE

[virtual_sdcard]
path: /home/klipper/printer_data/gcodes

[display_status]

[pause_resume]
EOF
fi

install -d -o klipper -g klipper /home/klipper/printer_data/comms
chown -R klipper:klipper /home/klipper/printer_data

# systemd services.
cat > /etc/systemd/system/klipper.service <<'EOF'
[Unit]
Description=Klipper 3D printer host firmware
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
Description=Moonraker API server for Klipper
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

# Mainsail static frontend only; Fluidd is intentionally not installed.
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
curl -fL --retry 3 https://github.com/mainsail-crew/mainsail/releases/latest/download/mainsail.zip -o "$TMP_DIR/mainsail.zip"
unzip -q "$TMP_DIR/mainsail.zip" -d /var/www/mainsail
chown -R root:root /var/www/mainsail

cat > /etc/nginx/sites-available/mainsail <<'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    root /var/www/mainsail;
    index index.html;

    client_max_body_size 0;

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

# Make services available on first boot. systemd may not be running inside a build chroot.
if command -v systemctl >/dev/null 2>&1; then
  systemctl enable klipper.service moonraker.service nginx.service || true
fi

# Rootfs housekeeping.
apt-get clean
rm -rf /var/lib/apt/lists/*
rm -rf /tmp/* /var/tmp/*
echo "Miracle Klipper setup completed. Configure printer.cfg before connecting hardware."
