# DanceFX

Native macOS prototype for low-latency live human matting. It uses the official recurrent Robust Video Matting (RVM) MobileNetV3 FP16 Core ML model, with Apple's Vision person segmentation retained as an automatic fallback if the packaged model cannot be loaded.

## What works

- AVFoundation camera discovery, 1280×720 capture, runtime switching, and late-frame discard
- exactly one inference at a time; incoming frames are dropped while inference is busy
- recurrent RVM foreground and alpha inference off the main thread
- all four recurrent outputs are passed into the next frame and reset on camera changes
- selectable Fast 640×360 and Quality 1280×720 inference profiles
- automatic Apple Vision fallback if RVM cannot be loaded
- GPU display and compositing through a Metal compute shader
- Original, Alpha Matte, Foreground, and Composite display modes
- black, white, gray, and checkerboard backgrounds
- add/remove FX stack with Gradient Overlay, Historical Trail, Liquid Distortion, Live Video Fill, Skeleton, Lines, Line Sampler, and Particles
- named, persistent effect presets; the first preset is restored automatically at launch
- rolling capture/processed FPS, inference, render, latency, and dropped-frame metrics
- explicit matting reset and automatic reset on camera change
- automatic borderless processed output on the first external display, with controls kept on the operator display

## Build and run

Requirements: macOS 14 or newer, Xcode 15.3 or newer, and a Metal-capable Mac. The project was compile-tested with Swift 6.2.1 / Xcode 26.1 on Apple Silicon.

```sh
chmod +x scripts/build-app.sh
scripts/build-app.sh
open .build/DanceFX.app
```

The build script compiles the checked-in `.mlmodel`, embeds the resulting `.mlmodelc`, and ad-hoc signs the app. The first launch asks for camera access. If access was previously denied, enable **DanceFX** under System Settings → Privacy & Security → Camera. Use the packaged app rather than `swift run`; the latter does not contain the compiled model resource or camera privacy metadata.

The app defaults to **Fast 360p**. The Metal compositor scales its foreground and alpha output to the full preview size. Select **Quality 720p** from the RVM picker when edge detail matters more than frame rate. Switching profiles creates a fresh engine and resets temporal state.

The processed stream always appears in a separate borderless, full-screen output window. With no external display, it fills the primary display as a local preview and the control panel floats above it. Connect a projector as an extended display before or after launching DanceFX and the output automatically moves to the first display other than the macOS menu-bar display, leaving only the controls and metrics on the operator display. Disconnecting the projector moves output back to the primary display. Use **Refresh Displays** if macOS has not yet announced a display change.

The floating control panel uses a dark theme and can be resized down to a compact palette. Control rows wrap responsively as width decreases, and the whole panel scrolls vertically so horizontal scrolling is unnecessary. Choose **View → Control Panel → Toggle Transparent Background** to remove or restore its window background while keeping the controls visible. The panel's position, size, and transparent-background setting are restored across app restarts.

The built-in Mac camera is mirrored for natural, mirror-like movement. External webcams and capture devices are projected without horizontal mirroring. This changes automatically when the selected camera changes.

## Effects

Effects are independent and can be enabled together. They are applied only in Foreground and Composite modes; Original and Alpha Matte remain clean diagnostic views.

Each active effect appears as a clearly bordered card with a prominent title header. The card contains only that effect's parameters, while ordering and removal controls remain in its header.

Choose **Randomize** to clear the current stack, select a random non-empty subset of the available effects in random order, and randomize all effect parameters within their supported control ranges. Stateful trail and particle data is cleared before the new stack is applied.

Use **Add Effect** to add an available effect to the stack and the remove button on a row to take it out. The arrow buttons reorder the top-to-bottom INPUT → OUTPUT pipeline. Compatible effects later in the list process output generated earlier; for example, placing Particles above Gradient Overlay or Live Video Fill colors the particles, while placing Particles last keeps them white. Liquid Distortion after Particles warps their positions. Enter a name and choose **Save Preset** to persist the ordered effect list and all of its parameters. Choosing another preset applies it immediately. The first saved preset is loaded whenever DanceFX starts.

**Gradient Overlay** clips a three-color gradient to the current person matte. Choose Neon, Sunset, or Ice and adjust opacity and direction.

