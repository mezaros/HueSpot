# HueSpot

## Introduction

HueSpot helps you identify any color on your screen. It's a MacOS menu bar app that, with just a point and click, boils any shade or hue down to a simple color name (i.e. blue or greenish-blue) and a hex code. Plus, the matching (or closest) specific color name from two widely known sets of color names.

Simple color names make this a helpful tool for those with color vision issues (color deficiency or "color blindness"). If you have trouble telling your reds from your greens, or your blues from your purples, this app will tell you the answer without involving obtuse shade names like "bittersweet shimmer." 

It's also a useful tool for designers and developers. In addition to hex codes, HueSpot can translate colors to CSS rgb() formats, NSColor, UIColor, etc.

## Why It Exists

HueSpot replicates some of the functionality of an older app named Color Doggy, which is sadly no longer developed.

This app is also an experiment in the use of AI coding assistants. While I'm technical and have done plenty of light scripting (Python and the like), I'm not a true developer. I don't know Swift. I don't know the MacOS APIs. I don't really know best practices, on the Mac or even for coding in general. I don't even have an Apple developer account. I've used AI for scripting over the past three years, but never a real coding assistant. This is one of two apps I've written in recent days using "pure vibes." I've been fiddling with it on and off for about two weeks, but in terms of real hours spent? Probably a full work day. Some of that being learning curve time with Codex.

Is the code spaghetti? Is it the worst written Mac app in history? I have no idea. I've barely looked at the code. If you actually know what you're doing, I'd love to hear your take on it.

What little I know: the app is written in Swift 5 and uses a mixture of SwiftUI and AppKit, as (allegedly) certain things could only be done in AppKit. No idea if that's true. I've asked Codex to explain how it works. See /CODEX.md.

## What It Does

HueSpot is a macOS menu bar app that identifies the color under the pointer while you hold an activation key. That key is fully configurable in Settings: make it anything you like.

It shows a floating HUD or overlay with:

- Simple color name
- ISCC-NAB Extended color name (optional)
- Web (HTML/CSS) or Wikipedia "List of Colors" color name (optional)
- RGB Hexadecimal (optional)

The simple color name strives to be simple. It usually sticks to the traditional colors, adding additional information (i.e. a compound name like brownish-red or a clarifying parenthetical like "teal") only when helpful.

HueSpot can also copy color data to the clipboard on activation-key double press, and many additional formats are available for this purpose (see the Settings window). Many of these formats are helpful for designers and developers.

## Permissions & Signing

HueSpot requires Screen Recording permission to read the colors on your screen. This is partly why I'm only releasing code, not the binary, at the moment. If your binary is self-signed using Xcode's default method, Apple's permission system may not always recognize HueSpot as the same app (or at least, so it seemed to me). I solved this problem by making a new personal certificate in Keychain Access and signing with that. You could also solve this by having an Apple developer account and properly signing the app.

## Requirements

- macOS 15+
- Xcode 16+

## Build And Run

1. Open `HueSpot.xcodeproj` in Xcode.
2. Select the `HueSpot` scheme.
3. Build and run.
4. Grant Screen Recording permission when prompted.

## License

- Licensed under GPL 2.0.
- Full license text: /LICENSE.txt
