# Audio instruments and tempo-synced loops: handover

Status: product direction and implementation proposal; no audio hosting or loop playback has been implemented. Updated 2026-10-06.

## Why this exists

Today Kinetic Canvas sends Line Sampler notes through Core MIDI to Waveform, which hosts Vital. Different sounds across Kinetic Canvas presets currently require separate Waveform projects or many loaded synth instances. The desired setup is roughly 16 available sounds with only about three sounding at once. A brief gap when changing an instrument preset is acceptable.

The user also wants prerecorded audio loops and individual drum hits. A line should be able to trigger a hit or toggle a loop on/off. All loops must share musical phase and **stretch to fit tempo changes without changing pitch**. A drum sampler may need reverb and delay, but adding a plugin host or replacing Waveform should be justified by an actual need.

## Current implementation

- `AppController.sampleBPM` is an editable 30–240 BPM value and is saved as `EffectPreset.sampleBPM`.
- `LineSamplerMIDI` owns a shared sixteenth-note clock for MIDI note scheduling. Its `configure` method adjusts the next tick when BPM changes, preserving its MIDI step phase. It does not provide an audio sample-clock transport or send host tempo to Waveform.
- Lines send MIDI through either a virtual port per line or one shared port with channels. The existing per-line modes generate notes or modulation CC; there is no audio-file or AU destination.
- No `AVAudioEngine`, AU instrument host, audio loop loader, time stretcher, or effect chain exists in the app.
- `docs/line-sampler-midi-concept.md` documents the existing MIDI feature and its history; this document covers the proposed audio work.

## Confirmed requirements and preferences

1. Keep Vital as the synth. Switching a Vital sound with a short interruption is acceptable. Avoid keeping one Vital instance loaded for every possible sound; target only the simultaneously needed instances.
2. Make sound selection follow Kinetic Canvas presets eventually, so a different Waveform project is unnecessary for each visual preset.
3. For audio, import prerecorded WAV/AIFF loops. Allow a line to toggle a loop and keep all loops in sync. Allow lines to trigger individual hits.
4. Tempo may change and loops must stretch to the new BPM while retaining pitch. Mere MIDI clock sync, retriggering, or varispeed that alters pitch does not satisfy this.
5. Prefer the smallest reliable setup. A built-in audio path that removes the Waveform dependency is attractive, but is a proposal rather than an agreed implementation decision.

## Recommended first audio slice

Build **one small native clip player** for prerecorded loops and one-shot samples before general AU hosting. Use the existing preset BPM as the sole tempo value in Kinetic Canvas. Store each loop's original BPM and musical length (beats or bars). For a loop, the nominal stretch ratio is `current BPM / original BPM`; calculate exact phase from the common musical timeline, not from wall-clock time since the last trigger.

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
