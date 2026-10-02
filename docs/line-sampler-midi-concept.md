# Line Sampler MIDI: implementation handover

Status: concept, no feature code implemented. The user confirmed composite-image pixel detection, root per line, 3/16 as one tick every three sixteenths, and segmented lines/labels on both the editor pad and projector output.

## Goal

Each Line Sampler line becomes a playable, segmented MIDI controller while retaining its current visual sampling effect. An occupied segment plays its assigned note on that line's rhythmic grid. All lines share one continuous BPM clock. Presence gates notes; it never starts or resets the clock.

## Existing behavior and integration points

- `SampleLine` in `Sources/DanceFX/Rendering/EffectPreset.swift` currently stores only UUID and normalized A/B coordinates. `EffectPreset` stores the array as `sampleLines`.
- `SampleLinePad.swift` draws and edits up to 16 lines on a 320 × 180, 16:9 black pad. `ContentView.swift` currently gives each line only a Delete button and puts sampling controls below the list.
- `AppController.swift` publishes the line array, saves/loads it with presets, and forwards it to `MetalRenderer`.
- `MetalRenderer.encodeLineSampler` copies the pre-sampler composite, captures a 512-pixel strip per line per rendered frame, and composites the histories. It currently recreates a line's GPU history when the entire `SampleLine` value changes. Once MIDI fields are added, compare geometry separately so editing a scale or visibility does **not** erase visual history.
- No Core MIDI output, musical transport, or note ownership exists yet.

## Proposed interaction

The Line Sampler card gets one numeric **BPM** control, shared by every line, and a compact settings panel under each line. Keep the existing global visual-sampler controls (stream direction, pixel speed, sample count, sampling thickness, opacity, fade, blend) separate from the new per-line musical controls.

| Per-line control | Behavior | Proposed initial value |
| --- | --- | --- |
| Generate MIDI notes | Enables/disables MIDI for this line. Turning it off stops its sounding notes immediately. Visual sampling and line drawing continue. | Off for old and new lines |
| MIDI channel | Identifies this line to an external host, allowing the host to route lines to different instrument tracks. Assign a stable channel 1...16 automatically per line; show the assigned channel in the row and allow an override. Choosing a channel already owned by another line swaps the two so channels stay unique. | Auto |
| Scale | Determines the ordered pitch offsets and therefore the segment count. Start with Chromatic, Major, Natural Minor, Major Pentatonic, Minor Pentatonic, and Blues; use named definitions, not free-form offsets in the first version. | Chromatic |
| Root note / key | A per-line note-class picker (C through B) turns scale degrees into absolute MIDI pitches. | C |
| Octave | Determines the base octave; display MIDI note names using the convention C4 = MIDI 60. Clamp choices so every scale pitch stays in 0...127. | 4 |
| Rhythm | One interval per line, represented as an integer number of sixteenth notes: 1/16, 1/8 (= 2/16), 3/16 (= one tick every three sixteenths), 1/4 (= 4/16), etc. | 1/8 |
| Trigger mode | **Rhythm** retriggers the segment's note on every line tick while it has pixels. **Single Shot** holds one note for as long as the segment keeps pixels and releases it when the segment empties. | Rhythm |
| Visibility | 0...100% visual opacity of the source line, boundaries, and optional note labels. At **≤ 1%**, draw none of those elements. This does not mute MIDI. | 0% (hidden until set) |
| Show notes | Draw each segment's note name at its center when the line is visible. This affects display only. | Off |

Show all line settings in an expandable row keyed by the line UUID. Keep the A/B endpoint handles usable even when visibility is ≤ 1%, for example by retaining a selected-line edit affordance in the control pad; the projected overlay should obey visibility strictly. A line can also be deleted from its row.

## Segment and visual rules

For a scale with `N` distinct offsets, divide the A→B line into exactly `N` equal-length sections. Degree 0 is nearest A; degree `N-1` is nearest B. A point at normalized distance `t` belongs to `min(N-1, floor(t × N))`. Draw `N-1` short perpendicular separators at boundaries and the main A→B line whenever visibility is **> 1%**. If Show notes is on, place labels near section centers and keep them legible on short or crowded lines (e.g. suppress overlapping labels on the small editor pad while preserving MIDI behavior).

Suggested Blues offsets: `[0, 3, 5, 6, 7, 10]`, giving six sections. Chromatic has 12. Scale selection changes the section count immediately and stops any now-invalid notes. Do not duplicate the octave tonic at the B end; that would create an extra section.

Draw the source lines in both the editor pad and the projector/output overlay after visual sampling and MIDI occupancy have been computed. This prevents drawn lines, separators, and labels from feeding back into the Line Sampler's own pixel detection.

## Pixel presence

Detect **visible nonblack pixels in the Line Sampler's input image**: the pre-sampler composite that `encodeLineSampler` already copies into `sampleSourceTexture`. This deliberately allows video fills, particles, trails, skeleton lines, and other upstream visual effects to play notes. Do not detect from the Line Sampler's own outgoing history or the proposed line overlay. This avoids self-triggering while preserving the effect-stack semantics.