**Historical Trail** captures the complete signal arriving at its position in the effect stack, including generated Skeleton and Particle pixels, rather than cloning only the camera matte. It excludes its own prior output to avoid recursive feedback. Samples controls the maximum number of visible snapshots, Snapshot controls the capture interval, and Lifetime expires old snapshots in seconds. Each older sample accumulates the configured aspect-correct rotation, bounded scale, and X/Y translation. Trail opacity controls the newest historical layer and Trail decay progressively fades older samples. Normal, Add, Screen, and Lighten blend modes are available. Samples stay GPU-only, use a reusable texture pool, and are stored at half preview resolution to bound memory and bandwidth.

**Liquid Distortion** animates an aspect-correct two-axis wave through both the live silhouette and historical snapshots. Strength controls displacement, Scale controls the size of the ripples, and Speed controls animation rate.

**Video Fill** loops selectable footage through the signal. Its Video picker is populated automatically from `.m4v`, `.mov`, and `.mp4` files in `Assets`; the build script packages every supported movie in that folder. The included choices are Explosions, Flowers, and Liquids. Opacity blends the selected footage with the camera foreground, Zoom changes texture framing, and Speed adjusts playback. Trail timing follows stack order: Video Fill before Historical Trail freezes the movie frame into each snapshot; Video Fill after Historical Trail fills all replayed trails with the current movie frame. Add another supported movie to `Assets` and rebuild the app to make it available in the picker.

**Clap Explosions** starts a copy of the bundled explosions video whenever two detected palms meet. The contact point stays fixed for that explosion, while later claps can start additional overlapping copies. Size, opacity, and blend mode are available in the effect controls. Edit `ExplosionSegment.clips` in `Sources/DanceFX/Rendering/ClapExplosionPlayer.swift` to set each clip's start frame and duration in frames (the video runs at 30 fps); claps cycle through the list. The included starts are frames 248, 500, 1002, 1255, and 1505, with a duration of 240 frames (8 seconds) each. Separate the hands before clapping again.

**Skeleton** runs Apple Vision body-pose detection independently from RVM and draws confidence-filtered white lines through the detected face, torso, arms, and legs. Pose inference is throttled to every second camera frame and coordinates are smoothed before rendering.

**Particles** can spawn from Limbs or Shape Border. Limbs uses the body pose to emit outward from both ankles, detected fingertips (falling back to wrists), and a forehead point; its Rate is per emitter. Shape Border samples random outward-facing points around every silhouette in the segmentation matte, naturally supporting multiple people; its Rate is the total emission rate. The border scan is limited to roughly 160×90 samples and disables particle-only hand-pose detection. Lifetime supports up to 10 seconds and Base Size up to 40 px. Motion Size increases birth size according to measured joint velocity, while Momentum transfers tracked limb velocity to new particles so fast gestures can throw them across the frame. Speed and Spread shape the initial burst, positive or negative Gravity pulls particles down or up, Drag slows them over time, and End Size makes them shrink, hold, or grow over their lifetime. Disc, Ring, Square, Diamond, and Spark shapes are rendered in the existing point-sprite shader. These controls reuse the same simulation and GPU draw call, with a 2,000-particle safety ceiling.

**Lines** turns every confident skeleton position into a moving geometric mesh. Each point connects to its nearest neighbors, with duplicate edges removed, so the tracked pose produces triangles and polygonal shapes without being constrained to anatomical bones. Geometry only hides the camera foreground so just the generated mesh and other explicit generated effects remain. Links / point controls mesh density, Thickness controls the rasterized width, and Opacity and Confidence control appearance and tracking. Like Particles, Lines begins white but is filled by any Gradient Overlay or Video Fill placed after it in the stack. Its Normal, Add, Screen, and Lighten blend modes control how the filled geometry composites over earlier layers. When added to a stack that already contains Historical Trail, Lines is inserted immediately before it so the geometry is captured by the trail; it can still be reordered afterward.

**Line Sampler** uses a black 16:9 pad in its effect card. Drag from A to B to add a line, or drag a white endpoint to adjust one. Up to 16 lines can remain active; each can be deleted individually, and Clear all removes them together. Every rendered frame samples a narrow strip of the live composited image along each line and streams successive strips perpendicular to it. A → B defines the left and right sides. Shared controls set direction (Both, Left, or Right), speed, editable retained sample count, sampling thickness, opacity, fade, and Normal/Add/Screen/Lighten overlay mode. Stored rows use fixed geometric spacing, so frame-time fluctuations cannot expand or contract the rendered block. Each line also carries per-line MIDI note settings, an overridable MIDI channel (taking a channel swaps with its current owner so routes stay unique), and a Visibility opacity; lines are hidden on the output until Visibility is raised, while the editing pad keeps a dashed guide so they stay selectable. Newly drawn lines inherit every setting from the previous line. Each MIDI line runs in **Rhythm** mode (it retriggers its note on every rhythm-grid tick while the segment has pixels) or **Single Shot** mode (it holds one note for as long as the segment keeps pixels, releasing when it empties). Every line sits in its own bordered box. The card is grouped into Lines, Sampling, and MIDI Output sections. Lines and their shared settings are saved in effect presets. Older seconds-based presets are converted to sample counts when loaded. The sampler draws over the live effect output before Clap Explosions.

