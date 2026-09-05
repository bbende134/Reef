# Vendored: KeyboardShortcuts

Source: https://github.com/sindresorhus/KeyboardShortcuts @ **2.3.0**
Licence: MIT — Copyright (c) Sindre Sorhus. See `LICENSE`.

## Why vendored

This fork builds without Xcode, using only the Command Line Tools. `Recorder.swift`
ends with three `#Preview { … }` blocks, and the `#Preview` macro is implemented by
`PreviewsMacros`, a plugin that ships *only* inside Xcode.app. Building against the
upstream package therefore fails under CLT with:

    error: external macro implementation type 'PreviewsMacros.SwiftUIView' could not be
    found for macro 'Preview(_:body:)'; plugin for module 'PreviewsMacros' not found

## The only modification

`Recorder.swift`: the three trailing `#Preview` blocks are removed and the file's
`#if os(macOS)` is closed with `#endif`. Nothing else is changed. Reef does not use
`KeyboardShortcuts.Recorder` at all — it sets shortcuts programmatically from
`ModifierManager` — so no functionality is lost.