For each segment, sample a narrow strip centered on that segment, using the existing Sampling thickness (or a fixed small detection width if that setting is meant to remain visual-only). A segment is occupied when enough samples exceed a small luminance threshold, rather than when any single pixel flickers. Use distinct on/off occupancy thresholds or a short hold to suppress edge jitter. Expose a threshold control later only if live tests show a need. If no fresh camera/composite frame arrives within a short timeout, treat all segments as empty and release sounding notes. The line pad and projector coordinate mapping must match the existing normalized A/B mapping.

Because the current output composite is opaque, a white, gray, checkerboard, or bright video background can hold many/all segments active continuously. This is a consequence of the selected source behavior, not a detector bug. Default black background is the cleanest setup for sparse triggering. If live use needs foreground-only notes later, add a separate source selector rather than silently changing the meaning of visible pixels.

Do not synchronously read the full composited Metal texture back to the CPU. Add a small GPU pass that samples only the line strips from `sampleSourceTexture`, reduces them to at most 16 per-line occupancy bitsets (12 bits per Chromatic line), and transfers that compact result asynchronously through a reused ring of small buffers. The transport consumes the newest completed result. Keep the existing visual capture path unchanged.

## Timing and MIDI behavior

- Add one shared monotonic transport with numerical BPM, suggested range 30...240 and default 120. `quarter-note seconds = 60 / BPM`; `sixteenth seconds = 15 / BPM`.
- Start the transport when Line Sampler MIDI is enabled or when the first MIDI line becomes active. All line intervals are anchored to the same transport origin. A 3/16 line fires on sixteenth-grid indices 0, 3, 6, ...; a 1/8 line fires on 0, 2, 4, ... . Presence changes never reset phase. Changing BPM updates future beat spacing without restarting musical phase.
- At each line tick, read the latest occupancy bitset. For each occupied section, send Note On for its pitch; for each empty section, send nothing. Thus a persistently bright section causes repeated notes on successive ticks and a newly bright section waits for the next tick. Multiple occupied sections can form a chord.
- Send a matching Note Off before the next tick, provisionally after 50% of that line's interval. This fixed gate makes repeated notes distinct and bounds stuck-note risk; make gate length configurable only if musical testing calls for it. A vanished segment does not cancel a note already sounding mid-gate. Disabling/deleting a line, changing its scale/root/octave, losing output, stopping transport, or quitting sends immediate Note Off for that line's active notes.
- Notes must have ownership by line UUID and segment index. Assign each line a stable MIDI channel on the shared virtual source. Up to 16 lines fit MIDI 1.0's 16 channels; the receiving host can route each channel to a different instrument track. Channel 10 is commonly treated as percussion by General MIDI instruments, so document that caveat and permit remapping or a separate virtual endpoint if the selected host makes it necessary. A Note Off on one line must never silence the same pitch on another line.
- Send MIDI 1.0 Note On/Off via Core MIDI. Expose a named DanceFX virtual MIDI source that a DAW/synth can subscribe to; an optional destination picker for hardware or existing virtual ports can follow. VST hosting is outside this feature. Use one fixed velocity at first; pixel brightness/area-to-velocity mapping is a later option.
- Run transport scheduling and MIDI dispatch away from the Metal render thread and SwiftUI main thread. Reuse the latest compact occupancy state; never wait for video inference at a beat boundary.

## Data and migration

Extend `SampleLine` with Codable fields for MIDI enabled, MIDI channel (or an auto-assignment marker), scale identifier, root, octave, rhythm numerator in sixteenths, visibility, and Show notes. Decode missing keys to the defaults above so existing saved presets keep their coordinates and visual behavior. Add BPM to `EffectPreset` with a default of 120. Save all new values with presets. If future versions rename scale identifiers, preserve a stable raw identifier in preset data. Preserve channel assignments by line UUID when lines are reordered; release a channel only when its line is deleted.

Keep transient state out of presets: current transport phase, occupancy, scheduled Note Offs, MIDI endpoint references, and active notes. On preset load, send Note Offs for prior line states, then apply the new settings without creating surprise Note Ons until the next scheduled tick.

## Performance guardrails

At 16 lines and chromatic scale there are at most 192 occupancy sections. Limit sampling to a small fixed number of points per section or one reduced strip per line. Reuse the already-copied pre-sampler texture and avoid a new vision pass, full-frame CPU conversion, per-pixel Swift loops over the output image, or blocking GPU readback. MIDI scheduling should operate on bitsets and a small event queue. Bound how many ticks can be caught up after a stall; skip old ticks rather than burst stale notes. Measure added camera-to-MIDI latency and frame time on the development Mac, including 16 lines at 240 BPM.

The current renderer's history reset check must switch from full-struct equality to A/B geometry equality once `SampleLine` grows. Otherwise moving a visibility slider or changing rhythm would allocate fresh history textures and visibly wipe the visual sampler.

## Suggested implementation order

