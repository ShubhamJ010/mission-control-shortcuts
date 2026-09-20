# Resources: macOS Event Architecture & Multitouch

A curated collection of resources grounding the teaching on Quartz Event Taps, MultitouchSupport private framework, and trackpad click disambiguation.

## Primary Sources
- [Quartz Event Services Reference (Apple Developer Archives)](https://developer.apple.com/documentation/coregraphics/quartz_event_services)
  - Canonical reference for `CGEventTap`, event masks, head insertion points, and filter callbacks.
- [CGEventField Reference (Apple Developer)](https://developer.apple.com/documentation/coregraphics/cgeventfield)
  - Details integer and double value fields including `mouseEventPressure` (`kCGMouseEventPressure`), `mouseEventSubtype`, and `mouseEventClickState`.
- [MultitouchSupport Reverse Engineering (Darwin / Open Source)](https://github.com/mizunashi-mana/MultitouchSupport-header)
  - C structure layout for `Finger`, touch states (hovering, touching, lifting), and `MTContactFrameCallback`.

## Community & Technical Discussions
- [Differentiating Trackpad Tap vs Physical Click on macOS (StackOverflow)](https://stackoverflow.com/questions/30897217/differentiating-trackpad-tap-and-click-in-os-x)
  - Deep architectural breakdown of hardware abstraction and pressure profiles on Force Touch trackpads.
