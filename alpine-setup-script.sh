#!/bin/sh
# Fully automated Alpine kiosk setup script
# Run as root

# ----------------------------
# 1. Check for root
# ----------------------------
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root"
    exit 1
fi

# ----------------------------
# 2. Enable community repository if not present
# ----------------------------
if ! grep -q "community" /etc/apk/repositories; then
    echo "Adding community repository..."
    echo "http://dl-cdn.alpinelinux.org/alpine/v$(cut -d. -f1-2 /etc/alpine-release)/community" >> /etc/apk/repositories
fi

# ----------------------------
# 3. Update Alpine and install missing packages
# ----------------------------
apk update

# List of required packages
REQUIRED_PKGS="cage flatpak seatd mesa-dri-gallium bash dbus dbus-x11 xdg-desktop-portal xdg-desktop-portal-wlr sudo shadow curl wget tzdata"

for pkg in $REQUIRED_PKGS; do
    if ! apk info -e "$pkg" >/dev/null 2>&1; then
        echo "Installing $pkg..."
        apk add --no-cache "$pkg"
    fi
done

# ----------------------------
# 4. Set keyboard (US default)
# ----------------------------
if [ ! -f /etc/conf.d/keymaps ]; then
    echo "us" > /etc/conf.d/keymaps
    loadkeys us
fi

# ----------------------------
# 5. Set locale (UTF-8)
# ----------------------------
if ! grep -q "en_US.UTF-8" /etc/locale.gen 2>/dev/null; then
    echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
    locale-gen
    echo "export LANG=en_US.UTF-8" > /etc/profile.d/locale.sh
    chmod +x /etc/profile.d/locale.sh
fi

# ----------------------------
# 6. Set timezone (UTC default)
# ----------------------------
if [ ! -f /etc/localtime ]; then
    cp /usr/share/zoneinfo/UTC /etc/localtime
    echo "UTC" > /etc/timezone
fi

# ----------------------------
# 7. Create kiosk user and seat group
# ----------------------------
if ! id -u kiosk >/dev/null 2>&1; then
    adduser -D -h /home/kiosk -s /bin/sh kiosk
    echo "Created user 'kiosk'"
fi

# Add to seat group for device access
addgroup kiosk seat 2>/dev/null

# ----------------------------
# 8. Setup Flatpak and Firefox as kiosk user
# ----------------------------
su - kiosk -c "
if ! flatpak remotes | grep -q flathub; then
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
fi

if ! flatpak list | grep -q org.mozilla.firefox; then
    flatpak install -y flathub org.mozilla.firefox
fi
"

# ----------------------------
# 9. Create kiosk launcher script
# ----------------------------
KIOSK_SCRIPT=/home/kiosk/kiosk.sh
if [ ! -f "$KIOSK_SCRIPT" ]; then
cat > "$KIOSK_SCRIPT" << 'EOF'
#!/bin/sh
# Kiosk launcher

# Runtime directory for Flatpak/Wayland
export XDG_RUNTIME_DIR=/run/user/$(id -u kiosk)
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
chown kiosk:kiosk "$XDG_RUNTIME_DIR"

# Force CPU rendering if no DRM device
if [ ! -e /dev/dri/card0 ]; then
    export WLR_NO_HARDWARE=1
fi

# Start seatd if not running
if ! pgrep -x seatd >/dev/null; then
    seatd &
fi

# Start DBus if not running
if ! pgrep -x dbus-daemon >/dev/null; then
    dbus-launch --sh-syntax >/tmp/dbus-env
    . /tmp/dbus-env
fi

# Launch Cage + Flatpak Firefox
exec cage -- flatpak run org.mozilla.firefox
EOF

chmod +x "$KIOSK_SCRIPT"
chown kiosk:kiosk "$KIOSK_SCRIPT"
fi

# ----------------------------
# 10. Setup auto-login for TTY1
# ----------------------------
PROFILE=/home/kiosk/.profile
if ! grep -q 'exec ~/kiosk.sh' "$PROFILE" 2>/dev/null; then
cat >> "$PROFILE" << 'EOF'
# Auto-start kiosk on TTY1
if [ -z "$WAYLAND_DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    exec ~/kiosk.sh
fi
EOF
chown kiosk:kiosk "$PROFILE"
fi

# ----------------------------
# 11. Enable and start DBus and seatd services
# ----------------------------
rc-update add dbus
rc-update add seatd
service dbus start 2>/dev/null
service seatd start 2>/dev/null

# ----------------------------
# Done
# ----------------------------
echo "Alpine kiosk setup complete!"
echo "Reboot or switch to TTY1 and login as 'kiosk' to start the kiosk environment."