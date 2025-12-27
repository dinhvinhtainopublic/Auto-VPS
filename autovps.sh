#!/bin/bash

set -e

VM_DIR="$HOME/vms"
mkdir -p "$VM_DIR"

# ==============================
# DANH SÁCH HỆ ĐIỀU HÀNH
# ==============================
declare -A OS_LIST=(
["1"]="Ubuntu 22.04|https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
["2"]="Ubuntu 24.04|https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
["3"]="Debian 12|https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
)

# ==============================
# CHỌN OS
# ==============================
select_os() {
  echo "===== CHỌN HỆ ĐIỀU HÀNH ====="
  for key in "${!OS_LIST[@]}"; do
    echo "$key) $(echo ${OS_LIST[$key]} | cut -d '|' -f1)"
  done
  read -p "Chọn: " CHOICE
  if [[ -z "${OS_LIST[$CHOICE]+x}" ]]; then
      echo "❌ Sai lựa chọn!" 
      return
  fi

  OS_NAME=$(echo "${OS_LIST[$CHOICE]}" | cut -d "|" -f1)
  IMG_URL=$(echo "${OS_LIST[$CHOICE]}" | cut -d "|" -f2)
}

# ==============================
# TẠO VPS
# ==============================
create_vm() {
select_os
echo "===== TẠO VPS ====="
read -p "Tên VPS: " VM_NAME
read -p "Tài khoản (mặc định ubuntu): " USER; USER="${USER:-ubuntu}"
read -s -p "Mật khẩu (mặc định ubuntu): " PASS; PASS="${PASS:-ubuntu}"; echo
read -p "RAM (MB - mặc định 2048): " RAM; RAM="${RAM:-2048}"
read -p "CPU (mặc định 2): " CPU; CPU="${CPU:-2}"
read -p "Ổ đĩa (VD 20G): " DISK; DISK="${DISK:-20G}"
read -p "SSH Port (mặc định 2222): " PORT; PORT="${PORT:-2222}"

IMG_FILE="$VM_DIR/$VM_NAME.img"
SEED_FILE="$VM_DIR/$VM_NAME-seed.iso"

echo "[+] Đang tải $OS_NAME..."
wget -q --show-progress -O "$IMG_FILE" "$IMG_URL" || { echo "❌ Lỗi tải OS"; return; }

qemu-img resize "$IMG_FILE" "$DISK" || echo "⚠️ Resize lỗi nhưng không nghiêm trọng"

# Lưu cấu hình
cat > "$VM_DIR/$VM_NAME.conf" <<EOF
VM_NAME="$VM_NAME"
USER="$USER"
PASS="$PASS"
RAM="$RAM"
CPU="$CPU"
PORT="$PORT"
EOF

# 🔥 CLOUD-INIT – CHỜ LOGIN RỒI MỚI CHẠY
cat > user-data <<EOF
#cloud-config
ssh_pwauth: true
disable_root: false

users:
  - name: $USER
    sudo: ALL=(ALL) NOPASSWD:ALL
    password: $(openssl passwd -6 "$PASS")

write_files:
  - path: /home/$USER/.profile
    owner: $USER:$USER
    permissions: '0755'
    content: |
      if [ ! -f /home/$USER/.firstboot ]; then
        echo "⏳ Chờ OS load xong..."
        sleep 12
        echo "🚀 Đang chạy remote script..."
        bash <(curl -s https://raw.githubusercontent.com/dinhvinhtainopublic/VNC-Remote/refs/heads/main/auto-remote-web.sh)
        touch /home/$USER/.firstboot
      fi

runcmd:
  - mkdir -p /etc/systemd/system/serial-getty@ttyS0.service.d
  - bash -c 'cat <<X >/etc/systemd/system/serial-getty@ttyS0.service.d/override.conf
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USER --noclear ttyS0 115200 vt100
X'
  - systemctl daemon-reload
EOF

echo "instance-id: iid-$VM_NAME" > meta-data
cloud-localds "$SEED_FILE" user-data meta-data || { echo "❌ Tạo seed lỗi"; return; }

echo "🎉 VPS tạo thành công!"
read -p "↩️ Enter để quay lại menu..."
}

# ==============================
# CHẠY VPS
# ==============================
run_vm() {
mapfile -t LIST < <(ls "$VM_DIR" | grep .conf | sed "s/.conf//")

echo "===== VPS SẴN CÓ ====="
i=1; for vm in "${LIST[@]}"; do echo "$i) $vm"; ((i++)); done
read -p "Chọn VPS: " ID

VM="${LIST[$((ID-1))]}"
source "$VM_DIR/$VM.conf"

# Auto nhảy port nếu trùng
if ss -tulpn | grep -q ":$PORT "; then
  while ss -tulpn | grep -q ":$PORT "; do PORT=$((PORT+1)); done
fi

echo "🚀 Booting $VM..."
qemu-system-x86_64 \
  -enable-kvm \
  -m "$RAM" -smp "$CPU" -cpu host \
  -serial mon:stdio -nographic \
  -drive file="$VM_DIR/$VM.img",if=virtio \
  -drive file="$VM_DIR/$VM-seed.iso",if=virtio \
  -netdev user,id=n1,hostfwd=tcp::$PORT-:22 \
  -device e1000,netdev=n1 &

sleep 6
echo "🌍 Lấy Cloudflare link..."
cloudflared tunnel --url http://localhost:6080
read -p "↩️ Enter để quay lại menu..."
}

# ==============================
# MENU
# ==============================
while true; do
clear
echo "===== MENU CHÍNH ====="
echo "1) Tạo VPS"
echo "2) Chạy VPS"
echo "0) Thoát"
read -p "Chọn: " M

case $M in
  1) create_vm ;;
  2) run_vm ;;
  0) exit ;;
  *) echo "Sai lựa chọn!" ;;
esac
done
