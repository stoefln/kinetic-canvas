# Audio instruments and tempo-synced loops: handover

Status: first native clip-player slice implemented (2026-10-06). Loops and one-shots play through a built-in AVAudioEngine + AVAudioUnitTimePitch path, so the plugin-host follow-up below is still a proposal. Updated 2026-10-06.

## Implemented first slice (2026-10-06)

The recommended first audio slice is in the app. A Line Sampler line now has a **Destination** of **MIDI**, **Loop**, or **One-shot**.

- `ClipAudioEngine` is a native `AVAudioEngine` player. Each loop has its own `AVAudioUnitTimePitch`; `rate` follows the preset BPM so loops stretch without changing pitch. One-shots use a small round-robin player pool.
- `MusicalTransport` is the single musical clock. The MIDI grid and the audio engine both read it; a BPM change is committed on the next bar line, so both change duration together. 4/4, sixteenth-note grid.
- Loops keep playing while muted and are muted with a short gain ramp, so the playhead keeps advancing and unmuting is phase-correct. A loop toggles on the next bar line; a one-shot fires on the rising edge of the line, quantized to the 1/16 grid when Quantize is on.
- Audio files are referenced in place (bookmark + path), not copied. A missing file shows a visible "File missing" state. Clips live on `SampleLine`, so they persist inside existing presets with no schema change.
- The editor shows each clip's file, source BPM, length in beats, level, start-muted state, and a live queued/playing/muted badge.
- Known limits of the slice: a device change restarts active loops at phase 0; files are decoded fully on load (fine for typical loops, not for large one-shots); there is no shared reverb/delay yet; and preset load starts non-muted loops immediately rather than on the next bar.

Defaults chosen for the open decisions below: BPM changes at the **next bar**; a line's Loop mode **toggles** on each new visual entry; audio is **referenced in place** using bookmarks.

## Why this exists

Today Kinetic Canvas sends Line Sampler notes through Core MIDI to Waveform, which hosts Vital. Different sounds across Kinetic Canvas presets currently require separate Waveform projects or many loaded synth instances. The desired setup is roughly 16 available sounds with only about three sounding at once. A brief gap when changing an instrument preset is acceptable.

The user also wants prerecorded audio loops and individual drum hits. A line should be able to trigger a hit or toggle a loop on/off. All loops must share musical phase and **stretch to fit tempo changes without changing pitch**. A drum sampler may need reverb and delay, but adding a plugin host or replacing Waveform should be justified by an actual need.

## Current implementation and AU boundary

- `AppController.sampleBPM` is an editable 30–240 BPM value and is saved as `EffectPreset.sampleBPM`.
- `MusicalTransport` is shared by `LineSamplerMIDI` and `ClipAudioEngine`; the latter already owns an `AVAudioEngine` for built-in loops and one-shots. Verify their alignment under load before treating it as finished.
- MIDI lines send notes through either a virtual port per line or one shared port with channels. Audio lines play clips in the app. There is **no hosted third-party AU instrument, Vital state capture, or AU effect chain** yet.
- Kinetic Canvas does not send host tempo to Waveform. The proposed AU host would use the existing in-app BPM and transport.
- `docs/line-sampler-midi-concept.md` documents the existing MIDI feature and its history; this document covers the proposed audio work.

## Confirmed requirements and preferences

1. Keep Vital as the synth. Switching a Vital sound with a short interruption is acceptable. Avoid keeping one Vital instance loaded for every possible sound; target only the simultaneously needed instances.
2. Make sound selection follow Kinetic Canvas presets eventually, so a different Waveform project is unnecessary for each visual preset.
3. For audio, import prerecorded WAV/AIFF loops. Allow a line to toggle a loop and keep all loops in sync. Allow lines to trigger individual hits.
4. Tempo may change and loops must stretch to the new BPM while retaining pitch. Mere MIDI clock sync, retriggering, or varispeed that alters pitch does not satisfy this.
5. Prefer the smallest reliable setup. A built-in audio path that removes the Waveform dependency is attractive, but is a proposal rather than an agreed implementation decision.

## First audio slice design and remaining validation