1. Add per-line settings, scale definitions, preset migration, BPM input, and segmented editor drawing. Preserve existing visual sampling.
2. Build pre-sampler-composite occupancy for the line sections with coordinate tests, thresholding, asynchronous compact readback, and stale-frame release.
3. Add one shared transport and a testable pure tick-to-note state machine. Verify phase continuity when occupancy changes and correct 3/16 versus 1/8 timing.
4. Add Core MIDI virtual output and note cleanup for every disable/delete/preset/device lifecycle path.
5. Add projector line overlay after sampling, live latency/frame-time checks, and `.app` build via `scripts/build-app.sh`.

## Acceptance checks

- A six-note Blues line shows six equal sections and five separators; a Chromatic line shows twelve sections and eleven separators. Reversing A/B reverses note order spatially.
- Visibility 0% and 1% hide the source line, separators, and labels. Visibility 2% draws them. MIDI continues at all three values if enabled.
- Show notes changes labels only. The selected octave and root produce the expected MIDI note numbers.
- With a section continuously occupied, it sends one note at every scheduled line tick and one corresponding Note Off per Note On. Empty sections send no notes. Entering/exiting a section between ticks never restarts the transport.
- At 120 BPM, 1/8 ticks are 250 ms apart and 3/16 ticks are 375 ms apart, on the same global phase. A BPM change preserves phase across all lines.
- Simultaneous lines, preset switching, disabling, deletion, camera loss, and app exit leave no stuck notes.
- In a host that supports channel-filtered MIDI tracks, line 1 can drive piano while line 2 drives another instrument simultaneously, without cross-triggering. GarageBand remains the one-instrument smoke test and should not be relied on for per-line channel routing.
- Existing presets open without migration errors; changing MIDI/visual line settings does not erase the existing sample history. The packaged `.app` builds successfully.
- Upstream bright pixels trigger even without a person; a white background continuously occupies sections; Line Sampler's own history and source-line overlay never self-trigger.

## Free piano test rig

GarageBand is already installed on the development Mac. After MIDI output is implemented, create a GarageBand **Software Instrument** track, choose a piano patch, keep that track selected, and receive from DanceFX's virtual MIDI source. GarageBand generally receives virtual MIDI on all channels without an input picker. First use GarageBand's on-screen Musical Typing keyboard to confirm that its piano audio works; then use a temporary DanceFX `Test Note` action (C4 / MIDI 60, Note On followed by Note Off) to isolate MIDI routing from visual detection. Remove or retain the action as a diagnostics control after the feature works. Do not require IAC when DanceFX already publishes its own Core MIDI virtual source.

For different instruments per line, use a host that can filter each track to one incoming MIDI channel, load a separate instrument on each track, and monitor those tracks simultaneously. GarageBand's all-channel input behavior makes it a poor validation host for this requirement. Waveform Free is a candidate free VST3 host; verify its channel-filtered track setup with two lines before making it the documented test environment.

For MIDI diagnostics, Snoize MIDI Monitor is free. Subscribe to the DanceFX virtual source and inspect pitch, channel, Note On/Off pairs, and timestamps. It produces no piano audio, so run it beside GarageBand. A free standalone alternative is Plogue sforzando, which needs a piano SFZ/SF2 bank; GarageBand is the shortest path because it is installed and includes piano sounds.

Live exercise: set DanceFX to a black background, one line across the moving subject, Generate MIDI on, C4 root, Blues scale, 120 BPM, and 1/8 rhythm. The line must show six sections. Hold a bright part of the image over one section: the same piano note should repeat every 250 ms. Leave the section: notes stop at the next tick, with no hanging voice. Move across sections to hear the six pitches. Change rhythm to 3/16 and expect 375 ms spacing without a phase restart. Add a second line to confirm both share BPM. Then switch to a white background: continuous triggering is expected under the selected nonblack-pixel rule.

For repeatable timing checks, feed a fixed bright test pattern into the pre-sampler composite or isolate the occupancy-to-MIDI pipeline with a synthetic bitset. Record MIDI Monitor event timestamps to distinguish clock drift from camera/GPU detection delay. Verify stop, disable, delete, preset load, and app exit each produce matching Note Offs. Also inspect frame-time metrics with one and sixteen lines.

References: [GarageBand for Mac](https://apps.apple.com/us/app/garageband/id682658836?mt=12), [Apple on virtual MIDI input in GarageBand](https://support.apple.com/en-mt/guide/logicpro/lgcpd48f11ad/mac), [Snoize MIDI Monitor](https://www.snoize.com/MIDIMonitor/), and [Plogue sforzando](https://www.plogue.com/products/sforzando.html).

## Confirmed product decisions

- Occupancy uses visible nonblack pixels in the pre-sampler composite.
- Each line has its own root note/key.
- A 3/16 rhythm ticks once every three sixteenth notes.
- Segmented lines and optional labels appear in both the editor pad and projector output.

👿 **Devil's advocate:** The weakest assumption is that visual occupancy will feel like intentional musical control. Fast rhythms may expose camera-frame latency, delayed GPU readback, and edge jitter, especially at 240 BPM, even when MIDI scheduling is precise. Bright backgrounds and upstream trails can keep notes firing indefinitely; users may need a black background or later a source selector. Validate the playing feel and frame-time cost before adding more controls.
