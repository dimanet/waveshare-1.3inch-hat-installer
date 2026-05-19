# waveshare-1.3inch-hat-installer

Installer for the Waveshare 1.3inch LCD HAT on Raspberry Pi OS Lite / minimal systems.

It sets up:
- ST7789 LCD as framebuffer display
- minimal X11 desktop on the LCD
- joystick/buttons as a mouse
- tty1 autologin + automatic desktop start
- tiny-screen desktop defaults

## Quick install

```bash
curl -fsSL https://raw.githubusercontent.com/dimanet/waveshare-1.3inch-hat-installer/main/install-waveshare-1.3inch-hat.sh | sudo bash -s -- pi
```

Replace `pi` with your target username if needed.

## Local install

```bash
sudo bash install-waveshare-1.3inch-hat.sh pi
sudo reboot
```

## Files

- `install-waveshare-1.3inch-hat.sh` — single-file curlable installer
- `scripts/setup-waveshare-1.3inch-hat-lite.sh` — more verbose local setup script

## Notes

- joystick directions are inverted to match the tested physical orientation
- Xorg is configured to use `/dev/fb1`
- current setup targets the Waveshare 1.3 inch LCD HAT with ST7789 controller
