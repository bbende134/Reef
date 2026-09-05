# Reef

The macOS window manager that gives every app its own Alt-Tab. 

![Cover photo. Reef logo and UI.](./github-assets/reef-banner-1280-short.jpg)

[Download for macOS](https://getreef.app) · [GitHub Releases](https://github.com/gouwsxander/Reef/releases/latest) (Requires macOS 14.6+)

[How we made Reef (YouTube)](https://youtu.be/niRCi5zJvHU)

## Key Features

Reef lets you bind applications to number keys and cycle through their windows with an Alt-Tab-like interface.

We built Reef because we wanted a fast and simple window switcher for macOS.

- Bind applications to number keys to refocus to **any** window for that app
- Assign profiles for different sets of bindings
- Do your binding and profile management through the keyboard
- Customizable keyboard shortcuts


## Usage

### Binding
You should start by binding different applications to the number keys. You can do this:
- through **Preferences → Profiles** (accessed through the menu bar), or
- by selecting the application of your choice and then pressing <kbd>Ctrl</kbd> + <kbd>Option</kbd> + <kbd>Shift</kbd>.

### Profiles
You can also set your bindings up in different profiles.

For example, you may want two profiles:
- "Coding": Which binds your favourite editor, browser, and terminal
- "Browsing": Which binds your favourite web browser, messaging app, and music client

You can switch between profiles:
- using the menu bar, or
- by binding them to the number keys, and then pressing <kbd>Ctrl</kbd> + <kbd>Option</kbd> + <kbd>[0-9]</kbd>.

### Switching applications
Suppose you're in your coding profile, and have your editor bound to `0`.

To switch between apps and windows:
1. Hold <kbd>Control</kbd> and press <kbd>0</kbd> to open a panel showing each of your editor's windows.
2. Press <kbd>0</kbd> multiple times to select the specific window you want.
3. Release <kbd>Control</kbd> to switch to the selected window.

In this way, Reef gives every app its own 'Alt-Tab'.

Note that window switching is scoped to your current [macOS space](https://support.apple.com/en-ca/guide/mac-help/mh14112/mac).

### Aligning windows

While the switcher panel is open — that is, while you are still holding <kbd>Ctrl</kbd> — you can also *move* the highlighted window:

| Key | Action |
| --- | --- |
| <kbd>H</kbd> / <kbd>L</kbd> | Left / right half. Press again to cycle ½ → ⅓ → ⅔ |
| <kbd>K</kbd> / <kbd>J</kbd> | Top / bottom half, with the same cycling |
| <kbd>⌥</kbd> + <kbd>H</kbd>/<kbd>J</kbd>/<kbd>K</kbd>/<kbd>L</kbd> | Quarters along that edge; press again for the other corner |
| <kbd>M</kbd> | Maximize (fills the screen; not native full screen) |
| <kbd>C</kbd> | Centre, keeping the window's size |
| <kbd>R</kbd> | Put the window back where it was before Reef first moved it |

So <kbd>Ctrl</kbd>+<kbd>1</kbd>, then <kbd>H</kbd>, then release: summon a window, snap it left, land in it — one motion.

Aligning does not raise the window, so you can align one window, tap the number key to move to the next, align that one too, and release <kbd>Ctrl</kbd> once. Pressing <kbd>Esc</kbd> after aligning keeps the new position without switching to the window.

Alignment adds **no new global shortcuts** — the keys above are only live while the panel is open, so nothing collides with your existing bindings or with macOS's own shortcuts.

Arrow keys are wired to the same actions as <kbd>H</kbd>/<kbd>J</kbd>/<kbd>K</kbd>/<kbd>L</kbd>, but on a stock Mac they never reach Reef: <kbd>Ctrl</kbd>+arrow is claimed by Mission Control and by "move left/right a space". Turn those off in **System Settings → Keyboard → Keyboard Shortcuts → Mission Control** if you would rather use arrows.

#### Known limitations

- **Full-screen, minimized, and fixed-size windows are refused** (Reef beeps). Aligning a native full-screen window would leave it in a broken half-full-screen state.
- **Some apps clamp what you ask for.** Terminal snaps to its character grid, and many Electron apps enforce a minimum size. Reef keeps the size the app insists on and slides the window back inside the screen.
- **Stage Manager.** macOS does not publish the width of the Stage Manager strip, so Reef cannot subtract it automatically. If you run Stage Manager with the strip pinned, set the inset once:
  ```
  defaults write xandergouws.Reef alignmentStageManagerInset -float 64
  ```

### Customization

You can customize the modifiers for switching applications and profiles, and for binding different applications in **Reef Preferences → Shortcuts**.

### Credits

The window-framing logic — the order Accessibility writes have to be made in, the
`AXEnhancedUserInterface` workaround for Electron and Chromium apps, and the carve-out
that leaves it alone while VoiceOver or Switch Control is running — is ported from
[Rectangle](https://github.com/rxhanson/Rectangle) (MIT, Copyright (c) 2019-2026 Ryan
Hanson, based on Spectacle, Copyright (c) 2017 Eric Czarny). That hard-won knowledge is
theirs.


## Installation

Download the latest release on [our website](https://getreef.app) or [GitHub](https://github.com/gouwsxander/Reef/releases/latest)

Simply: 
1) Download the `.zip` and unzip the file.
2) Drag `Reef.app` into your Applications folder.

Reef is free/pay-what-you-want. Use the link on our website to support us.

### Compatibility

Reef is compatible with **macOS 14.6 (Sonoma)** and onwards. 

You can find your macOS version from the ** → About This Mac** page.


## Development

### Building without Xcode

This fork builds with only the **Xcode Command Line Tools** — no 30 GB Xcode install:

```bash
./build.sh          # -> .build/Reef.app   (~30 s from clean)
./check.sh          # runs the model-layer assertions
```

`Package.swift` is an alternative front door; `Reef.xcodeproj` is untouched and still
works if you do have Xcode.

Three things ship only inside Xcode.app, so the standalone build works around each:

| Missing | Consequence | Workaround |
| --- | --- | --- |
| `actool` | Asset catalogs cannot compile | `ReefMenuIcon44.png` is copied straight into `Resources` and loaded by `ReefApp.menuBarIcon`. The app has no Finder icon. |
| `PreviewsMacros` | `#Preview` fails to compile | Previews removed from Reef's views, and KeyboardShortcuts is vendored with its three previews stripped (see `Vendor/KeyboardShortcuts/VENDORED.md`) |
| XCTest / swift-testing | `ReefTests/` cannot run | The same assertions live in `Checks/main.swift`, run by `./check.sh` |

Sparkle is removed entirely in this fork, which also avoids embedding and signing a
framework with nested XPC services by hand.

#### Signing and the Accessibility permission

`build.sh` signs ad-hoc but pins an explicit designated requirement:

```
designated => identifier "xandergouws.Reef"
```

This matters. A plain ad-hoc signature's requirement is a bare `cdhash`, which changes
on every rebuild and invalidates the Accessibility grant each time. Pinning it to the
bundle identifier means one grant covers every future build — verified by rebuilding
with changed code and confirming the requirement is byte-identical while the cdhash
moved.

Because the signing identity differs from the released app's Developer ID, the existing
grant does **not** carry over on first install:

```bash
osascript -e 'tell application "Reef" to quit'
rm -rf /Applications/Reef.app
ditto .build/Reef.app /Applications/Reef.app
tccutil reset Accessibility xandergouws.Reef
open /Applications/Reef.app
```

Then press <kbd>Ctrl</kbd>+<kbd>1</kbd> to trigger the permission prompt, allow Reef in
System Settings → Privacy & Security → Accessibility, and quit and relaunch it.


Please share issues and feedback via the [GitHub issues page](https://github.com/gouwsxander/Reef/issues).

Feel free to submit pull requests, though we can't guarantee that we'll get to them.


## FAQ
<details>
<summary><b>Why is it called "Reef"?</b></summary>
<br>
The name comes from the starting sounds of the words "refocus" and "reframe". And, like a coral reef supports a diverse ecosystem, Reef supports your workspace—helping you navigate between windows quickly and easily.
</details>


## Related Projects
- [yabai](https://github.com/asmvik/yabai)
- [Aerospace](https://github.com/nikitabobko/AeroSpace?tab=readme-ov-file)
- [Rectangle](https://github.com/rxhanson/Rectangle)
- [AltTab for macOS](https://github.com/lwouis/alt-tab-macos/tree/master)
