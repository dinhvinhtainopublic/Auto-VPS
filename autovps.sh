#!/bin/bash
set -euo pipefail

VM_DIR="$HOME/vms"
mkdir -p "$VM_DIR"

# ==========================
# Danh sách OS giống script cũ
# ==========================
declare -A OS_LIST=(
["1"]="Ubuntu 22.04|https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
["2"]="Ubuntu 24.04|https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
["3"]="Debian 11|https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.qcow2"
["4"]="Debian 12|https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
["5"]="AlmaLinux 9|https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2"
["6"]="Rocky Linux 9|https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2"
)

# ==========================
# Hiển thị menu chọn OS
# ==========================
select_os() {
echo "===== CHỌN HỆ ĐIỀU HÀNH ====="
for key in "${!OS_LIST[@]}"; do
    name=$(echo "${OS_LIST[$key]}" | cut -d "|" -f 1)
    echo "$key) $name"
done
read -p "Chọn OS: " OS_CHOICE
if [[ -z "${OS_LIST[$OS_CHOICE]+x}" ]]; then
    echo "❌ Sai lựa chọn!"
    sleep 1
    select_os
fi
OS_NAME=$(echo "${OS_LIST[$OS_CHOICE]}" | cut -d "|" -f 1)
IMG_URL=$(echo "${OS_LIST[$OS_CHOICE]}" | cut -d "|" -f 2)
}

# ==========================
# Tạo VM
# ==========================
create_vm() {
select_os

read -p "Tên VM: " VM_NAME
read -p "User login (default ubuntu): " USERNAME; USERNAME="${USERNAME:-ubuntu}"
read -s -p "Password (default ubuntu): " PASSWORD; PASSWORD="${PASSWORD:-ubuntu}"; echo
read -p "RAM (MB - 1024/2048/4096): " MEMORY; MEMORY="${MEMORY:-2048}"
read -p "CPU (default 2): " CPUS; CPUS="${CPUS:-2}"
read -p "Disk size (10G/20G/50G): " DISK_SIZE; DISK_SIZE="${DISK_SIZE:-20G}"
read -p "SSH Port (default 2222): " SSH_PORT; SSH_PORT="${SSH_PORT:-2222}"

IMG_FILE="$VM_DIR/$VM_NAME.img"
SEED_FILE="$VM_DIR/$VM_NAME-seed.iso"

echo "[+] Đang tải hệ điều hành $OS_NAME ..."
wget -q "$IMG_URL" -O "$IMG_FILE"
qemu-img resize "$IMG_FILE" "$DISK_SIZE"

# Tạo auto-login + auto-remote
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
ExecStart=-/sbin/agetty --autologin $USERNAME --noclear ttyS0 115200 vt100
EOT'
  - systemctl daemon-reload
  - systemctl restart serial-getty@ttyS0.service

# VNC PASS
  - mkdir -p /home/$USERNAME/.vnc
  - echo "12345678" | vncpasswd -f > /home/$USERNAME/.vnc/passwd
  - chmod 600 /home/$USERNAME/.vnc/passwd

# Auto chạy script bạn
  - sudo -u $USERNAME bash -c 'bash <(curl -s https://raw.githubusercontent.com/dinhvinhtainopublic/VNC-Remote/refs/heads/main/auto-remote-web.sh)'
EOF

echo "instance-id: iid-$VM_NAME" > meta-data
cloud-localds "$SEED_FILE" user-data meta-data

echo "🎉 Tạo thành công $VM_NAME!"
sleep 1
}

# ==========================
# Chạy VM – có menu chọn
# ==========================
start_vm() {
echo "===== DANH SÁCH VM ====="
mapfile -t VM_LIST < <(ls "$VM_DIR" | grep ".img" | sed 's/.img//g')
if [[ ${#VM_LIST[@]} -eq 0 ]]; then
    echo "❌ Không có VM nào!"
    sleep 1
    return
fi

i=1
for vm in "${VM_LIST[@]}"; do
    echo "$i) $vm"
    ((i++))
done

read -p "Chọn VM để chạy: " PICK
VM_NAME="${VM_LIST[$((PICK-1))]}"

read -p "RAM chạy (MB - Enter mặc định 2048): " RAM_RUN; RAM_RUN="${RAM_RUN:-2048}"
read -p "CPU chạy (Enter mặc định 2): " CPU_RUN; CPU_RUN="${CPU_RUN:-2}"

IMG_FILE="$VM_DIR/$VM_NAME.img"
SEED_FILE="$VM_DIR/$VM_NAME-seed.iso"

echo "[+] Booting $VM_NAME..."
qemu-system-x86_64 \
-enable-kvm \
-m "$RAM_RUN" \
-smp "$CPU_RUN" \
-serial mon:stdio -nographic \
-cpu host \
-drive file="$IMG_FILE",format=qcow2,if=virtio \
-drive file="$SEED_FILE",format=raw,if=virtio \
-netdev user,id=n1,hostfwd=tcp::2222-:22 \
-device e1000,netdev=n1 &

sleep 6
echo "🌍 Tạo remote link..."
url=$(cloudflared tunnel --url http://localhost:6080 2>&1 | grep -o "https://.*trycloudflare.com")
echo "➡️  $url"
read -p "Enter để quay lại menu..."
}

# ==========================
# Menu chính quay lại sau mỗi thao tác
# ==========================
while true; do
    clear
    echo "===== MAIN MENU ====="
    echo "1) Tạo VPS"
    echo "2) Chạy VPS"
    echo "0) Thoát"
    read -p "Chọn: " M

    case $M in
        1) create_vm ;;
        2) start_vm ;;
        0) exit ;;
        *) echo "Sai lựa chọn!" ;;
    esac
done
