#!/bin/bash
set -euo pipefail

# ===========================================================
#  QEMU AUTO VPS (AUTO LOGIN + AUTO REMOTE + CHỌN CẤU HÌNH)
#  Khi vào QEMU ➜ TỰ LOGIN + TỰ CHẠY SCRIPT + IN 1 LINK REMOTE
#  Mật khẩu VNC mặc định: 12345678
# ===========================================================

VM_DIR="$HOME/vms"
mkdir -p "$VM_DIR"
clear

echo "=============================================================="
echo "    QEMU VPS MANAGER - AUTO LOGIN / AUTO REMOTE / GUI VNC     "
echo "            VNC default password: 12345678                    "
echo "=============================================================="
echo

# ==========================
# TẠO VM
# ==========================
create_vm() {
    read -p "Tên VM: " VM_NAME

    read -p "User login (default ubuntu): " USERNAME
    USERNAME="${USERNAME:-ubuntu}"

    read -s -p "Mật khẩu user (default ubuntu): " PASSWORD; echo
    PASSWORD="${PASSWORD:-ubuntu}"

    read -p "RAM (MB, ví dụ 1024 / 2048 / 4096): " MEMORY
    MEMORY="${MEMORY:-2048}"

    read -p "Số CPU (default 2): " CPUS
    CPUS="${CPUS:-2}"

    read -p "Dung lượng Disk (10G / 20G / 50G): " DISK_SIZE
    DISK_SIZE="${DISK_SIZE:-20G}"

    read -p "SSH Port (default 2222): " SSH_PORT
    SSH_PORT="${SSH_PORT:-2222}"

    IMG_FILE="$VM_DIR/$VM_NAME.img"
    SEED_FILE="$VM_DIR/$VM_NAME-seed.iso"
    IMG_URL="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"

    echo "[+] Đang tải image..."
    wget -q "$IMG_URL" -O "$IMG_FILE"
    qemu-img resize "$IMG_FILE" "$DISK_SIZE"

# ============= CLOUD-INIT: TỰ LOGIN + TỰ CHẠY SCRIPT ============
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

# AUTO LOGIN QEMU CONSOLE
runcmd:
  - mkdir -p /etc/systemd/system/serial-getty@ttyS0.service.d
  - bash -c 'cat <<EOT >/etc/systemd/system/serial-getty@ttyS0.service.d/override.conf
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USERNAME --noclear %I 115200 vt100
EOT'
  - systemctl daemon-reload
  - systemctl restart serial-getty@ttyS0.service

# SET VNC PASSWORD
  - mkdir -p /home/$USERNAME/.vnc
  - echo "12345678" | vncpasswd -f > /home/$USERNAME/.vnc/passwd
  - chmod 600 /home/$USERNAME/.vnc/passwd
  - chown -R $USERNAME:$USERNAME /home/$USERNAME/.vnc

# AUTO CHẠY SCRIPT REMOTE KHI BOOT
  - sudo -u $USERNAME bash -c 'bash <(curl -s https://raw.githubusercontent.com/dinhvinhtainopublic/VNC-Remote/refs/heads/main/auto-remote-web.sh)'

# AUTO CHẠY MỖI LẦN ĐĂNG NHẬP
write_files:
  - path: /home/$USERNAME/.bash_profile
    permissions: '0755'
    owner: $USERNAME:$USERNAME
    content: |
      bash <(curl -s https://raw.githubusercontent.com/dinhvinhtainopublic/VNC-Remote/refs/heads/main/auto-remote-web.sh)
EOF

cat > meta-data <<EOF
instance-id: iid-$VM_NAME
local-hostname: $VM_NAME
EOF

cloud-localds "$SEED_FILE" user-data meta-data

echo
echo "========== ✔️ VM Tạo xong =========="
echo "Tên      : $VM_NAME"
echo "RAM      : $MEMORY MB"
echo "CPU      : $CPUS"
echo "Disk     : $DISK_SIZE"
echo "SSH      : ssh -p $SSH_PORT $USERNAME@localhost"
echo "VNC PASS : 12345678"
echo "===================================="
echo
}

# ==========================
# CHẠY VM
# ==========================
start_vm() {
    read -p "Tên VM: " VM_NAME
    read -p "SSH Port (default 2222): " SSH_PORT
    SSH_PORT="${SSH_PORT:-2222}"

    read -p "RAM để chạy (MB - để trống lấy cấu hình đã đặt): " RAM_RUN
    RAM_RUN="${RAM_RUN:-2048}"

    read -p "CPU để chạy (để trống để dùng cấu hình cũ): " CPU_RUN
    CPU_RUN="${CPU_RUN:-2}"

    IMG_FILE="$VM_DIR/$VM_NAME.img"
    SEED_FILE="$VM_DIR/$VM_NAME-seed.iso"

    echo "[+] Bắt đầu khởi động VM..."
    qemu-system-x86_64 \
      -enable-kvm \
      -m "$RAM_RUN" \
      -smp "$CPU_RUN" \
      -cpu host \
      -drive "file=$IMG_FILE,format=qcow2,if=virtio" \
      -drive "file=$SEED_FILE,format=raw,if=virtio" \
      -serial mon:stdio \
      -nographic \
      -netdev user,id=n1,hostfwd=tcp::$SSH_PORT-:22 \
      -device e1000,netdev=n1 &

    sleep 6

    echo
    echo "=============================================================="
    echo " ⏳ Cloudflare Tunnel đang tạo link... (chỉ hiện 1 link)"
    echo "=============================================================="

    url=$(cloudflared tunnel --url http://localhost:6080 2>&1 | grep -o "https://.*trycloudflare.com")

    echo
    echo "=========== 🌍 LINK REMOTE CỦA BẠN ==========="
    echo "👉 $url"
    echo "=============================================="
    echo
}

# ==========================
# MENU
# ==========================
echo "1) Tạo VM (có chọn RAM/CPU/Disk)"
echo "2) Chạy VM (AUTO LOGIN + AUTO REMOTE)"
echo "0) Thoát"
read -p "Chọn: " CHOICE

case $CHOICE in
1) create_vm ;;
2) start_vm ;;
0) exit ;;
*) echo "Sai lựa chọn" ;;
esac
