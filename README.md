# NetToggle

A quick proof-of-concept macOS app that lets you bind a global hotkey to toggle a Network Link Conditioner-like traffic profile on and off.

It is intentionally small and uses the same primitives Apple’s Network Link Conditioner uses under the hood: `dnctl` (dummynet pipes) and `pfctl` (packet filter rules).

```
global hotkey → NetToggle app → setuid root NetToggleHelper → dnctl + pfctl rules
```

## What it does

- Runs as a tiny menu-bar app.
- Captures a global key combination of your choice (needs Accessibility permission).
- Toggles a `dnctl`/`pfctl` network profile on/off on every key press.
- Shapes **inbound and outbound traffic independently**.
- Default profile is **0 ms delay + 90% packet loss** in both directions. Open the app’s **Settings...** window to change both directions on the fly.

## Files

- `Sources/NetToggle/` — Swift/ObjC-free AppKit menu-bar app.
- `Helper/NetToggleHelper.c` — setuid-root C helper that calls `dnctl` and `pfctl`.
- `install.sh` — compiles the helper, installs it to `/usr/local/bin`, and sets the setuid bit.
- `make-app.sh` — builds a signed `NetToggle.app` bundle that you can drag to `/Applications`.

## Build the app bundle

```bash
./make-app.sh
```

This produces a signed `.build/release/NetToggle.app`. Drag that to `/Applications` (or run `cp -R .build/release/NetToggle.app /Applications/`).

## Install the root helper

The helper needs to be owned by `root` and have the `setuid` bit set. The install script handles that:

```bash
./install.sh
```

It will ask for your admin password. After it finishes, verify:

```bash
ls -la /usr/local/bin/NetToggleHelper
# should show: -rwsr-xr-x 1 root wheel ... /usr/local/bin/NetToggleHelper
```

If `/usr/local/bin` does not exist or you cannot write there, the script falls back to `~/.local/bin`.

## Run

After installing the helper and placing `NetToggle.app` in `/Applications`, launch it from Finder or run:

```bash
open /Applications/NetToggle.app
```

On first launch macOS will ask you to grant **Accessibility** access so the app can listen for global hotkeys. After granting it, **relaunch** the app.

Right-click the menu-bar icon (or open it from the status bar) to:

- **Settings...** — set the global hotkey, inbound delay/loss, and outbound delay/loss.
- **Toggle Network** — turn the network profile on/off manually.
- **Quit** — exit and automatically turn the profile off if it is active.

## Troubleshooting

- **“Helper not found or not executable”** — make sure `install.sh` completed successfully, or set `NETTOGGLE_HELPER` to the full path:
  ```bash
  NETTOGGLE_HELPER=/path/to/NetToggleHelper /Applications/NetToggle.app/Contents/MacOS/NetToggle
  ```
- **Hotkey does not work** — check *System Settings → Privacy & Security → Accessibility* and make sure `NetToggle` is enabled, then relaunch.
- **Network does not change after toggle** — the helper may have been blocked by Gatekeeper. Try `sudo xattr -d com.apple.quarantine /usr/local/bin/NetToggleHelper` or run `install.sh` again.
- **No status bar icon** — the app may be running under a process that does not have a display session. Run it from a normal macOS user session (not a remote/headless shell).

## Warnings

- This is a **proof-of-concept**. The helper runs with root privileges via `setuid`. Only use it on your own machine and review the code before granting root.
- The profile applies to **all traffic** by default (TCP/UDP/ICMP, both directions, with per-direction settings). If you only want Roblox traffic, you will need to filter by host/port/UID in `NetToggleHelper.c` and rebuild.
- Toggling the network profile uses `pfctl -f`, which temporarily replaces the running PF ruleset. The helper restores the default `/etc/pf.conf` when turned off.

## Customizing the profile

Edit `Helper/NetToggleHelper.c` and adjust the `DEFAULT_DELAY` and `DEFAULT_PLR` macros, or change the `rules` string to use different dummynet pipes. Then run `./install.sh` again.
