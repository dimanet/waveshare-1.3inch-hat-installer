#!/usr/bin/env bash
set -euo pipefail

# One-file installer for Waveshare 1.3inch LCD HAT on Raspberry Pi OS Lite/minimal.
# Safe usage:
#   curl -fsSL <URL>/install-waveshare-1.3inch-hat.sh | sudo bash -s -- pi
# Or:
#   sudo bash install-waveshare-1.3inch-hat.sh pi

TARGET_USER="${1:-pi}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6 || true)"

if [[ ${EUID} -ne 0 ]]; then
  echo "Run as root: sudo bash $0 [username]" >&2
  exit 1
fi

if [[ -z "$TARGET_HOME" || ! -d "$TARGET_HOME" ]]; then
  echo "User '$TARGET_USER' does not exist or has no home directory" >&2
  exit 1
fi

CFG=/boot/config.txt
[[ -f /boot/firmware/config.txt ]] && CFG=/boot/firmware/config.txt

backup_file() {
  local f="$1"
  [[ -f "$f" ]] && cp -a "$f" "$f.bak.$(date +%Y%m%d-%H%M%S)"
}

echo "[+] Installing packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y \
  xserver-xorg xinit x11-xserver-utils xserver-xorg-video-fbdev \
  openbox lxsession lxpanel pcmanfm lxterminal menu \
  python3-gpiozero python3-evdev xfonts-base

echo "[+] Backing up and editing boot config: $CFG"
backup_file "$CFG"
sed -i 's/^dtoverlay=vc4-kms-v3d/#dtoverlay=vc4-kms-v3d/' "$CFG" || true
sed -i 's/^dtoverlay=vc4-fkms-v3d/#dtoverlay=vc4-fkms-v3d/' "$CFG" || true
sed -i 's/^#\?dtparam=spi=on/dtparam=spi=on/' "$CFG" || true

python3 - "$CFG" <<'PY'
from pathlib import Path
import sys
cfg = Path(sys.argv[1])
lines = cfg.read_text().splitlines()
out = []
seen = {
    'overlay': False,
    'spi': False,
    'gpio': False,
    'hotplug': False,
}
for line in lines:
    s = line.strip()
    if s.startswith('dtoverlay=fbtft,'):
        out.append('dtoverlay=fbtft,spi0-0,st7789v,reset_pin=27,dc_pin=25,led_pin=24,speed=40000000,rotate=90,width=240,height=240,fps=30')
        seen['overlay'] = True
    else:
        out.append(line)
    if s == 'dtparam=spi=on':
        seen['spi'] = True
    if s == 'gpio=6,19,5,26,13,21,20,16=pu':
        seen['gpio'] = True
    if s == 'hdmi_force_hotplug=1':
        seen['hotplug'] = True
if not seen['overlay']:
    out.append('dtoverlay=fbtft,spi0-0,st7789v,reset_pin=27,dc_pin=25,led_pin=24,speed=40000000,rotate=90,width=240,height=240,fps=30')
if not seen['spi']:
    out.append('dtparam=spi=on')
if not seen['gpio']:
    out.append('gpio=6,19,5,26,13,21,20,16=pu')
if not seen['hotplug']:
    out.append('hdmi_force_hotplug=1')
cfg.write_text('\n'.join(out) + '\n')
PY

echo "[+] Writing Xorg fbdev config"
mkdir -p /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/99-waveshare-fbdev.conf <<'EOF'
Section "Device"
    Identifier  "WaveshareFB"
    Driver      "fbdev"
    Option      "fbdev" "/dev/fb1"
EndSection

Section "Screen"
    Identifier "Screen0"
    Device     "WaveshareFB"
    DefaultDepth 16
    SubSection "Display"
        Depth 16
        Modes "320x240"
        Virtual 320 240
    EndSubSection
EndSection
EOF

echo "[+] Installing joystick mouse service"
cat > /usr/local/bin/waveshare-joystick-mouse.py <<'EOF'
#!/usr/bin/env python3
import time
from gpiozero import Button
from evdev import UInput, ecodes as e

