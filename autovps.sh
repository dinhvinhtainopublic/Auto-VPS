#!/bin/bash
set -euo pipefail

# =============================
#  QEMU VPS AUTO REMOTE SYSTEM
#  - Auto Login
#  - Auto Run VNC Remote
#  - VNC Password: 12345678
#  - Author: Custom for bạn
# =============================

clear
echo "==============================================================="
echo "      QEMU VPS - AUTO LOGIN + AUTO VNC REMOTE + AUTO RUN       "
echo "                Default VNC Password: 12345678                 "
echo "==============================================================="
echo

VM_DIR="$HOME/vms"
mkdir -p "$VM_DIR"

create_vm() {
    read -p "Tên VM: " VM_NAME
    read -p "User login (default ubuntu): " USERNAME
    USERNAME="${USERNAME:-ubuntu}"
    read -s -p "Mật khẩu user (default ubuntu): " PASSWORD; echo
    PASSWORD="${PASSWORD:-ubuntu}"
    read -p "RAM (MB - default 2048): " MEMORY
    MEMORY="${MEMORY:-2048}"
    read -p "CPU (default 2): " CPUS
    CPUS="${CPUS:-2}"
    read -p "SSH Port (default 2222): " SSH_PORT
    SSH_PORT="${SSH_PORT:-2222}"

    IMG_FILE="$VM_DIR/$VM_NAME.img"
    SEED_FILE="$VM_DIR/$VM_NAME-seed.iso"
    IMG_URL="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"

    echo "[+] Đang tải image Ubuntu..."
    wget -q "$IMG_URL" -O "$IMG_FILE"
    qemu-img resize "$IMG_FILE" 20G

    echo "[+] Tạo file cloud-init tự động..."
    cat > user-data <<EOF
#cloud-config
hostname: $VM_NAME
ssh_pwauth: true
disable_root: false

users:
  - name: $USERNAME
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    password: $(openssl passwd -6 "$PASSWORD")

# Set mật khẩu VNC mặc định
runcmd:
  - mkdir -p /home/$USERNAME/.vnc
  - echo "12345678" | vncpasswd -f > /home/$USERNAME/.vnc/passwd
  - chmod 600 /home/$USERNAME/.vnc/passwd
  - chown -R $USERNAME:$USERNAME /home/$USERNAME/.vnc

# Tự động chạy script của bạn sau khi boot
  - sudo -u $USERNAME bash -c 'bash <(curl -s https://raw.githubusercontent.com/dinhvinhtainopublic/VNC-Remote/refs/heads/main/auto-remote-web.sh)'

# Tự chạy lại mỗi khi login
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

    echo "[✔] Tạo VM hoàn tất!"
    echo "-----------------------------------------"
    echo "VM Name     : $VM_NAME"
    echo "SSH         : ssh -p $SSH_PORT $USERNAME@localhost"
    echo "VNC Password: 12345678"
    echo "-----------------------------------------"
    echo
}

start_vm() {
    read -p "Tên VM muốn chạy: " VM_NAME
    read -p "SSH Port (default 2222): " SSH_PORT
    SSH_PORT="${SSH_PORT:-2222}"

    IMG_FILE="$VM_DIR/$VM_NAME.img"
    SEED_FILE="$VM_DIR/$VM_NAME-seed.iso"

    echo "[+] Đang khởi động VM và auto login..."
    qemu-system-x86_64 \
    -enable-kvm \
    -m 2048 -smp 2 \
    -cpu host \
    -drive "file=$IMG_FILE,format=qcow2,if=virtio" \
    -drive "file=$SEED_FILE,format=raw,if=virtio" \
    -nographic -serial mon:stdio \
    -netdev user,id=n1,hostfwd=tcp::$SSH_PORT-:22 \
    -device e1000,netdev=n1

    echo "[✔] Đã chạy!"
}

echo "1) Tạo VM mới (Auto cấu hình đầy đủ)"
echo "2) Chạy VM (Auto login + chạy script + VNC)"
echo "0) Thoát"
read -p "Chọn: " CHOICE

case $CHOICE in
1) create_vm ;;
2) start_vm ;;
0) exit ;;
*) echo "Sai lựa chọn" ;;
esac