The default FX values mirror the reference setup: Neon gradient at 72% and 83°; 15 historical snapshots with 3° rotation, −1.5% scale, 1.5% X, 0.4% Y, 50% opacity, and 0.96 decay. The app starts in Composite mode on black with Fast 360p RVM.

To validate model loading and one recurrent state cycle without a camera:

```sh
xcrun swift scripts/smoke-rvm.swift \
  .build/DanceFX.app/Contents/Resources/rvm_mobilenetv3_1280x720_s0.375_fp16.mlmodelc
```

Append `cpu-gpu` or `cpu-ne` to compare another Core ML compute-unit selection.

## Runtime pipeline

```text
AVCaptureDevice → CVPixelBuffer → serial recurrent RVM inference
                → foreground + one-channel alpha CVPixelBuffers
                → IOSurface/Metal textures → compute compositor → MTKView
```

There is no image encoding, `NSImage`, `CGImage`, or CPU per-pixel compositor in the frame path.

## RVM model signature

The Quality model is the [official upstream release](https://github.com/PeterL1n/RobustVideoMatting/releases/download/v1.0.0/rvm_mobilenetv3_1280x720_s0.375_fp16.mlmodel), version 1.0.0, SHA-256 `b1b60ff93d57ba4c3c0eeedd1d38590ccbd498144d4ddcdaf8624dbe69e901ad`. The Fast model was exported from the official checkpoint with the upstream Core ML exporter at 640×360, `downsample_ratio=0.5`, and FP16 weights; its SHA-256 is `623c512022b26ea2b094a653db037c13302bbc9e7cb70f769d7d82a5721c18de`.

Both models' Core ML metadata declares FP16 compute precision and an Apache License 2.0 model license. The upstream source repository is GPL-3.0, and its license is included in `Vendor/RobustVideoMatting-LICENSE.txt` and the packaged app.

The signature was inspected with `xcrun coremlcompiler metadata`:

- `src`: 1280×720 RGB image
- `r1i`: optional Float32 `1×16×135×240`; initial value is all zeros
- `r2i`: optional Float32 `1×20×68×120`; initial value is all zeros
- `r3i`: optional Float32 `1×40×34×60`; initial value is all zeros
- `r4i`: optional Float32 `1×64×17×30`; initial value is all zeros
- `fgr`: 1280×720 RGB foreground image
- `pha`: 1280×720 grayscale alpha image
- `r1o`…`r4o`: recurrent outputs mapped directly to the corresponding next-frame inputs

The Quality model bakes in `downsample_ratio = 0.375`; the Fast model bakes in `0.5`. Initial recurrent inputs are optional and are omitted on the first frame, invoking their declared zero initialization. Every later prediction receives the previous four outputs.

The development-only Fast model conversion is reproducible with:

```sh
chmod +x scripts/export-fast-model.sh
scripts/export-fast-model.sh
```

It creates an isolated Python environment under `Tools/RVMExport/.venv`. Python is not packaged with or required by DanceFX.

## Performance and quality

The camera-free recurrent smoke test on the development MacBook Pro with M1 Pro measured approximately 36 ms for Fast 360p and 103 ms for Quality 720p. Fast mode uses `MLComputeUnits.all`, which tied CPU + GPU in the short synthetic comparison and leaves Core ML free to schedule supported operations. These are synthetic measurements; live FPS and latency must be recorded from an interactive camera run. Run at least 10 minutes with rapid arm motion, spins, hair movement, entrances/exits, and two people crossing before treating the prototype as validated.

If the app reports “Apple Vision fallback active,” rebuild with `scripts/build-app.sh` and launch the packaged app. Vision's fallback mask is lower-quality and stateless.

## Next recommended improvements

1. Benchmark `.all`, `.cpuAndGPU`, and `.cpuAndNeuralEngine` on the target M1.
2. Add UI controls for the already-supported shader parameters: threshold, edge softness, and alpha gain.
3. Reuse a persistent fallback alpha texture if an output pixel buffer cannot be mapped directly to Metal.
4. Add Instruments signposts around capture, Core ML, and Metal stages.
5. Validate 720p for 10 minutes before trying the official 1080p model.
