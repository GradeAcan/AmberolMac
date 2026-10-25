# AmberolMac

A native, and (hopefully) minimal-resource audio player for macOS, inspired by the minimalist design philosophy of [Amberol](https://gitlab.gnome.org/Bassi/amberol).

## Features

- **Native Stack**: Written entirely from scratch in Swift and SwiftUI using `AVFoundation`.
- **No Bullshit**: Ultra-lightweight footprint (~3.5% CPU usage, ~87-120MB RAM).
- **Dynamic UI**: Dynamic blurred background that adapts to the current track's album artwork.
- **macOS Integration**: Full support for `MPRemoteCommandCenter` (Control Center, hardware media keys).
- **QoL Controls**: Playlist drag-and-drop, shuffle, loop modes (`off`, `all`, `one`), and seamless auto-play.

## Building from Source

No Xcode or paid developer account required. You can build the application manually using the provided automation script:
#### It is a bit messy, so you can build from source (if you can even call it that) but i'll also try and keep a "releases" tab updated.

```bash
git clone https://github.com/GradeAcan/AmberolMac.git
cd AmberolMac
./build.sh
```
Troubleshooting (Quarantine)

Because the binary is built locally with ad-hoc signing, macOS might restrict it upon first launch. If the system blocks the application, simply clear the quarantine attribute via terminal:
```Bash

xattr -cr AmberolMac.app
```