MOVE_PINS = {'up': 6, 'down': 19, 'left': 5, 'right': 26}
CLICK_PINS = {13: e.BTN_LEFT, 21: e.BTN_LEFT, 20: e.BTN_RIGHT, 16: e.BTN_MIDDLE}
buttons = {name: Button(pin, pull_up=True, bounce_time=0.02) for name, pin in MOVE_PINS.items()}
clickers = {pin: Button(pin, pull_up=True, bounce_time=0.05) for pin in CLICK_PINS}
ui = UInput({e.EV_KEY: [e.BTN_LEFT, e.BTN_RIGHT, e.BTN_MIDDLE], e.EV_REL: [e.REL_X, e.REL_Y]}, name='waveshare-joystick-mouse', version=0x3)
pressed = {pin: False for pin in CLICK_PINS}
base_step, accel_step, accel_after = 6, 14, 0.35
hold_since = {k: None for k in buttons}
while True:
    dx = dy = 0
    now = time.monotonic()
    for name, btn in buttons.items():
        active = btn.is_pressed
        if active and hold_since[name] is None:
            hold_since[name] = now
        if not active:
            hold_since[name] = None
    # Inverted directions to match tested physical orientation.
    if buttons['left'].is_pressed:
        dx += accel_step if hold_since['left'] and now - hold_since['left'] > accel_after else base_step
    if buttons['right'].is_pressed:
        dx -= accel_step if hold_since['right'] and now - hold_since['right'] > accel_after else base_step
    if buttons['up'].is_pressed:
        dy += accel_step if hold_since['up'] and now - hold_since['up'] > accel_after else base_step
    if buttons['down'].is_pressed:
        dy -= accel_step if hold_since['down'] and now - hold_since['down'] > accel_after else base_step
    if dx or dy:
        ui.write(e.EV_REL, e.REL_X, dx)
        ui.write(e.EV_REL, e.REL_Y, dy)
        ui.syn()
    for pin, code in CLICK_PINS.items():
        active = clickers[pin].is_pressed
        if active and not pressed[pin]:
            ui.write(e.EV_KEY, code, 1)
            ui.syn()
            pressed[pin] = True
        elif not active and pressed[pin]:
            ui.write(e.EV_KEY, code, 0)
            ui.syn()
            pressed[pin] = False
    time.sleep(0.02)
EOF
chmod 0755 /usr/local/bin/waveshare-joystick-mouse.py

echo uinput > /etc/modules-load.d/uinput.conf
modprobe uinput || true
cat > /etc/systemd/system/waveshare-joystick-mouse.service <<'EOF'
[Unit]
Description=Waveshare LCD HAT joystick as mouse
After=multi-user.target

[Service]
Type=simple
ExecStart=/usr/local/bin/waveshare-joystick-mouse.py
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable waveshare-joystick-mouse.service

echo "[+] Configuring tty1 autologin and X start"
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $TARGET_USER --noclear %I \$TERM
EOF

cat > "$TARGET_HOME/.bash_profile" <<'EOF'
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
  exec startx /usr/bin/startlxde -- :0 vt1 -keeptty
fi
EOF
chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.bash_profile"
chmod 0644 "$TARGET_HOME/.bash_profile"

echo "[+] Writing tiny-screen desktop defaults"
install -d -o "$TARGET_USER" -g "$TARGET_USER" "$TARGET_HOME/.config/lxpanel/default/panels"
install -d -o "$TARGET_USER" -g "$TARGET_USER" "$TARGET_HOME/.config/pcmanfm/default"
install -d -o "$TARGET_USER" -g "$TARGET_USER" "$TARGET_HOME/.config/lxsession/LXDE"

cat > "$TARGET_HOME/.config/lxpanel/default/panels/panel" <<'EOF'
Global {
  edge=top
  align=left
  margin=0
  widthtype=percent
  width=100
  height=28
  transparent=0
  alpha=0
  autohide=1
  heightwhenhidden=2
  setdocktype=1
  setpartialstrut=1
  fontsize=10
  usefontsize=1
  iconsize=20
  monitor=0
}
Plugin {
  type=menu
  Config {
    image=start-here
    system {
    }
  }
}
Plugin {
  type=space
  Config { Size=4 }
}
Plugin {
  type=launchbar
  Config {
    Button { id=pcmanfm.desktop }
    Button { id=lxterminal.desktop }
  }
}
Plugin {
  type=taskbar
  expand=1
  Config {
    tooltips=0
    IconsOnly=1
    FlatButton=1
    MaxTaskWidth=80
    GroupedTasks=1
  }
}
Plugin {
  type=clock
  Config {
    ClockFmt=%H:%M
    TooltipFmt=%Y-%m-%d %H:%M
  }
}
EOF

cat > "$TARGET_HOME/.config/pcmanfm/default/desktop-items-0.conf" <<'EOF'
[*]
wallpaper_mode=color
wallpaper_common=1
wallpaper=#000000
desktop_bg=#000000
desktop_fg=#ffffff
desktop_shadow=#000000
desktop_font=Sans 11
show_wm_menu=1
show_documents=0
show_trash=0
show_mounts=0
EOF

cat > "$TARGET_HOME/.config/lxsession/LXDE/desktop.conf" <<'EOF'
[GTK]
sGtk/FontName=Sans 11
iGtk/CursorThemeSize=32
iGtk/ToolbarIconSize=2
sGtk/IconSizes=gtk-large-toolbar=20,20
EOF

chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.config"

echo "[+] Disabling display manager if present"
systemctl disable lightdm 2>/dev/null || true
systemctl disable sddm 2>/dev/null || true
systemctl disable gdm3 2>/dev/null || true

echo
echo "Done. Reboot now: sudo reboot"
echo "After reboot: LCD on fb1 should become the main visible desktop, and the joystick should act as a mouse."
