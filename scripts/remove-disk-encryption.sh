#!/usr/bin/env bash
# Remove the LUKS2 disk encryption from the root partition, online (the system keeps running),
# then point the boot loader at the plain btrfs so no disk password is asked at boot.
#
# Flow: checks -> header backup -> cryptsetup reencrypt --decrypt (moves data to the start of the partition)
#       -> verify the partition now holds the btrfs -> drop cryptdevice= from the kernel command line -> limine-update.
# The boot config is only touched after decryption has finished and been verified.
set -euo pipefail

die() { printf '\033[91m%s\033[0m\n' "$*" >&2; exit 1; }
say() { printf '\033[96m==> %s\033[0m\n' "$*"; }

[[ $EUID -eq 0 ]] || exec sudo bash "$0" "$@"

# --- what the running system booted with ------------------------------------------------------
cd_arg=$(grep -oE 'cryptdevice=[^ ]+' /proc/cmdline) || die "No cryptdevice= in /proc/cmdline: the root is not unlocked by the encrypt hook. Nothing to do."
spec=${cd_arg#cryptdevice=}            # UUID=<luks uuid>:<name>
dev_spec=${spec%%:*}
name=${spec#*:}; name=${name%%:*}
[[ $dev_spec == UUID=* ]] || die "Unexpected cryptdevice= form: $cd_arg"
luks_uuid=${dev_spec#UUID=}
dev=$(blkid -U "$luks_uuid") || die "No partition with UUID $luks_uuid"
mapper=/dev/mapper/$name
[[ -b $mapper ]] || die "$mapper is not active"
cryptsetup isLuks --type luks2 "$dev" || die "$dev is not LUKS2 (online decryption needs LUKS2)"
fs_type=$(blkid -s TYPE -o value "$mapper")
fs_uuid=$(blkid -s UUID -o value "$mapper")
[[ -n $fs_uuid ]] || die "Cannot read the filesystem UUID inside $mapper"

# the exported header must live on another partition (never on the device being decrypted)
boot_src=$(findmnt -no SOURCE /boot) || die "/boot is not mounted"
[[ $boot_src != "$dev" && $boot_src != "$mapper" ]] || die "/boot sits on the encrypted device"
header=/boot/luks-header-$name.img
backup=/boot/luks-header-backup-$name-$(date +%Y%m%d-%H%M%S).img
[[ ! -e $header ]] || die "$header already exists (an earlier run?). Resume with: cryptsetup reencrypt --resume-only --header $header $dev"

cat <<EOF

  Encrypted partition : $dev  (LUKS UUID $luks_uuid)
  Unlocked as         : $mapper  ($fs_type, UUID $fs_uuid)
  Header exported to  : $header
  Header backup       : $backup
  Used space          : $(df -h --output=used / | tail -1 | tr -d ' ')  (the whole partition is rewritten: $(lsblk -dno SIZE "$dev" | tr -d ' '))

  After this the disk is NOT encrypted any more: anyone with the laptop can read it.
  Do not power off, suspend or reboot until it says DONE. Keep the charger plugged in.
EOF

ac=0
for s in /sys/class/power_supply/*; do
    [[ -r $s/online && $(cat "$s/type" 2>/dev/null) != Battery ]] && [[ $(cat "$s/online") == 1 ]] && ac=1
done
((ac)) || printf '\n\033[93m  WARNING: the charger does not look plugged in.\033[0m\n'

printf '\nType YES to start: '
read -r answer
[[ $answer == YES ]] || die "Cancelled, nothing changed."

# --- 1. header backup --------------------------------------------------------------------------
say "Backing up the LUKS header to $backup"
cryptsetup luksHeaderBackup "$dev" --header-backup-file "$backup"

# Stop the machine from sleeping while this runs.
inhibit=()
command -v systemd-inhibit >/dev/null && inhibit=(systemd-inhibit --what=sleep:idle:handle-lid-switch --who=remove-disk-encryption --why="Decrypting the disk")

# --- 2. decrypt --------------------------------------------------------------------------------
say "Decrypting $dev (asks for the DISK password, the old one). This takes a while."
if ! "${inhibit[@]}" cryptsetup reencrypt --decrypt --batch-mode --header "$header" --progress-frequency 5 "$dev"; then
    if [[ -e $header ]]; then
        cat >&2 <<EOF

Decryption stopped before the end. The boot configuration was NOT changed.
Do not reboot. Resume it with:
    sudo cryptsetup reencrypt --resume-only --header $header $dev
EOF
    else
        printf '\nDecryption did not start; nothing on the disk changed. You can run this script again.\n' >&2
    fi
    exit 1
fi

# --- 3. verify -------------------------------------------------------------------------------
say "Checking the partition"
blkid -p "$dev" >/dev/null 2>&1 || true
new_type=$(blkid -p -s TYPE -o value "$dev" || true)
new_uuid=$(blkid -p -s UUID -o value "$dev" || true)
if [[ $new_type != "$fs_type" || $new_uuid != "$fs_uuid" ]]; then
    die "After decryption $dev reads as '$new_type' UUID '$new_uuid', expected $fs_type $fs_uuid. Boot config NOT changed; do not reboot and ask for help."
fi

# --- 4. boot config ----------------------------------------------------------------------------
for f in /etc/default/limine /etc/kernel/cmdline; do
    [[ -f $f ]] || continue
    cp -a "$f" "$f.luks-backup"
    sed -i -e "s#cryptdevice=$spec \?##g" -e "s#root=/dev/mapper/$name#root=UUID=$fs_uuid#g" "$f"
    say "Updated $f (old one kept as $f.luks-backup)"
    grep -n 'root=' "$f" || true
done

say "Rebuilding the initramfs and boot entries"
limine-update

if grep -q "cryptdevice=$spec" /boot/limine.conf 2>/dev/null; then
    printf '\033[93mWARNING: /boot/limine.conf still mentions cryptdevice= (maybe old snapshot entries). The default entry should be fine.\033[0m\n'
fi

cat <<EOF

DONE. The disk is no longer encrypted; reboot and there is no disk password any more.
$header and $backup are not needed any more; delete them once the machine has booted fine.
EOF
