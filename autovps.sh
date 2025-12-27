#!/bin/bash
set -euo pipefail

VM_DIR="$HOME/vms"
mkdir -p "$VM_DIR"

# ==============================
# DANH SÁCH HỆ ĐIỀU HÀNH
# ==============================
declare -A OS_LIST=(
["1"]="Ubuntu 22.04|https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
["2"]="Ubuntu 24.04|https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
["3"]="Debian 11|https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.qcow2"
["4"]="Debian 12|https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
["5"]="AlmaLinux 9|https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2"
["6"]="Rocky Linux 9|https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2"
)

select_os() {
echo "===== CHỌN HỆ ĐIỀU HÀNH ====="
for key in "${!OS_LIST[@]}"; do
    echo "$key) $(echo ${OS_LIST[$key]} | cut -d '|' -f1)"
done
read -p "Chọn: " OS_CHOICE
[[ -z "${OS_LIST[$OS_CHOICE]+x}" ]] && echo "❌ Sai lựa chọn!" && sleep 1 && select_os
OS_NAME=$(echo "${OS_LIST[$OS_CHOICE]}" | cut -d '|' -f1)
IMG_URL=$(echo "${OS_LIST[$OS_CHOICE]}" | cut -d '|' -f2)
}

# ==============================
# TẠO VPS
# ==============================
create_vm() {
select_os

read -p "Tên VPS: " VM_NAME
read -p "User (default ubuntu): " USERNAME; USERNAME="${USERNAME:-ubuntu}"
read -s -p "Password (default ubuntu): " PASSWORD; PASSWORD="${PASSWORD:-ubuntu}"; echo
read -p "RAM (MB - ví dụ: 2048): " MEMORY; MEMORY="${MEMORY:-2048}"
read -p "CPU (tối đa nên 8): " CPUS; CPUS="${CPUS:-2}"
read -p "Disk size (VD: 20G): " DISK_SIZE; DISK_SIZE="${DISK_SIZE:-20G}"
read -p "SSH Port (default 2222): " SSH_PORT; SSH_PORT="${SSH_PORT:-2222}"

IMG_FILE="$VM_DIR/$VM_NAME.img"
SEED_FILE="$VM_DIR/$VM_NAME-seed.iso"

echo "[+] Đang tải $OS_NAME..."
wget -q "$IMG_URL" -O "$IMG_FILE"
qemu-img resize "$IMG_FILE" "$DISK_SIZE"

# LƯU CẤU HÌNH ĐỂ CHẠY KHÔNG HỎI LẠI
cat > "$VM_DIR/$VM_NAME.conf" <<EOF
VM_NAME="$VM_NAME"
USERNAME="$USERNAME"
PASSWORD="$PASSWORD"
MEMORY="$MEMORY"
CPUS="$CPUS"
DISK_SIZE="$DISK_SIZE"
SSH_PORT="$SSH_PORT"
EOF

# ==============================
# TẠO AUTO-LOGIN + AUTO DELAY SERVICE
# ==============================
cat > user-data <<EOF
#cloud-config
hostname: $VM_NAME
ssh_pwauth: true
disable_root: false
users:
  - name: $USERNAME
    sudo: ALL=(ALL) NOPASSWD:ALL
    password: $(openssl passwd -6 "$PASSWORD")
    shell: /bin/bash

# AUTO LOGIN TTY S0 (QEMU CONSOLE)
runcmd:
  - mkdir -p /etc/systemd/system/serial-getty@ttyS0.service.d
  - bash -c 'cat <<EOT >/etc/systemd/system/serial-getty@ttyS0.service.d/override.conf
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USERNAME --noclear ttyS0 115200 vt100
EOT'
  - systemctl daemon-reload
  - systemctl restart serial-getty@ttyS0.service

# AUTO DELAY 15 GIÂY RỒI MỚI CHẠY SCRIPT
  - bash -c 'cat <<EOT >/etc/systemd/system/autoremote.service
[Unit]
Description=Delayed Auto Remote Startup
After=network-online.target cloud-init.target multi-user.target systemd-user-sessions.service getty.target

[Service]
User=$USERNAME
Type=simple
ExecStart=/bin/bash -c "sleep 15 && bash <(curl -s https://raw.githubusercontent.com/dinhvinhtainopublic/VNC-Remote/refs/heads/main/auto-remote-web.sh)"
Restart=no

[Install]
WantedBy=multi-user.target
EOT'

  - systemctl enable autoremote.service
EOF

echo "instance-id: iid-$VM_NAME" > meta-data
cloud-localds "$SEED_FILE" user-data meta-data

echo "🎉 VPS tạo thành công!"
sleep 1
}

# ==============================
# CHẠY VPS (KHÔNG HỎI LẠI CẤU HÌNH)
# ==============================
start_vm() {
mapfile -t VM_LIST < <(ls "$VM_DIR" | grep ".conf" | sed 's/.conf//g')
[[ ${#VM_LIST[@]} -eq 0 ]] && echo "❌ Chưa có VPS!" && sleep 1 && return

echo "===== DANH SÁCH VPS ====="
i=1; for vm in "${VM_LIST[@]}"; do echo "$i) $vm"; ((i++)); done
read -p "Chọn VPS: " PICK
VM_NAME="${VM_LIST[$((PICK-1))]}"

source "$VM_DIR/$VM_NAME.conf"

# AUTO NHẢY PORT NẾU TRÙNG
if ss -tulpn 2>/dev/null | grep -q ":$SSH_PORT "; then
    while ss -tulpn 2>/dev/null | grep -q ":$SSH_PORT "; do SSH_PORT=$((SSH_PORT+1)); done
fi

echo "[+] Booting $VM_NAME (RAM $MEMORY | CPU $CPUS | PORT $SSH_PORT)"

qemu-system-x86_64 \
-enable-kvm \
-m "$MEMORY" \
-smp "$CPUS" \
-serial mon:stdio -nographic \
-cpu host \
-drive "file=$VM_DIR/$VM_NAME.img,format=qcow2,if=virtio" \
-drive "file=$VM_DIR/$VM_NAME-seed.iso,format=raw,if=virtio" \
-netdev user,id=n1,hostfwd=tcp::$SSH_PORT-:22 \
-device e1000,netdev=n1 &

sleep 6
echo "🌍 Đang tạo Cloudflare Tunnel..."
url=$(cloudflared tunnel --url http://localhost:6080 2>&1 | grep -o "https://.*trycloudflare.com")
echo "==============================="
echo "➡️  LINK REMOTE:"
echo "👉 $url"
echo "==============================="
read -p "Enter để quay lại menu..."
}

# ==============================
# MENU CHÍNH – KHÔNG BAO GIỜ THOÁT
# ==============================
while true; do
clear
echo "===== MENU VPS QEMU ====="
echo "1) Tạo VPS mới"
echo "2) Chạy VPS (không hỏi lại cấu hình)"
echo "0) Thoát"
read -p "Chọn: " M
case $M in
1) create_vm ;;
2) start_vm ;;
0) exit ;;
*) echo "Sai lựa chọn!" ;;
esac
done