The native clip player described here is implemented as the first slice; the acceptance checks below are still needed before treating its timing and stretch quality as validated. Use the existing preset BPM as the sole tempo value in Kinetic Canvas. Store each loop's original BPM and musical length (beats or bars). For a loop, the nominal stretch ratio is `current BPM / original BPM`; calculate exact phase from the common musical timeline, not from wall-clock time since the last trigger.

Suggested line destination choices in the editor: **MIDI**, **Loop**, and **One-shot**. MIDI keeps existing behavior. Loop and One-shot choose an imported audio file. A rising edge of the line's visual trigger requests the action, so a continuously occupied segment does not toggle repeatedly. For the first version, schedule a loop toggle at the next bar boundary; schedule a one-shot on the existing sixteenth-note grid or immediately, according to the line's quantize setting. The UI should show whether a loop is queued, playing, or muted.

All loops share one beat/bar position. When a loop is muted, its **logical** playhead keeps advancing. It need not consume a stretch processor or mix audio while silent. On unmute, begin at the position corresponding to the shared timeline, with a short gain ramp to avoid a click. This makes independently toggled loops remain in phase and avoids the CPU cost of processing every available loop. Keep file data ready for the next queued start, but bound memory: decode or stream based on file size rather than permanently loading the entire loop library.

Apply a BPM change on a defined musical boundary, initially the next bar. The currently audible loops must transition to the new duration together. A short fade or transition gap is acceptable, but audible drift between loops is not. Do not assume the existing `DispatchSourceTimer` MIDI tick is accurate enough to schedule audio buffers. Introduce a single musical transport state that both MIDI and the audio engine read, with audio events scheduled against the audio render clock. Preserve musical phase when BPM changes; verify MIDI and audio stay aligned.

Pitch-preserving stretching is the main feasibility gate. Prototype Apple's [`AVAudioUnitTimePitch`](https://developer.apple.com/documentation/avfaudio/avaudiounittimepitch) with representative drum and melodic loops and live BPM changes. Apple's documentation describes independent rate and pitch controls, but its quality, latency, real-time behavior, and CPU cost in this specific clip-player design are **unverified**. If it fails the test, evaluate an established stretch library or a focused AU looper. Do not build a custom DSP stretch algorithm as the first step. `AVAudioUnitVarispeed` alone is unsuitable because rate changes also alter pitch.

### Minimum controls and preset data

| Scope | First version |
| --- | --- |
| Global | BPM, time signature fixed at 4/4 initially, transport phase, loop quantization at next bar |
| Per loop | Audio file reference, source BPM, musical length, level, assigned line, optional start-muted state |
| Per one-shot | Audio file reference, level, assigned line |
| Per line | Destination type and trigger action; preserve current MIDI settings when MIDI is selected |
| Preset | Line routing and clip references; existing BPM remains the tempo value |

Store audio references in a way that survives app restart and moving a preset between machines; decide between managed copies and external file bookmarks before implementing persistence. Missing files must show a visible, recoverable state rather than silently playing nothing. Preserve decoding of existing presets with no audio fields.

## Instrument and effects follow-up

Native loop playback does **not** itself switch Vital presets. A later AU-hosting slice could keep approximately three Vital instances for the concurrent synth lines, save each instrument's AU state in the Kinetic Canvas preset, and restore that state on preset changes. First test whether Vital AU state restoration is fast and reliable enough; the earlier sandboxed probe was inconclusive. Stop notes and apply a short fade around a state swap to avoid stuck voices and clicks. General plugin hosting adds UI, state migration, crash handling, and CPU/memory costs, so it should follow a successful clip-player prototype.

### Audio Unit implementation instructions: Vital first

This is a proposed **Vital-only instrument host**, not a general plugin browser or effect rack. On the development Mac, Vital is installed at `/Library/Audio/Plug-Ins/Components/Vital.component`; discover the registered component at runtime instead of hard-coding its file path or component IDs. The project targets macOS 14 in `Package.swift` and already links AVFoundation.

