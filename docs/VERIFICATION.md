# Verification

Initial public beta, October 30, 2026.

## Native Premiere checks

The effect was exercised in Adobe Premiere Pro 26.5.2 on an Intel Mac using synthetic, labeled foreground images over a contrasting checkerboard. Tests covered opaque and existing-half-transparent inputs at 960 × 540, 30 fps.

- Default values preserved the native captured picture exactly, for both inputs.
- Four independent sides had correct orientation, unchanged opposite regions and transparent outer boundaries.
- Top/bottom, left/right and all-side linking, 100% wide fades, smooth/linear curves, insets and overlapping fades behaved as intended.
- Scaling the clip with native Motion to 50% scaled the feather with it.
- Settings survived save, close and reopening. Native Effect Controls displayed the complete control set.
- Actual five-second ProRes 4444 exports were decoded and compared. Applying the effect at zero produced exactly the same decoded RGB as removing the effect. The unaffected region matched exactly; the fully transparent boundary matched a background-only export within one 8-bit level.

Thirty-three image checks passed. These were static patterns; this does not establish real-time playback speed or animated-control behavior.

The factory movie exports' default BT.709-tagged interpretation differed from Premiere's PNG captures even with the effect removed. An explicit BT.601 diagnostic closely matched the PNGs. No media was changed to hide that difference. Same-export-path controls isolated Side Feather's identity and blend behavior from this export/color-interpretation issue.

The public package uses the same rendering source with release metadata, path remapping and distribution signing. Public-package host checks are recorded in the release notes.

## Automated checks

The host-independent C++ core and pixel-buffer bridge passed 20,108 checks with strict warnings, AddressSanitizer and UndefinedBehaviorSanitizer. They cover side isolation, linking, insets, broad/overlapping ramps, invalid inputs, one-pixel dimensions, signed/padded strides, unaligned data, in-place rendering, chunk boundaries, identity, straight BGRA8/32f alpha, HDR-value preservation and premultiplied AE ARGB8/16.

Run `bash scripts/check.sh`. CI runs core/buffer checks on Linux and macOS and builds the plug-in on macOS. These checks do not replace native host acceptance.

## Remaining qualification

Apple silicon runtime behavior, other Premiere versions, After Effects, Windows, interlaced sources, animated controls and HDR delivery remain unqualified. Floating-point buffers are unit-tested, but Premiere did not report which negotiated format it used during the native checks. This release has no GPU rendering path or real-time performance guarantee.