1. **Prove one instance works.** Use [`AVAudioUnitComponentManager`](https://developer.apple.com/documentation/avfaudio/avaudiounitcomponentmanager) to find the registered Vital music-device component (`kAudioUnitType_MusicDevice`), and show a clear “Vital AU unavailable” message if it is absent. Instantiate it asynchronously with [`AVAudioUnit.instantiate`](https://developer.apple.com/documentation/audiotoolbox/incorporating-audio-effects-and-instruments), attach/connect it to an `AVAudioEngine` mixer/output, and send C4 Note On/Off through [`AVAudioUnitMIDIInstrument.sendMIDIEvent`](https://developer.apple.com/documentation/avfaudio/avaudiounitmidiinstrument/sendmidievent%28_%3Adata1%3Adata2%3A%29) if the returned unit supports that interface. Verify audible output before changing preset data or line routing. Apple's [AU host sample](https://developer.apple.com/documentation/audiotoolbox/incorporating-audio-effects-and-instruments) is the API reference for discovery, graph setup, UI, and presets. Prefer integrating instrument nodes into the existing clip engine's audio graph after the smoke test, so one app audio engine owns mixing and output.
2. **Prove state round-trip.** Open Vital's editor using [`requestViewController`](https://developer.apple.com/documentation/audiotoolbox/auaudiounit/requestviewcontroller%28completionhandler%3A%29); on macOS this supplies an `NSViewController` when the plugin has a custom UI. Load or design two clearly different Vital sounds. Read the AU's [`fullState`](https://developer.apple.com/documentation/audiotoolbox/auaudiounit/fullstate) for each, persist the dictionaries losslessly (for example as validated property-list sidecars), then restore each state into **the same instance** after app restart. Check actual output and user edits, not just the displayed preset name. If Vital needs `fullStateForDocument` for reliable restore, test that alternative explicitly. Do not parse `.vital` files or rely on MIDI Program Change; Vital users report that Program Change is not implemented for patch selection ([Vital discussion](https://forum.vital.audio/t/switching-presets-for-live-use/9917)).
3. **Add only active synth slots.** Add **Vital AU** as a per-line destination beside MIDI, Loop, and One-shot. Its compact row should show the selected sound plus **Open Vital** and **Capture sound** actions; keep the full Vital editor in a separate window. Keep up to the required simultaneous Vital routes alive (initial target: three), rather than one instance per saved sound or Kinetic Canvas preset. Associate each active slot with a stable line/route ID; if a preset asks for more simultaneous AU routes than available slots, show a clear capacity error instead of silently reassigning a sounding line. Store a lightweight reference to a captured AU state in each Kinetic Canvas preset; keep the state blob in a versioned sidecar, with the component description and a human-readable sound name. Missing plugin/state should leave that line silent and visible as an error while other routes continue. Decode old MIDI-only presets unchanged.
4. **Switch a slot safely.** On a Kinetic Canvas preset change, stop and account for outstanding notes on that slot, ramp its mixer gain down, apply the new state from a serialized control queue (never the render callback or Metal frame path), then ramp up and allow new notes. Reuse the instance; do not destroy/recreate it for every sound change. Measure the actual interruption and confirm that tails, stuck notes, and simultaneous slot changes behave acceptably. No need to promise a seamless swap: the user accepts a brief gap.
5. **Route line MIDI directly.** For lines set to a hosted Vital destination, send their existing note/CC events to the matching AU instrument instead of looping them through a Core MIDI virtual port. Keep the existing external MIDI destination for Waveform and other hosts. Preserve per-line note ownership and release rules. Decide whether Vital's modulation CC bindings should be captured as part of its saved state; verify with a round-trip test.
6. **Test under the real workload.** Compare three hosted Vital instances against the current Waveform setup while the camera, Fast 360p model, Metal effects, and two stretched loops run. Measure app/host memory, CPU, audio underruns, preset-swap gap, and note latency. Test restart, unavailable Vital, device change, repeated preset switching, and mixed AU/MIDI/Loop/One-shot lines. Only expand to arbitrary AU instruments or AU reverb/delay if the Vital-only path proves useful and the native audio path cannot meet a specific need. Build the `.app` after source changes.

The key technical gate is **step 2**: if Vital does not reliably restore its AU state into a reused instance, the low-memory preset-switch design is not viable as proposed. At that point, reassess a small pool of preloaded instances or a host-side preset mechanism before adding more UI.

**Implemented (2026-10-06).** The Vital-only host is in the app. `InstrumentHost` discovers the registered music-device component, hosts up to three instances out-of-process in the shared clip engine, routes line notes/CC to them, and captures/restores `fullState` through versioned property-list sidecars under `Application Support/Kinetic Canvas/AU States/`. A line destination **Vital AU** shows the selected sound plus **Open Vital** and **Capture sound**; the full editor opens in a separate window. Lines with a hosted destination route their existing note/CC pipeline to the AU instead of a Core MIDI port; MIDI, Loop, and One-shot are unchanged, and old MIDI-only presets decode as before.

Machine-verified on this Mac: Vital's bundle is x86_64-only, so in-process instantiation fails (`OSStatus -1`) and **out-of-process** hosting is required (`AVAudioUnit.instantiate` with `.loadOutOfProcess`), which the engine accepts as a normal node. `fullState` is property-list serializable and the sidecar round-trips losslessly. A self re-set of `fullState` changes exactly one field, `settings.sample.samples` — Vital re-encodes its sample/wavetable blob — while every synth parameter, macro, and tuning value is preserved. **The audible fidelity of that re-encode is the remaining part of the step 2 gate and still needs a by-ear check** with two clearly different sounds.

For drum hits, start with the same native one-shot player. Add a simple shared reverb/delay only if dry samples sound inadequate in a live trial. A full per-line effect rack and arbitrary AU effects are out of the first version. If native stretching proves unsuitable, a focused AU such as [Loopmix](https://audiomodern.com/shop/plugins/loopmix/) can be tested: its [manual](https://d3jxl5cc6pcqb4.cloudfront.net/Manuals/Audiomodern_Loopmix_User_Manual.pdf) describes imported samples, host sync, track mute, and MIDI mapping. Verify dynamic tempo changes, independent loop toggles, MIDI mapping, and phase behavior in a trial before relying on it. Its six-track design and creative sequencer may be more than this project needs.

[SooperLooper](https://sonosaurus.com/sooperlooper/doc_sync.html) is **not** a solution for this requirement: its own sync documentation says it does not time-stretch loops to follow external tempo changes.

## Prototype and acceptance gate

1. Use three representative user loops at different original BPMs: a sharp drum loop, a sustained/melodic loop, and a longer phrase. Include one one-shot. Test at 80, 120, and 150 BPM and change BPM while two loops play.
2. Toggle each loop independently and repeatedly. Starts and stops land on the intended bar; unmuted loops resume at the shared phase without a doubled downbeat, click, or accumulated drift.
3. Change BPM in both the UI and via preset load. Verify all active loops transition together and their pitch stays recognizably stable. Check line MIDI notes against loop downbeats.
4. Measure audio glitches, audio callback time, app CPU, resident memory, and camera/render frame time with three active loops and a larger library of inactive files. Exercise the app's Fast 360p visual pipeline at the same time. Do not perform disk reads, decoding, allocations, or waits on the real-time audio render thread.
5. Verify missing files, device changes, preset switching, stop/start, and app quit. Existing MIDI-only presets must still work.
6. If source code is changed, build the packaged `.app` using `scripts/build-app.sh` so the result can be tested.

## Decisions still needing a human choice

- Should a BPM change take effect at the **next bar** (recommended first version) or immediately while a bar is playing? Immediate changes increase transition complexity and risk artifacts.
- Should a line's Loop mode **toggle** on each new visual entry or provide separate on/off gestures? Toggle is simple but can be surprising if noisy occupancy generates extra edges.
- Should imported audio be copied into a managed project/library or referenced in place? Managed copies make presets portable; references avoid duplicates.
- What stretch range is musically acceptable for the user's material? The broad 30–240 BPM control range is not a promise that every loop will sound good at every ratio.

## 👿 Devil's advocate

The weakest assumption is that one lightweight built-in stretcher will sound good on varied loops while the camera, Core ML, Metal renderer, and Vital run together. Stretch quality may fall apart on transients or at large BPM ratios, and audio latency may make MIDI alignment harder than the UI suggests. Keep the first slice to three active loops, benchmark under the actual visual workload, and be willing to use a focused third-party engine if the native prototype misses the quality or CPU target.
