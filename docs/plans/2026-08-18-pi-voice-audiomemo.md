# pi-voice over audiomemo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development (recommended) or executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dictation in pi, driven by `audiomemo`. `audiomemo record --stream` grows a newline-delimited JSON stdout channel; a first-party `pi-voice` extension in `pi-nix` consumes it, renders partials and a VU meter into pi's TUI, pastes the finished text into the editor, and writes the voice state file that `agent-statusline`'s `voice` widget already reads.

**Architecture:** Every decision about devices, backends, formats, and secrets stays in audiomemo, where it is already tested. `--stream` is a flag on `record`, not a new subcommand and not an `argv[0]` symlink, so it composes with `-D/--device`, `-d/--duration`, `--format`, and `-t`. Go emits facts (`rms` in dBFS and normalised, raw partial text); TypeScript owns smoothing, colour, width, and layout, because pi pushes the render width and a live theme proxy into `render(width)` on every frame and neither survives a process boundary. The voice state file is the third leg: pi-voice writes it, `agent-statusline` reads it under both harnesses, so one implementation lights the mic indicator in pi and in Claude Code.

**Tech Stack:** Go 1.22 (audiomemo, stdlib plus its existing vendored deps), TypeScript on bun (`bun test`, no vitest, no npm), Nix flakes, bubblewrap via jail.nix, agenix.

This is phase 8 of the design in `docs/plans/2026-08-18-pi-nix-agent-stack-design.md` §18. It depends on phase 2 (`pi-nix` fork) for `lib/`, `extensionPackages`, and the passthru contract.

## Global Constraints

- **Two repos, plus a thin third.** Tasks 1-6 are `/home/joe/Development/audiomemo`. Tasks 7-11 are `/home/joe/Development/pi-nix`. Task 12 is `/home/joe/dotfiles`. Every **Files:** block names the repo.
- **Nothing about `record` without `--stream` may change.** The existing stdout contract (`transcribe $(record)` prints one path) and the TUI path are the regression gate. `go test ./...` covers both today.
- audiomemo is Go stdlib plus its vendored deps (`spf13/cobra`, `charmbracelet/*`, `gorilla/websocket`, `pelletier/go-toml`). `--stream` adds no dependency.
- The NDJSON stream is the only thing on stdout under `--stream`. Warnings that today go to stderr become `error` events. Subprocess stderr still reaches fd 2.
- pi-voice imports nothing. pi injects `@earendil-works/pi-tui` as a jiti virtual module at runtime (`src/core/extensions/loader.ts:50-74`), but `bun test` in the Nix check sandbox does not, and pulling pi-tui in for two width functions would need a bun2nix'd devDependency. The extension owns ~40 lines of width maths instead, under test. `agent-statusline`'s extension took the other road and now devDepends on `@earendil-works/pi-tui@0.84.2`; it needs far more of pi-tui than two functions, so the trade lands differently there. Keeping pi-voice dependency-free is what makes `checks.pi-voice-tests` a plain `bun test` with no network and no lockfile.
- Tests are `bun test` from `bun:test`. Copy the local `waitFor` helper from `/home/joe/Development/agent-statusline/extension/statusline.test.ts:8-22`; `bun:test` has no `vi.waitFor`.
- No secret reaches the Nix store or the process environment. Keys travel as `*_API_KEY_FILE` paths pointing at `/run/agenix/*`; audiomemo reads the files itself (`internal/config/config.go:145-172`).
- Go formatting is `gofmt`. Nix formatting in `pi-nix` is `pkgs.nixfmt` via `nix fmt`, not `nixfmt-rfc-style`.
- The system in every command below is `x86_64-linux`.

### Verified before writing this plan

Read from source and from live commands on 2026-08-18, not from documentation:

1. `ctx.ui.pasteToEditor(text: string): void` exists at `pi-coding-agent/src/core/extensions/types.ts:213`, next to `setEditorText` (`:216`) and `getEditorText` (`:219`). pasteToEditor is the right one: its doc comment says it triggers paste handling and collapses large content, and unlike `setEditorText` it does not discard what the user already typed.
2. `setWidget(key, factory, {placement})` mounts a component verbatim with no line cap and no sanitisation (`src/modes/interactive/interactive-mode.ts:2134-2174`); the `string[]` form caps at 10 lines. `setStatus` runs text through `sanitizeStatusText` (`src/modes/interactive/components/footer.ts:13-19`), which replaces `[\r\n\t]` with a space and collapses ` +` to one space. A VU bar is space-padded and a transcript row may contain runs of spaces, so neither goes through `setStatus`.
3. **Mic capture works inside bubblewrap.** Run on elphael: `bwrap --ro-bind /nix/store /nix/store --proc /proc --dev /dev --tmpfs /tmp --tmpfs "$HOME" --bind /run/user/1000/pulse /run/user/1000/pulse --setenv XDG_RUNTIME_DIR /run/user/1000 -- ffmpeg -f pulse -i default -t 1 ...` captured 32 KiB of audio and exited 0. No `/dev/snd` bind, no extra capability. jail.nix ships `pulse` and `pipewire` combinators that bind exactly these paths (`lib/combinators/pulse.nix`, `pipewire.nix`).
4. jail.nix's `base` permission does `--clearenv` and `--tmpfs ~` (`lib/combinators/base.nix`). `$HOME/.config/audiomemo/config.toml` and `$HOME/.claude` do not exist inside the jail unless bound. `--dev /dev` does provide `/dev/shm` as a tmpfs, so PulseAudio's shared-memory transport has somewhere to land.
5. `internal/voice/voice.go` does not read a bespoke state file. It reads the Claude Code settings layers and looks for a `voice` object. Task 8 reproduces its exact precedence.
6. ffmpeg's `astats` RMS arrives as dBFS and can be the literal `inf` or `-inf` (`internal/record/recorder.go:177`, `strconv.ParseFloat` accepts both). `encoding/json` returns `UnsupportedValueError` for `±Inf`, which would silently drop the whole event, so the wire values are clamped.

---

### Task 1: The NDJSON event schema and emitter

A new `internal/stream` package owning the wire format. Nothing in `cmd/` changes yet, so this task is pure addition with its own tests.

**Files:** (all in `/home/joe/Development/audiomemo`)
- Create: `docs/plans/2026-08-18-record-stream-design.md`
- Create: `internal/stream/event.go`
- Create: `internal/stream/emitter.go`
- Create: `internal/stream/emitter_test.go`
- Modify: `internal/transcribe/stream.go` (export the realtime backend name)

**Interfaces:**
- Consumes: nothing
- Produces:
  - `stream.StartEvent`, `LevelEvent`, `TextEvent`, `FinalEvent`, `ErrorEvent`, `EndEvent`
  - `func stream.NewEmitter(w io.Writer) *Emitter`
  - `(*Emitter) Start(StartEvent)`, `Level(rms, db float64)`, `Partial(string)`, `Commit(string)`, `Final(FinalEvent)`, `Error(scope string, fatal bool, err error)`, `End(EndEvent)`
  - `const transcribe.RealtimeBackendName = "elevenlabs"`

- [ ] **Step 1: Write the design note the repo's convention expects**

Every feature in `audiomemo/docs/plans/` has a design doc before an impl doc. Create `docs/plans/2026-08-18-record-stream-design.md`:

```markdown
# `record --stream` Design

Date: 2026-08-18
Status: Approved

## Goal

Give `record` a machine-readable stdout channel so a program can render the
live transcript and the mic level while recording, without scraping the TUI.
One JSON object per line, written as it happens.

## Why a flag

`--stream` composes with `-D/--device`, `-d/--duration`, `--format`, `-r`, `-c`,
`-n`, `--temp`, `-t`, and `--no-live-transcription`. A `recstream` symlink or a
`record stream` subcommand would have to redeclare all of them, and the argv[0]
dispatch in `main.go` is already carrying four names.

## Event types

    start    once, after the pipeline is up. Carries device, path, and mode.
    level    the mic RMS, coalesced to 20 Hz.
    partial  in-progress text from the realtime backend; replaces the previous.
    commit   text the realtime backend finalised; appended.
    final    the finished transcript, from the live session or the batch pass.
    error    something failed; `fatal` says whether recording continued.
    end      always last. `reason` says why, `exit_code` says how it went.

`start.mode` is `live` when partials will arrive, `batch` when no partials will
arrive but a batch pass will produce one `final`, and `none` when there will be
no transcript at all. It is emitted after the streamer has connected, so it is
a statement of fact rather than an intention.

## What stdout carries

Under `--stream`, the NDJSON is the whole of stdout. The bare path line
`record` prints today would break a line-oriented consumer's parser, so it is
suppressed; `path` appears on `start`, `final`, and `end` instead. The batch
`transcribe` subprocess normally inherits stdout, so under `--stream` its
stdout is captured into a buffer and delivered as `final.text`.

Scripts that do `transcribe $(record)` must not pass `--stream`. That is the
whole of the compatibility story: the flag opts into a different contract.

## Termination

`--stream` implies `--no-tui`: bubbletea's alternate screen and an NDJSON
consumer cannot both own stdout. It also installs a SIGINT and SIGTERM handler,
which `--no-tui` does not have today. On the first signal, ffmpeg is stopped
the graceful way (`Recorder.Stop` writes `q` to its stdin), the transcript is
promoted, the batch pass runs if it was asked for, and the stream closes with
`end{reason:"signal", exit_code:0}`. A deliberate stop is not a failure. The
signal is then restored to its default disposition, so a second Ctrl-C kills
the process outright rather than hanging on a wedged ffmpeg.

A consumer that reaches EOF without having seen `end` knows the producer died.

## Rejected combinations

`--stream --clips` and `--stream --list-devices` both fail with an error.
Clips mode is an interactive TUI loop; `--list-devices` prints a human table.
Both want stdout for something that is not NDJSON. Use `audiomemo device list`
for enumeration.

## Levels

ffmpeg's `astats` filter prints one RMS line per 480 samples, which is 100 a
second at 48 kHz. That is more than any consumer needs, so the emitter keeps
the loudest reading per 50 ms window and emits at 20 Hz. Smoothing stays with
the consumer: the wire carries measurements, not a rendering.

`astats` reports digital silence as `-inf` and can report `inf`. `encoding/json`
refuses to marshal either, and a refused encode drops the whole line, so `db`
is clamped to [-60, 0] and `rms` is the same reading normalised onto [0, 1]
against the same -60 dBFS floor the TUI already uses.

## Errors

Everything audiomemo would have written to stderr as a warning becomes an
`error` event with a `scope` (`record`, `stream`, `transcribe`, `config`) and a
`fatal` flag. Subprocess stderr still goes to fd 2, because ffmpeg's and
whisper's diagnostics are not audiomemo's to reformat.

## Out of scope

Device enumeration over the stream, pause/resume control on stdin, and any
change to the batch backends or output formats.
```

- [ ] **Step 2: Write the failing test**

Create `internal/stream/emitter_test.go`:

```go
package stream

import (
	"bytes"
	"encoding/json"
	"errors"
	"math"
	"strings"
	"sync"
	"testing"
	"time"
)

// decodeLines splits NDJSON output into one generic map per line. Tests assert
// on the map rather than on a struct so a field silently disappearing from the
// wire shows up as a failure.
func decodeLines(t *testing.T, s string) []map[string]any {
	t.Helper()
	var out []map[string]any
	for _, line := range strings.Split(strings.TrimRight(s, "\n"), "\n") {
		if line == "" {
			continue
		}
		var m map[string]any
		if err := json.Unmarshal([]byte(line), &m); err != nil {
			t.Fatalf("line %q is not JSON: %v", line, err)
		}
		out = append(out, m)
	}
	return out
}

// fakeClock advances only when a test says so, so `t` is deterministic.
type fakeClock struct{ at time.Time }

func (c *fakeClock) now() time.Time { return c.at }

func newTestEmitter() (*Emitter, *bytes.Buffer, *fakeClock) {
	buf := &bytes.Buffer{}
	clk := &fakeClock{at: time.Unix(1000, 0)}
	return newEmitter(buf, clk.now), buf, clk
}

func TestStartEvent(t *testing.T) {
	em, buf, _ := newTestEmitter()
	em.Start(StartEvent{
		Device:      "alsa_input.usb-Blue_Yeti-00.analog-stereo",
		DeviceLabel: "mic",
		Devices:     []string{"alsa_input.usb-Blue_Yeti-00.analog-stereo"},
		Path:        "/tmp/memo.ogg",
		Format:      "ogg",
		SampleRate:  48000,
		Channels:    1,
		Mode:        ModeLive,
		Backend:     "elevenlabs",
	})
	lines := decodeLines(t, buf.String())
	if len(lines) != 1 {
		t.Fatalf("want 1 line, got %d", len(lines))
	}
	got := lines[0]
	if got["type"] != "start" {
		t.Errorf("type = %v, want start", got["type"])
	}
	if got["device_label"] != "mic" {
		t.Errorf("device_label = %v", got["device_label"])
	}
	if got["path"] != "/tmp/memo.ogg" {
		t.Errorf("path = %v", got["path"])
	}
	if got["mode"] != "live" {
		t.Errorf("mode = %v, want live", got["mode"])
	}
	if got["sample_rate"] != float64(48000) {
		t.Errorf("sample_rate = %v", got["sample_rate"])
	}
	if got["t"] != float64(0) {
		t.Errorf("t = %v, want 0 on the first event", got["t"])
	}
}

func TestLevelEventCarriesBothScales(t *testing.T) {
	em, buf, clk := newTestEmitter()
	clk.at = clk.at.Add(250 * time.Millisecond)
	em.Level(0.35, -39.0)
	got := decodeLines(t, buf.String())[0]
	if got["type"] != "level" {
		t.Errorf("type = %v", got["type"])
	}
	if got["rms"] != 0.35 {
		t.Errorf("rms = %v, want 0.35", got["rms"])
	}
	if got["db"] != -39.0 {
		t.Errorf("db = %v, want -39", got["db"])
	}
	if got["t"] != float64(250) {
		t.Errorf("t = %v, want 250", got["t"])
	}
}

// An unencodable float would make Encode fail and drop the line entirely, so
// the emitter must never be handed one. This pins the guard in place.
func TestLevelEventRefusesNonFiniteValues(t *testing.T) {
	em, buf, _ := newTestEmitter()
	em.Level(math.Inf(1), math.Inf(-1))
	got := decodeLines(t, buf.String())[0]
	if got["rms"] != 1.0 {
		t.Errorf("rms = %v, want 1 for +Inf", got["rms"])
	}
	if got["db"] != -60.0 {
		t.Errorf("db = %v, want -60 for -Inf", got["db"])
	}
}

func TestPartialAndCommit(t *testing.T) {
	em, buf, _ := newTestEmitter()
	em.Partial("so the thing is")
	em.Commit("So the thing is,")
	lines := decodeLines(t, buf.String())
	if lines[0]["type"] != "partial" || lines[0]["text"] != "so the thing is" {
		t.Errorf("partial line = %v", lines[0])
	}
	if lines[1]["type"] != "commit" || lines[1]["text"] != "So the thing is," {
		t.Errorf("commit line = %v", lines[1])
	}
}

// Transcripts contain apostrophes and angle brackets often enough that HTML
// escaping would be visible in the consumer's UI.
func TestTextIsNotHTMLEscaped(t *testing.T) {
	em, buf, _ := newTestEmitter()
	em.Partial(`5 < 6 && "quoted"`)
	if !strings.Contains(buf.String(), `5 < 6`) == false {
		t.Errorf("output was HTML-escaped: %s", buf.String())
	}
	if got := decodeLines(t, buf.String())[0]["text"]; got != `5 < 6 && "quoted"` {
		t.Errorf("round-trip = %q", got)
	}
}

func TestFinalEvent(t *testing.T) {
	em, buf, _ := newTestEmitter()
	em.Final(FinalEvent{
		Text:           "So the thing is, we shipped it.",
		Path:           "/tmp/memo.ogg",
		TranscriptPath: "/tmp/memo.txt",
		Backend:        "elevenlabs",
		Source:         SourceLive,
	})
	got := decodeLines(t, buf.String())[0]
	if got["type"] != "final" {
		t.Errorf("type = %v", got["type"])
	}
	if got["source"] != "live" {
		t.Errorf("source = %v", got["source"])
	}
	if got["transcript_path"] != "/tmp/memo.txt" {
		t.Errorf("transcript_path = %v", got["transcript_path"])
	}
}

func TestErrorEvent(t *testing.T) {
	em, buf, _ := newTestEmitter()
	em.Error(ScopeStream, false, errors.New("websocket dial failed"))
	got := decodeLines(t, buf.String())[0]
	if got["type"] != "error" {
		t.Errorf("type = %v", got["type"])
	}
	if got["scope"] != "stream" {
		t.Errorf("scope = %v", got["scope"])
	}
	if got["fatal"] != false {
		t.Errorf("fatal = %v, want false", got["fatal"])
	}
	if got["message"] != "websocket dial failed" {
		t.Errorf("message = %v", got["message"])
	}
}

// `fatal` must be present even when false, or a consumer cannot tell "not
// fatal" from "field missing".
func TestErrorEventAlwaysCarriesFatal(t *testing.T) {
	em, buf, _ := newTestEmitter()
	em.Error(ScopeRecord, false, errors.New("x"))
	if _, ok := decodeLines(t, buf.String())[0]["fatal"]; !ok {
		t.Error("fatal field omitted when false")
	}
}

func TestEndEvent(t *testing.T) {
	em, buf, _ := newTestEmitter()
	em.End(EndEvent{Reason: ReasonSignal, Path: "/tmp/memo.ogg", ExitCode: 0})
	got := decodeLines(t, buf.String())[0]
	if got["type"] != "end" {
		t.Errorf("type = %v", got["type"])
	}
	if got["reason"] != "signal" {
		t.Errorf("reason = %v", got["reason"])
	}
	if _, ok := got["exit_code"]; !ok {
		t.Error("exit_code omitted when zero")
	}
}

// Levels come off ffmpeg's stderr goroutine while partials come off the
// websocket goroutine. Interleaved half-lines would be unparseable.
func TestConcurrentEmitsProduceWholeLines(t *testing.T) {
	em, buf, _ := newTestEmitter()
	var wg sync.WaitGroup
	for i := 0; i < 50; i++ {
		wg.Add(2)
		go func() { defer wg.Done(); em.Level(0.5, -30) }()
		go func() { defer wg.Done(); em.Partial("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa") }()
	}
	wg.Wait()
	if got := len(decodeLines(t, buf.String())); got != 100 {
		t.Errorf("parsed %d whole lines, want 100", got)
	}
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run:
```bash
cd /home/joe/Development/audiomemo && go test ./internal/stream/ 2>&1 | tail -5
```

Expected: `internal/stream/emitter_test.go: no required module provides package` or `undefined: Emitter`. The package does not exist yet.

- [ ] **Step 4: Write `internal/stream/event.go`**

```go
// Package stream defines the newline-delimited JSON that `record --stream`
// writes to stdout: one JSON object per line, emitted as it happens.
//
// The wire carries measurements, not a rendering. Levels are raw readings on
// two scales and text is exactly what the backend produced; smoothing, colour,
// and layout belong to the consumer, which knows its own terminal width.
package stream

// Event type discriminators.
const (
	TypeStart   = "start"
	TypeLevel   = "level"
	TypePartial = "partial"
	TypeCommit  = "commit"
	TypeFinal   = "final"
	TypeError   = "error"
	TypeEnd     = "end"
)

// StartEvent.Mode values. Mode answers one question: will partials arrive?
const (
	ModeLive  = "live"  // realtime backend connected; partial and commit will follow
	ModeBatch = "batch" // no partials, but a batch pass will produce one final
	ModeNone  = "none"  // no transcript will be produced at all
)

// FinalEvent.Source values.
const (
	SourceLive  = "live"
	SourceBatch = "batch"
)

// ErrorEvent.Scope values.
const (
	ScopeRecord     = "record"
	ScopeStream     = "stream"
	ScopeTranscribe = "transcribe"
	ScopeConfig     = "config"
)

// EndEvent.Reason values.
const (
	ReasonStopped = "stopped" // ffmpeg exited on its own (duration elapsed, device gone)
	ReasonSignal  = "signal"  // SIGINT or SIGTERM; a deliberate stop
	ReasonError   = "error"   // the run failed
)

// header is embedded in every event. Anonymous with no tag of its own, so its
// fields are promoted into the top-level JSON object.
type header struct {
	Type string `json:"type"`
	T    int64  `json:"t"` // milliseconds since the stream opened
}

// StartEvent is emitted once, after the recorder is running and the realtime
// backend has either connected or failed. Mode is therefore a fact.
type StartEvent struct {
	header
	Device      string   `json:"device"`
	DeviceLabel string   `json:"device_label"`
	Devices     []string `json:"devices"`
	Path        string   `json:"path"`
	Format      string   `json:"format"`
	SampleRate  int      `json:"sample_rate"`
	Channels    int      `json:"channels"`
	Mode        string   `json:"mode"`
	Backend     string   `json:"backend,omitempty"`
}

// LevelEvent carries one mic reading on both scales: RMS normalised onto
// [0,1] for a meter, and the dBFS the meter was derived from for a readout.
type LevelEvent struct {
	header
	RMS float64 `json:"rms"`
	DB  float64 `json:"db"`
}

// TextEvent backs both partial and commit. A partial replaces the previous
// partial; a commit is appended and will not change.
type TextEvent struct {
	header
	Text string `json:"text"`
}

// FinalEvent is the finished transcript. Source says where it came from: the
// realtime session, or the higher-quality batch pass that ran afterwards.
type FinalEvent struct {
	header
	Text           string `json:"text"`
	Path           string `json:"path"`
	TranscriptPath string `json:"transcript_path,omitempty"`
	Backend        string `json:"backend,omitempty"`
	Source         string `json:"source"`
}

// ErrorEvent replaces the stderr warnings the non-stream paths print. Fatal
// distinguishes "recording continued without this" from "the run is over".
type ErrorEvent struct {
	header
	Scope   string `json:"scope"`
	Fatal   bool   `json:"fatal"`
	Message string `json:"message"`
}

// EndEvent is always the last line. Reaching EOF without one means the
// producer died rather than finished.
type EndEvent struct {
	header
	Reason   string `json:"reason"`
	Path     string `json:"path,omitempty"`
	ExitCode int    `json:"exit_code"`
}
```

- [ ] **Step 5: Write `internal/stream/emitter.go`**

```go
package stream

import (
	"encoding/json"
	"io"
	"math"
	"sync"
	"time"
)

// Emitter serialises events onto one writer. Levels arrive on ffmpeg's stderr
// goroutine and text arrives on the websocket goroutine, so the mutex is what
// keeps lines whole.
type Emitter struct {
	mu  sync.Mutex
	enc *json.Encoder

	start time.Time
	now   func() time.Time
}

// NewEmitter returns an Emitter writing NDJSON to w.
func NewEmitter(w io.Writer) *Emitter { return newEmitter(w, time.Now) }

func newEmitter(w io.Writer, now func() time.Time) *Emitter {
	enc := json.NewEncoder(w)
	// Transcripts contain apostrophes and angle brackets; escaping them would
	// be visible in the consumer's UI.
	enc.SetEscapeHTML(false)
	return &Emitter{enc: enc, start: now(), now: now}
}

func (e *Emitter) header(t string) header {
	return header{Type: t, T: e.now().Sub(e.start).Milliseconds()}
}

// emit writes one line. json.Encoder.Encode appends the newline itself, which
// is exactly the NDJSON framing. A write error means the consumer is gone;
// there is nowhere useful to report that, so it is dropped.
func (e *Emitter) emit(v any) {
	e.mu.Lock()
	defer e.mu.Unlock()
	_ = e.enc.Encode(v)
}

func (e *Emitter) Start(ev StartEvent) {
	ev.header = e.header(TypeStart)
	if ev.Devices == nil {
		ev.Devices = []string{}
	}
	e.emit(ev)
}

// Level clamps both scales before encoding. encoding/json returns an
// UnsupportedValueError for ±Inf and NaN, and a refused encode would drop the
// whole line rather than one field.
func (e *Emitter) Level(rms, db float64) {
	e.emit(LevelEvent{header: e.header(TypeLevel), RMS: finite(rms, 0, 1), DB: finite(db, FloorDB, 0)})
}

func (e *Emitter) Partial(text string) {
	e.emit(TextEvent{header: e.header(TypePartial), Text: text})
}

func (e *Emitter) Commit(text string) {
	e.emit(TextEvent{header: e.header(TypeCommit), Text: text})
}

func (e *Emitter) Final(ev FinalEvent) {
	ev.header = e.header(TypeFinal)
	e.emit(ev)
}

func (e *Emitter) Error(scope string, fatal bool, err error) {
	msg := ""
	if err != nil {
		msg = err.Error()
	}
	e.emit(ErrorEvent{header: e.header(TypeError), Scope: scope, Fatal: fatal, Message: msg})
}

func (e *Emitter) End(ev EndEvent) {
	ev.header = e.header(TypeEnd)
	e.emit(ev)
}

// finite maps NaN to lo and clamps everything else into [lo, hi], so +Inf
// saturates at hi and -Inf at lo.
func finite(v, lo, hi float64) float64 {
	if math.IsNaN(v) || v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}
```

`FloorDB` is defined in Task 2; until then, add `const FloorDB = -60.0` to `emitter.go` and move it in Task 2.

- [ ] **Step 6: Export the realtime backend name**

In `internal/transcribe/stream.go`, immediately after the `realtimeModelID` block, add:

```go
// RealtimeBackendName identifies the Streamer's provider in machine-readable
// output. The Transcriber interface's Name() covers the batch backends; the
// realtime path has no Transcriber, so it needs its own constant.
const RealtimeBackendName = "elevenlabs"
```

- [ ] **Step 7: Run the tests**

Run:
```bash
cd /home/joe/Development/audiomemo && gofmt -l . | grep -v '^vendor/' ; go test ./internal/stream/ ./internal/transcribe/
```

Expected: `gofmt -l` prints nothing, and both packages report `ok`.

- [ ] **Step 8: Commit**

```bash
cd /home/joe/Development/audiomemo
git add -A
git commit -m "feat(stream): NDJSON event schema and emitter for record --stream

One JSON object per line, emitted as it happens. The wire carries
measurements rather than a rendering: levels come on both the normalised
and dBFS scales and text is verbatim, so the consumer owns smoothing,
colour, and width. Levels are clamped because encoding/json refuses Inf
and a refused encode drops the whole line, and ffmpeg's astats reports
digital silence as -inf."
```

---

### Task 2: Level normalisation and rate limiting

ffmpeg prints one RMS line per 480 samples. At 48 kHz that is 100 lines a second, which is more NDJSON than any consumer wants. This task adds the maths and the coalescing, and removes the duplicate copy by pointing the TUI at it.

**Files:** (all in `/home/joe/Development/audiomemo`)
- Create: `internal/stream/level.go`
- Create: `internal/stream/level_test.go`
- Modify: `internal/stream/emitter.go` (drop the temporary `FloorDB`)
- Modify: `internal/tui/vu.go` (`dbToLevel` delegates)

**Interfaces:**
- Consumes: `stream.Emitter` from Task 1
- Produces:
  - `const stream.FloorDB = -60.0`
  - `func stream.NormalizeLevel(db float64) float64`
  - `func stream.ClampDB(db float64) float64`
  - `type stream.LevelThrottle` with `func NewLevelThrottle(interval time.Duration) *LevelThrottle` and `(*LevelThrottle) Push(db float64) (float64, bool)`

- [ ] **Step 1: Write the failing test**

Create `internal/stream/level_test.go`:

```go
package stream

import (
	"math"
	"testing"
	"time"
)

func TestNormalizeLevel(t *testing.T) {
	cases := []struct {
		db   float64
		want float64
	}{
		{0, 1},         // full scale
		{-30, 0.5},     // halfway up the -60 dBFS floor
		{-60, 0},       // the floor itself
		{-90, 0},       // below the floor clamps rather than going negative
		{6, 1},         // above full scale clamps
		{math.Inf(-1), 0},
		{math.Inf(1), 1},
		{math.NaN(), 0},
	}
	for _, c := range cases {
		if got := NormalizeLevel(c.db); math.Abs(got-c.want) > 1e-9 {
			t.Errorf("NormalizeLevel(%v) = %v, want %v", c.db, got, c.want)
		}
	}
}

func TestClampDB(t *testing.T) {
	cases := []struct{ in, want float64 }{
		{-21.5, -21.5},
		{-120, FloorDB},
		{4, 0},
		{math.Inf(-1), FloorDB},
		{math.Inf(1), 0},
		{math.NaN(), FloorDB},
	}
	for _, c := range cases {
		if got := ClampDB(c.in); got != c.want {
			t.Errorf("ClampDB(%v) = %v, want %v", c.in, got, c.want)
		}
	}
}

func TestLevelThrottleEmitsFirstSampleImmediately(t *testing.T) {
	th := newLevelThrottle(50*time.Millisecond, clockAt(0))
	got, ok := th.Push(-20)
	if !ok {
		t.Fatal("first sample was withheld; the meter would start blank")
	}
	if got != -20 {
		t.Errorf("got %v, want -20", got)
	}
}

func TestLevelThrottleKeepsThePeakWithinAWindow(t *testing.T) {
	clk := &fakeClock{at: time.Unix(0, 0)}
	th := newLevelThrottle(50*time.Millisecond, clk.now)
	th.Push(-40) // emitted immediately

	clk.at = clk.at.Add(10 * time.Millisecond)
	if _, ok := th.Push(-35); ok {
		t.Error("sample inside the window was emitted")
	}
	clk.at = clk.at.Add(10 * time.Millisecond)
	if _, ok := th.Push(-12); ok { // the peak
		t.Error("sample inside the window was emitted")
	}
	clk.at = clk.at.Add(10 * time.Millisecond)
	if _, ok := th.Push(-38); ok {
		t.Error("sample inside the window was emitted")
	}

	clk.at = clk.at.Add(30 * time.Millisecond) // window closed
	got, ok := th.Push(-45)
	if !ok {
		t.Fatal("window closed but nothing was emitted")
	}
	// A meter that reported -45 here would miss the transient entirely.
	if got != -12 {
		t.Errorf("got %v, want the window peak -12", got)
	}
}

func TestLevelThrottleStartsAFreshWindowAfterEmitting(t *testing.T) {
	clk := &fakeClock{at: time.Unix(0, 0)}
	th := newLevelThrottle(50*time.Millisecond, clk.now)
	th.Push(-10)
	clk.at = clk.at.Add(60 * time.Millisecond)
	th.Push(-50)
	clk.at = clk.at.Add(60 * time.Millisecond)
	got, _ := th.Push(-55)
	if got != -55 {
		t.Errorf("got %v, want -55; the previous window's peak leaked", got)
	}
}

func clockAt(sec int64) func() time.Time {
	return func() time.Time { return time.Unix(sec, 0) }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
cd /home/joe/Development/audiomemo && go test ./internal/stream/ 2>&1 | tail -5
```

Expected: `undefined: NormalizeLevel`, `undefined: ClampDB`, `undefined: newLevelThrottle`.

- [ ] **Step 3: Write `internal/stream/level.go`**

```go
package stream

import (
	"math"
	"time"
)

// FloorDB is the quietest reading the meter distinguishes. ffmpeg's astats
// reports digital silence as -inf, so a floor is needed either way, and -60
// is the one the recording TUI has always used.
const FloorDB = -60.0

// NormalizeLevel maps a dBFS reading onto [0, 1] against FloorDB. NaN and
// anything below the floor read as silence; anything at or above full scale
// reads as 1.
func NormalizeLevel(db float64) float64 {
	if math.IsNaN(db) || db <= FloorDB {
		return 0
	}
	if db >= 0 {
		return 1
	}
	return (db - FloorDB) / -FloorDB
}

// ClampDB finite-ises a dBFS reading for the wire. See Emitter.Level for why
// this matters: encoding/json refuses ±Inf and NaN outright.
func ClampDB(db float64) float64 {
	if math.IsNaN(db) || db < FloorDB {
		return FloorDB
	}
	if db > 0 {
		return 0
	}
	return db
}

// LevelThrottle coalesces ffmpeg's ~100 Hz RMS lines down to one reading per
// interval, keeping the loudest in each window. Keeping the peak rather than
// the last reading is what stops a meter from missing transients.
type LevelThrottle struct {
	interval time.Duration
	now      func() time.Time

	opened   time.Time
	peak     float64
	havePeak bool
	started  bool
}

// NewLevelThrottle returns a throttle emitting at most one reading per interval.
func NewLevelThrottle(interval time.Duration) *LevelThrottle {
	return newLevelThrottle(interval, time.Now)
}

func newLevelThrottle(interval time.Duration, now func() time.Time) *LevelThrottle {
	return &LevelThrottle{interval: interval, now: now}
}

// Push feeds one dBFS reading. It returns the value to emit and true when the
// current window has closed, and false while the window is still filling.
func (t *LevelThrottle) Push(db float64) (float64, bool) {
	now := t.now()
	if !t.started {
		t.started = true
		t.opened = now
		return db, true
	}
	if !t.havePeak || db > t.peak {
		t.peak = db
		t.havePeak = true
	}
	if now.Sub(t.opened) < t.interval {
		return 0, false
	}
	peak := t.peak
	t.opened = now
	t.peak = 0
	t.havePeak = false
	return peak, true
}
```

- [ ] **Step 4: Delete the temporary constant and point the TUI at the shared one**

In `internal/stream/emitter.go`, delete the `const FloorDB = -60.0` line added in Task 1 Step 5; `level.go` now owns it.

In `internal/tui/vu.go`, replace the body of `dbToLevel` so there is one definition of the mapping rather than two that can drift:

```go
// dbToLevel maps a dBFS reading onto the 0..1 the meter draws. The mapping
// lives in internal/stream so the TUI and the --stream wire format cannot
// disagree about what "half" means.
func dbToLevel(db float64) float64 {
	return stream.NormalizeLevel(db)
}
```

and add `"github.com/joegoldin/audiomemo/internal/stream"` to that file's imports. Leave `levelToDB` alone: it is the TUI's own inverse for the dB readout and has no wire counterpart.

- [ ] **Step 5: Run the tests**

Run:
```bash
cd /home/joe/Development/audiomemo && gofmt -l . | grep -v '^vendor/' ; go test ./internal/stream/ ./internal/tui/
```

Expected: `gofmt -l` prints nothing, both packages `ok`. `internal/tui`'s existing `vu_test.go` must pass unchanged; if it does not, the mapping was not equivalent and `NormalizeLevel` is wrong, not the test.

- [ ] **Step 6: Commit**

```bash
cd /home/joe/Development/audiomemo
git add -A
git commit -m "feat(stream): level normalisation and 20 Hz coalescing

astats prints 100 RMS lines a second at 48 kHz. The throttle keeps the
loudest reading per window so transients survive the rate reduction,
which taking the last reading would not do. dbToLevel now delegates to
NormalizeLevel so the meter and the wire format share one definition of
the -60 dBFS floor."
```

---

### Task 3: The `--stream` flag and its guardrails

Flag registration and the pure decisions that follow from it. The run loop is Task 4; this task is only the parts that can be tested without a microphone.

**Files:** (all in `/home/joe/Development/audiomemo`)
- Modify: `cmd/record.go` (register `--stream`, force `--no-tui`, gate the path line)
- Modify: `cmd/record_test.go` (new tests appended)
- Modify: `README.md`

**Interfaces:**
- Consumes: `stream.ModeLive` / `ModeBatch` / `ModeNone` from Task 1
- Produces:
  - `func validateStreamFlags(stream, clips, listDevices bool) error`
  - `func resolveStreamMode(liveActive, batchTranscribe bool) string`
  - `var rStream bool`, wired to `--stream`

- [ ] **Step 1: Write the failing test**

Append to `cmd/record_test.go`:

```go
func TestValidateStreamFlags(t *testing.T) {
	if err := validateStreamFlags(false, true, true); err != nil {
		t.Errorf("without --stream nothing is rejected, got %v", err)
	}
	if err := validateStreamFlags(true, false, false); err != nil {
		t.Errorf("plain --stream must be accepted, got %v", err)
	}
	// Clips mode drives an interactive TUI loop, so it owns stdout for
	// something that is not NDJSON.
	err := validateStreamFlags(true, true, false)
	if err == nil {
		t.Fatal("--stream --clips must be rejected")
	}
	if !strings.Contains(err.Error(), "--clips") {
		t.Errorf("error should name the offending flag, got %q", err)
	}
	// --list-devices prints a human table on stdout.
	err = validateStreamFlags(true, false, true)
	if err == nil {
		t.Fatal("--stream --list-devices must be rejected")
	}
	if !strings.Contains(err.Error(), "device list") {
		t.Errorf("error should point at the supported alternative, got %q", err)
	}
}

func TestResolveStreamMode(t *testing.T) {
	cases := []struct {
		name                  string
		liveActive, willBatch bool
		want                  string
	}{
		{"realtime backend connected", true, false, "live"},
		{"realtime plus a batch pass still yields partials", true, true, "live"},
		{"no key but -t was passed", false, true, "batch"},
		{"no key and no batch pass", false, false, "none"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := resolveStreamMode(c.liveActive, c.willBatch); got != c.want {
				t.Errorf("resolveStreamMode(%v, %v) = %q, want %q", c.liveActive, c.willBatch, got, c.want)
			}
		})
	}
}
```

Add `"strings"` to that file's imports.

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
cd /home/joe/Development/audiomemo && go test ./cmd/ 2>&1 | tail -5
```

Expected: `undefined: validateStreamFlags` and `undefined: resolveStreamMode`.

- [ ] **Step 3: Implement the two functions in `cmd/record.go`**

Add next to `resolveRecordTranscriptionMode`:

```go
// validateStreamFlags rejects the combinations --stream cannot honour. Both
// rejected modes want stdout for something other than NDJSON, and a consumer
// parsing one object per line would choke on either.
func validateStreamFlags(streamFlag, clips, listDevices bool) error {
	if !streamFlag {
		return nil
	}
	if clips {
		return fmt.Errorf("--stream cannot be combined with --clips: clips mode is an interactive TUI loop")
	}
	if listDevices {
		return fmt.Errorf("--stream cannot be combined with --list-devices: use `audiomemo device list`")
	}
	return nil
}

// resolveStreamMode reports what the start event should claim. It answers one
// question for the consumer: will partial events arrive? A batch pass alone
// produces a single final at the end and nothing before it.
func resolveStreamMode(liveActive, batchTranscribe bool) string {
	switch {
	case liveActive:
		return stream.ModeLive
	case batchTranscribe:
		return stream.ModeBatch
	default:
		return stream.ModeNone
	}
}
```

Add `"github.com/joegoldin/audiomemo/internal/stream"` to the imports.

- [ ] **Step 4: Register the flag and force headless mode**

Add `rStream bool` to the `var (...)` block at the top of `cmd/record.go`, then in `init()`:

```go
	recordCmd.Flags().BoolVar(&rStream, "stream", false, "emit newline-delimited JSON events on stdout while recording (implies --no-tui)")
```

In `runRecord`, immediately after the config load and before `maybeOnboard`, add:

```go
	if err := validateStreamFlags(rStream, rClips, rListDevices); err != nil {
		return err
	}
	// A bubbletea alternate screen and an NDJSON consumer cannot both own
	// stdout. Forcing headless mode here also suppresses the interactive
	// device picker below, which a machine consumer could not answer.
	if rStream {
		rNoTUI = true
	}
```

- [ ] **Step 5: Gate the bare path line**

In `runRecord`, replace:

```go
	// Print just the path to stdout so it can be piped, e.g.:
	//   transcribe $(record)
	fmt.Println(outputPath)
```

with:

```go
	// Print just the path to stdout so it can be piped, e.g.:
	//   transcribe $(record)
	// Under --stream, stdout carries NDJSON and a bare path line would break
	// a line-oriented consumer; path travels on the start, final, and end
	// events instead.
	if !rStream {
		fmt.Println(outputPath)
	}
```

This is defensive: Task 4 routes `--stream` down its own function before reaching here. The guard costs one branch and means a future refactor cannot reintroduce the corruption silently.

- [ ] **Step 6: Document the flag**

In `README.md`, under `### record (alias: rect)`, add to the flag list after `--no-tui`:

```
        --stream                 emit newline-delimited JSON on stdout
                                 (implies --no-tui; see STREAMING OUTPUT)
```

and add a new section after `## LIVE TRANSCRIPTION`:

```
## STREAMING OUTPUT

`record --stream` writes one JSON object per line to stdout while recording,
so another program can render the transcript and the mic level live.

    $ record --stream -D mic -t
    {"type":"start","t":0,"device":"alsa_input.usb-Blue_Yeti-00.analog-stereo","device_label":"mic","devices":["alsa_input.usb-Blue_Yeti-00.analog-stereo"],"path":"/home/joe/Recordings/recording-2026-08-18T14-30-05.ogg","format":"ogg","sample_rate":48000,"channels":1,"mode":"live","backend":"elevenlabs"}
    {"type":"level","t":52,"rms":0.21,"db":-47.4}
    {"type":"partial","t":1840,"text":"so the thing is"}
    {"type":"commit","t":2900,"text":"So the thing is,"}
    {"type":"final","t":9120,"text":"So the thing is, we shipped it.","path":"/home/joe/Recordings/recording-2026-08-18T14-30-05.ogg","transcript_path":"/home/joe/Recordings/recording-2026-08-18T14-30-05.txt","backend":"elevenlabs","source":"batch"}
    {"type":"end","t":9130,"reason":"signal","path":"/home/joe/Recordings/recording-2026-08-18T14-30-05.ogg","exit_code":0}

Every event carries `type` and `t` (milliseconds since the stream opened).

    start    once, after the pipeline is up. `mode` is `live` (partials will
             arrive), `batch` (no partials, one final after recording), or
             `none` (no transcript at all).
    level    `rms` on 0..1 and `db` in dBFS, coalesced to 20 Hz.
    partial  in-progress text; replaces the previous partial.
    commit   finalised text; append it.
    final    the finished transcript. `source` is `live` or `batch`.
    error    `scope` is record, stream, transcribe, or config; `fatal` says
             whether recording continued.
    end      always last. Reaching EOF without it means the producer died.

`--stream` implies `--no-tui`, suppresses the bare path line, and installs a
SIGINT/SIGTERM handler that stops ffmpeg gracefully and closes the stream with
`end{"reason":"signal"}`. A second signal exits immediately. It cannot be
combined with `--clips` or `--list-devices`.

Unknown event types must be skipped rather than treated as errors, so the
schema can grow.
```

- [ ] **Step 7: Run the tests**

Run:
```bash
cd /home/joe/Development/audiomemo && gofmt -l . | grep -v '^vendor/' ; go test ./... 2>&1 | grep -v '^ok' | head
```

Expected: no gofmt output and no failures. `integration_test.go` still passes, which is the proof that the non-stream stdout contract is intact.

- [ ] **Step 8: Commit**

```bash
cd /home/joe/Development/audiomemo
git add -A
git commit -m "feat(record): --stream flag, guardrails, and mode resolution

A flag rather than a subcommand or an argv[0] symlink, so it composes
with the device, duration, and format flags instead of redeclaring them.
It forces --no-tui because bubbletea and an NDJSON consumer cannot both
own stdout, and rejects --clips and --list-devices for the same reason."
```

---

### Task 4: The streaming run loop

`runRecordStream` replaces the `--no-tui` block for `--stream` runs: it pumps levels and text into the emitter, turns warnings into `error` events, and terminates on a signal in a way the consumer can distinguish from a crash.

**Files:** (all in `/home/joe/Development/audiomemo`)
- Create: `cmd/record_stream.go`
- Create: `cmd/record_stream_test.go`
- Modify: `cmd/record.go` (branch into `runRecordStream`)

**Interfaces:**
- Consumes: `stream.Emitter`, `stream.LevelThrottle`, `record.Recorder`, `transcribe.Streamer`
- Produces:
  - `type streamRun struct` holding the emitter and the pumps
  - `func pumpLevels(em *stream.Emitter, levels <-chan float64, th *stream.LevelThrottle)`
  - `func pumpText(em *stream.Emitter, partial, committed <-chan string)`
  - `func pumpErrors(em *stream.Emitter, errs <-chan error)`
  - `func runRecordStream(cfg *config.Config, opts record.RecordOpts, streamer *transcribe.Streamer, streamErr error, batchTranscribe bool) error`

- [ ] **Step 1: Write the failing test**

Create `cmd/record_stream_test.go`:

```go
package cmd

import (
	"bytes"
	"encoding/json"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/joegoldin/audiomemo/internal/stream"
)

func decodeStreamLines(t *testing.T, s string) []map[string]any {
	t.Helper()
	var out []map[string]any
	for _, line := range strings.Split(strings.TrimRight(s, "\n"), "\n") {
		if line == "" {
			continue
		}
		var m map[string]any
		if err := json.Unmarshal([]byte(line), &m); err != nil {
			t.Fatalf("line %q is not JSON: %v", line, err)
		}
		out = append(out, m)
	}
	return out
}

func TestPumpLevelsEmitsBothScalesAndStopsOnClose(t *testing.T) {
	buf := &bytes.Buffer{}
	em := stream.NewEmitter(buf)
	levels := make(chan float64, 4)
	levels <- -30.0
	close(levels)

	done := make(chan struct{})
	go func() { pumpLevels(em, levels, stream.NewLevelThrottle(0)); close(done) }()
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("pumpLevels did not return when its channel closed")
	}

	lines := decodeStreamLines(t, buf.String())
	if len(lines) != 1 {
		t.Fatalf("want 1 level line, got %d", len(lines))
	}
	if lines[0]["type"] != "level" {
		t.Errorf("type = %v", lines[0]["type"])
	}
	if lines[0]["db"] != -30.0 {
		t.Errorf("db = %v, want -30", lines[0]["db"])
	}
	if lines[0]["rms"] != 0.5 {
		t.Errorf("rms = %v, want 0.5 halfway up the -60 floor", lines[0]["rms"])
	}
}

// ffmpeg reports digital silence as -inf. Without the clamp this line would
// fail to encode and vanish, taking the meter with it.
func TestPumpLevelsSurvivesDigitalSilence(t *testing.T) {
	buf := &bytes.Buffer{}
	levels := make(chan float64, 1)
	levels <- math_Inf_neg()
	close(levels)
	pumpLevels(stream.NewEmitter(buf), levels, stream.NewLevelThrottle(0))

	lines := decodeStreamLines(t, buf.String())
	if len(lines) != 1 {
		t.Fatalf("silence produced %d lines, want 1", len(lines))
	}
	if lines[0]["rms"] != 0.0 || lines[0]["db"] != -60.0 {
		t.Errorf("silence encoded as rms=%v db=%v, want 0 and -60", lines[0]["rms"], lines[0]["db"])
	}
}

func TestPumpTextSeparatesPartialFromCommit(t *testing.T) {
	buf := &bytes.Buffer{}
	partial := make(chan string, 2)
	committed := make(chan string, 2)
	partial <- "so the thing"
	committed <- "So the thing is,"
	close(partial)
	close(committed)

	pumpText(stream.NewEmitter(buf), partial, committed)

	types := map[string]string{}
	for _, l := range decodeStreamLines(t, buf.String()) {
		types[l["type"].(string)] = l["text"].(string)
	}
	if types["partial"] != "so the thing" {
		t.Errorf("partial = %q", types["partial"])
	}
	if types["commit"] != "So the thing is," {
		t.Errorf("commit = %q", types["commit"])
	}
}

// The Streamer's Err channel carries session failures that do not stop the
// recording. They must reach the consumer as events, not as stderr noise it
// never sees.
func TestPumpErrorsMarksSessionFailuresNonFatal(t *testing.T) {
	buf := &bytes.Buffer{}
	errs := make(chan error, 1)
	errs <- errors.New("elevenlabs error (rate_limited): slow down")
	close(errs)

	pumpErrors(stream.NewEmitter(buf), errs)

	line := decodeStreamLines(t, buf.String())[0]
	if line["type"] != "error" {
		t.Errorf("type = %v", line["type"])
	}
	if line["scope"] != "stream" {
		t.Errorf("scope = %v, want stream", line["scope"])
	}
	if line["fatal"] != false {
		t.Errorf("fatal = %v; the recording keeps going after a stream error", line["fatal"])
	}
	if !strings.Contains(line["message"].(string), "rate_limited") {
		t.Errorf("message = %v", line["message"])
	}
}

func TestEndReasonForSignal(t *testing.T) {
	if got := endReason(true, nil); got != stream.ReasonSignal {
		t.Errorf("endReason(signalled) = %q, want signal", got)
	}
	if got := endReason(false, nil); got != stream.ReasonStopped {
		t.Errorf("endReason(clean) = %q, want stopped", got)
	}
	if got := endReason(false, errors.New("boom")); got != stream.ReasonError {
		t.Errorf("endReason(failed) = %q, want error", got)
	}
	// A signal is a deliberate stop, so it outranks whatever non-zero status
	// ffmpeg produced while tearing down.
	if got := endReason(true, errors.New("exit status 255")); got != stream.ReasonSignal {
		t.Errorf("endReason(signalled, ffmpeg error) = %q, want signal", got)
	}
}

func TestEndExitCode(t *testing.T) {
	if got := endExitCode(true, errors.New("exit status 255")); got != 0 {
		t.Errorf("a deliberate stop is not a failure, got exit_code %d", got)
	}
	if got := endExitCode(false, errors.New("boom")); got != 1 {
		t.Errorf("got %d, want 1", got)
	}
	if got := endExitCode(false, nil); got != 0 {
		t.Errorf("got %d, want 0", got)
	}
}

func math_Inf_neg() float64 { return neg_inf }
```

Add to the top of the file, after the imports:

```go
import "math"

var neg_inf = math.Inf(-1)
```

Fold that into the single import block rather than adding a second one; the split above is only for legibility here.

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
cd /home/joe/Development/audiomemo && go test ./cmd/ 2>&1 | tail -6
```

Expected: `undefined: pumpLevels`, `undefined: pumpText`, `undefined: pumpErrors`, `undefined: endReason`, `undefined: endExitCode`.

- [ ] **Step 3: Write `cmd/record_stream.go`**

```go
package cmd

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"sync"
	"syscall"
	"time"

	"github.com/joegoldin/audiomemo/internal/config"
	"github.com/joegoldin/audiomemo/internal/record"
	"github.com/joegoldin/audiomemo/internal/stream"
	"github.com/joegoldin/audiomemo/internal/transcribe"
)

// levelInterval is the coalescing window for mic readings. ffmpeg prints one
// RMS line per 480 samples, so 50 ms turns ~100 events/s into 20.
const levelInterval = 50 * time.Millisecond

// pumpLevels forwards ffmpeg's RMS readings as level events until the
// recorder closes the channel, which it does when ffmpeg exits.
func pumpLevels(em *stream.Emitter, levels <-chan float64, th *stream.LevelThrottle) {
	for db := range levels {
		if peak, ok := th.Push(db); ok {
			em.Level(stream.NormalizeLevel(peak), stream.ClampDB(peak))
		}
	}
}

// pumpText forwards the Streamer's two text channels. Partial replaces the
// previous partial; commit is final and appended. Stop() closes both, which
// is how this returns.
func pumpText(em *stream.Emitter, partial, committed <-chan string) {
	var wg sync.WaitGroup
	wg.Add(2)
	go func() {
		defer wg.Done()
		for text := range partial {
			em.Partial(text)
		}
	}()
	go func() {
		defer wg.Done()
		for text := range committed {
			em.Commit(text)
		}
	}()
	wg.Wait()
}

// pumpErrors forwards session failures from the realtime backend. They are
// never fatal to the recording: the Streamer either reconnects or gives up,
// and ffmpeg keeps writing the audio file either way.
func pumpErrors(em *stream.Emitter, errs <-chan error) {
	for err := range errs {
		em.Error(stream.ScopeStream, false, err)
	}
}

// endReason classifies why the stream is closing. A signal outranks a
// non-zero ffmpeg status, because tearing down the PCM pipe on stop routinely
// produces one and the user still got what they asked for.
func endReason(signalled bool, runErr error) string {
	switch {
	case signalled:
		return stream.ReasonSignal
	case runErr != nil:
		return stream.ReasonError
	default:
		return stream.ReasonStopped
	}
}

func endExitCode(signalled bool, runErr error) int {
	if signalled || runErr == nil {
		return 0
	}
	return 1
}

// runRecordStream is the --stream counterpart of runRecord's --no-tui branch.
// It receives an already-started streamer (or nil plus the reason it is nil)
// so the start event's mode is a fact rather than an intention.
func runRecordStream(
	cfg *config.Config,
	opts record.RecordOpts,
	rec *record.Recorder,
	streamer *transcribe.Streamer,
	streamErr error,
	batchTranscribe bool,
) error {
	em := stream.NewEmitter(os.Stdout)

	// The streamer failed to connect but the recording is fine, so the
	// consumer is told and the run continues without partials.
	if streamErr != nil {
		em.Error(stream.ScopeStream, false, streamErr)
	}

	mode := resolveStreamMode(streamer != nil, batchTranscribe)
	startEv := stream.StartEvent{
		Device:      opts.Device,
		DeviceLabel: opts.DeviceLabel,
		Devices:     opts.Devices,
		Path:        opts.OutputPath,
		Format:      opts.Format,
		SampleRate:  opts.SampleRate,
		Channels:    opts.Channels,
		Mode:        mode,
	}
	if streamer != nil {
		startEv.Backend = transcribe.RealtimeBackendName
	}
	em.Start(startEv)

	var pumps sync.WaitGroup
	pumps.Add(1)
	go func() { defer pumps.Done(); pumpLevels(em, rec.Level, stream.NewLevelThrottle(levelInterval)) }()
	if streamer != nil {
		pumps.Add(2)
		go func() { defer pumps.Done(); pumpText(em, streamer.Partial, streamer.Committed) }()
		go func() { defer pumps.Done(); pumpErrors(em, streamer.Err) }()
	}

	// --no-tui has no signal handler today: Ctrl+C kills the process and
	// ffmpeg finalises the file on its own. A consumer needs more than that,
	// so --stream stops ffmpeg the same graceful way the TUI's `q` does and
	// then closes the stream deliberately.
	sigCtx, stopSignals := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stopSignals()

	signalled := make(chan struct{})
	var signalOnce sync.Once
	go func() {
		<-sigCtx.Done()
		// Restore the default disposition first, so a second Ctrl+C kills the
		// process outright rather than waiting on a wedged ffmpeg.
		stopSignals()
		signalOnce.Do(func() { close(signalled) })
		rec.Stop()
	}()

	runErr := <-rec.Done
	wasSignalled := false
	select {
	case <-signalled:
		wasSignalled = true
	default:
	}

	if err := rec.Wait(); err != nil && !wasSignalled {
		// ffmpeg exits non-zero on a broken PCM pipe even when the audio file
		// is valid, so this is reported and not returned.
		em.Error(stream.ScopeRecord, false, err)
	}

	if streamer != nil {
		streamer.Stop()
	}
	pumps.Wait()

	if promoted, err := promoteLiveTranscript(opts.OutputPath); err != nil {
		em.Error(stream.ScopeRecord, false, fmt.Errorf("promoting live transcript: %w", err))
	} else if promoted != "" {
		_ = promoted
	}

	emitFinal(em, cfg, opts.OutputPath, streamer, batchTranscribe)

	em.End(stream.EndEvent{
		Reason:   endReason(wasSignalled, runErr),
		Path:     opts.OutputPath,
		ExitCode: endExitCode(wasSignalled, runErr),
	})
	return nil
}
```

`emitFinal` lands in Task 5. Until then, stub it so this task compiles and its tests run:

```go
func emitFinal(em *stream.Emitter, cfg *config.Config, audioPath string, streamer *transcribe.Streamer, batchTranscribe bool) {
}
```

- [ ] **Step 4: Branch into it from `runRecord`**

In `runRecord`, replace the `if rNoTUI { ... }` block:

```go
	var model *tui.Model
	if rNoTUI {
		fmt.Fprintf(os.Stderr, "Recording to %s (Ctrl+C to stop)...\n", outputPath)
		if err := <-rec.Done; err != nil {
			return err
		}
	} else {
```

with:

```go
	var model *tui.Model
	if rStream {
		// The start event carries the same facts as the stderr line the plain
		// headless path prints, so that line is redundant here.
		return runRecordStream(cfg, opts, rec, streamer, streamStartErr, shouldTranscribe)
	} else if rNoTUI {
		fmt.Fprintf(os.Stderr, "Recording to %s (Ctrl+C to stop)...\n", outputPath)
		if err := <-rec.Done; err != nil {
			return err
		}
	} else {
```

and capture the streamer start failure so `runRecordStream` can report it. In the `if streamer != nil { ... }` block above, add a `streamStartErr` variable:

```go
	var streamStartErr error
	if streamer != nil {
		transcriptPath := liveTranscriptPathFor(outputPath)
		if err := streamer.Start(context.Background(), rec.PCMReader, transcriptPath); err != nil {
			if !rStream {
				fmt.Fprintf(os.Stderr, "Warning: live transcription failed to start: %v\n", err)
			}
			streamStartErr = err
			streamNote = fmt.Sprintf("live transcription unavailable: %v", err)
			streamer = nil
			go io.Copy(io.Discard, rec.PCMReader)
		}
	} else if streamNote != "" && rStream {
		// "no ElevenLabs API key configured" is the note the TUI shows; under
		// --stream the same fact reaches the consumer as an error event.
		streamStartErr = errors.New(streamNote)
	}
```

Add `"errors"` to the imports.

- [ ] **Step 5: Run the tests**

Run:
```bash
cd /home/joe/Development/audiomemo && gofmt -l . | grep -v '^vendor/' ; go test ./cmd/ ./internal/... 2>&1 | grep -v '^ok' | head
```

Expected: no output from either command.

- [ ] **Step 6: Verify the stream against a live microphone**

This one needs hardware, so it is a manual check rather than a test. Run:

```bash
cd /home/joe/Development/audiomemo && go build -o /tmp/audiomemo . && \
  (/tmp/audiomemo record --stream --temp --no-live-transcription -D default probe & \
   sleep 3; kill -INT %1; wait) 2>/dev/null | head -8
```

Expected: a `start` line with `"mode":"none"`, several `level` lines roughly 50 ms apart, then `end` with `"reason":"signal"` and `"exit_code":0`. If `level` lines arrive far faster than 20 a second, `levelInterval` is not being applied.

- [ ] **Step 7: Commit**

```bash
cd /home/joe/Development/audiomemo
git add -A
git commit -m "feat(record): --stream run loop and deliberate termination

Levels, partials, commits, and stream errors pump into the emitter from
their own goroutines; the emitter's mutex is what keeps lines whole. The
signal handler stops ffmpeg the graceful way and then restores the
default disposition, so a second Ctrl+C is not blocked by a wedged
encoder. A signal exits zero: a deliberate stop is not a failure, and it
outranks the non-zero status ffmpeg produces when the PCM pipe tears down."
```

---

### Task 5: The `final` event

Where the text comes from, and which backend produced it. This is the only event the consumer pastes into an editor, so it is worth its own task.

**Files:** (all in `/home/joe/Development/audiomemo`)
- Modify: `cmd/record.go` (split `runPostTranscribe` so both paths share one command builder)
- Modify: `cmd/record_stream.go` (`emitFinal`)
- Modify: `cmd/record_stream_test.go`

**Interfaces:**
- Consumes: `buildPostTranscribeArgs` (existing), `transcribe.NewDispatcher`, `stream.FinalEvent`
- Produces:
  - `func newPostTranscribeCmd(audioPath string) (*exec.Cmd, []string, error)`
  - `func runPostTranscribeCapture(audioPath string) (string, error)`
  - `func backendFromArgs(cfg *config.Config, args []string) string`
  - `func emitFinal(em *stream.Emitter, cfg *config.Config, audioPath string, streamer *transcribe.Streamer, batchTranscribe bool)`

- [ ] **Step 1: Write the failing test**

Append to `cmd/record_stream_test.go`:

```go
func TestBackendFromArgsTakesTheLastOccurrence(t *testing.T) {
	cfg := config.Default()
	// recw appends its local-only backend after the user's --transcribe-args
	// precisely so it wins; cobra keeps the final occurrence.
	args := []string{"--language", "en", "--backend", "elevenlabs", "--backend", "whisper-cpp", "memo.ogg"}
	if got := backendFromArgs(cfg, args); got != "whisper-cpp" {
		t.Errorf("backendFromArgs = %q, want whisper-cpp", got)
	}
}

func TestBackendFromArgsHonoursTheShortFlag(t *testing.T) {
	cfg := config.Default()
	if got := backendFromArgs(cfg, []string{"-b", "deepgram", "memo.ogg"}); got != "deepgram" {
		t.Errorf("backendFromArgs = %q, want deepgram", got)
	}
}

// With no explicit backend the subprocess autodetects from the same config
// this process loaded, so resolving it here gives the same answer.
func TestBackendFromArgsFallsBackToAutodetect(t *testing.T) {
	cfg := config.Default()
	cfg.Transcribe.Deepgram.APIKey = "dg-key"
	if got := backendFromArgs(cfg, []string{"memo.ogg"}); got != "deepgram" {
		t.Errorf("backendFromArgs = %q, want deepgram from autodetect", got)
	}
}

func TestBackendFromArgsIsEmptyWhenNoBackendExists(t *testing.T) {
	cfg := config.Default()
	cfg.Transcribe.Whisper.Binary = "definitely-not-a-real-binary"
	got := backendFromArgs(cfg, []string{"memo.ogg"})
	// Autodetect may still find a local whisper on the developer's machine;
	// the contract is only that it never panics and never invents a name.
	if got != "" && !strings.Contains(got, "whisper") {
		t.Errorf("backendFromArgs = %q, want empty or a whisper variant", got)
	}
}

func TestEmitFinalSkippedWhenThereIsNoText(t *testing.T) {
	buf := &bytes.Buffer{}
	em := stream.NewEmitter(buf)
	emitFinal(em, config.Default(), "/tmp/memo.ogg", nil, false)
	if buf.Len() != 0 {
		t.Errorf("a run with no transcript emitted %q", buf.String())
	}
}
```

Add `"github.com/joegoldin/audiomemo/internal/config"` to the test file's imports.

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
cd /home/joe/Development/audiomemo && go test ./cmd/ 2>&1 | tail -4
```

Expected: `undefined: backendFromArgs`.

- [ ] **Step 3: Split the command builder in `cmd/record.go`**

Replace `runPostTranscribe` with a builder plus two thin callers, so the streaming path reuses every existing flag rather than reimplementing them:

```go
// newPostTranscribeCmd builds the batch transcription subprocess and returns
// the argument list alongside it, so callers can inspect which backend the
// subprocess will resolve without re-deriving it.
func newPostTranscribeCmd(audioPath string) (*exec.Cmd, []string, error) {
	self, err := os.Executable()
	if err != nil {
		self = "transcribe"
	}
	args, err := buildPostTranscribeArgs(audioPath, rTranscribeArgs, rVerbose, rWhisperShortcut, exec.LookPath)
	if err != nil {
		return nil, nil, err
	}
	return exec.Command(self, append([]string{"transcribe"}, args...)...), args, nil
}

func runPostTranscribe(audioPath string) error {
	cmd, _, err := newPostTranscribeCmd(audioPath)
	if err != nil {
		return err
	}
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

// runPostTranscribeCapture runs the same batch pass with stdout captured.
// Under --stream, stdout carries NDJSON, and a transcript written straight
// into it would break the consumer's line parser. Stderr still goes to fd 2:
// whisper's and ffmpeg's diagnostics are not audiomemo's to reformat.
func runPostTranscribeCapture(audioPath string) (string, []string, error) {
	cmd, args, err := newPostTranscribeCmd(audioPath)
	if err != nil {
		return "", nil, err
	}
	var out bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = os.Stderr
	err = cmd.Run()
	return strings.TrimRight(out.String(), "\n"), args, err
}
```

Add `"bytes"` to the imports.

- [ ] **Step 4: Implement `backendFromArgs` and `emitFinal` in `cmd/record_stream.go`**

```go
// backendFromArgs reports which backend the batch subprocess will use. It
// scans for the last --backend/-b because cobra keeps the final occurrence,
// which is exactly why recw appends its local-only backend after the user's
// --transcribe-args. With no explicit backend the subprocess autodetects from
// the same config this process loaded, so resolving it here agrees.
func backendFromArgs(cfg *config.Config, args []string) string {
	name := ""
	for i := 0; i < len(args)-1; i++ {
		if args[i] == "--backend" || args[i] == "-b" {
			name = args[i+1]
		}
	}
	backend, err := transcribe.NewDispatcher(cfg, name)
	if err != nil {
		return name
	}
	return backend.Name()
}

// emitFinal writes at most one final event. The batch pass wins when it ran
// and produced text, because it is the diarised, higher-quality result; the
// live transcript is the fallback when batch was not asked for or failed,
// mirroring how the TUI path promotes <base>-live.txt before overwriting it.
func emitFinal(em *stream.Emitter, cfg *config.Config, audioPath string, streamer *transcribe.Streamer, batchTranscribe bool) {
	liveText := ""
	if streamer != nil {
		liveText = strings.TrimSpace(streamer.FullText())
	}
	transcriptPath := transcriptPathFor(audioPath, transcribe.FormatText)

	if batchTranscribe {
		text, args, err := runPostTranscribeCapture(audioPath)
		if err != nil {
			em.Error(stream.ScopeTranscribe, false, err)
		} else if strings.TrimSpace(text) != "" {
			em.Final(stream.FinalEvent{
				Text:           text,
				Path:           audioPath,
				TranscriptPath: transcriptPath,
				Backend:        backendFromArgs(cfg, args),
				Source:         stream.SourceBatch,
			})
			return
		}
	}

	if liveText == "" {
		return
	}
	em.Final(stream.FinalEvent{
		Text:           liveText,
		Path:           audioPath,
		TranscriptPath: transcriptPath,
		Backend:        transcribe.RealtimeBackendName,
		Source:         stream.SourceLive,
	})
}
```

Add `"strings"` and `"github.com/joegoldin/audiomemo/internal/config"` to the imports, and delete the Task 4 stub.

- [ ] **Step 5: Run the tests**

Run:
```bash
cd /home/joe/Development/audiomemo && gofmt -l . | grep -v '^vendor/' ; go test ./... 2>&1 | grep -v '^ok' | head
```

Expected: no output.

- [ ] **Step 6: Verify the batch path end to end**

Run, using the repo's own fixture rather than a live mic:

```bash
cd /home/joe/Development/audiomemo && go build -o /tmp/audiomemo . && \
  /tmp/audiomemo transcribe --backend whisper-cpp testdata/test.ogg | head -2
```

Expected: the transcript text on stdout. If `whisper-cli` is not installed this fails, which tells you the local backend is missing rather than that `emitFinal` is wrong; the same command is what `runPostTranscribeCapture` shells out to.

- [ ] **Step 7: Commit**

```bash
cd /home/joe/Development/audiomemo
git add -A
git commit -m "feat(record): final event, with the batch pass captured

The batch transcribe subprocess normally inherits stdout, which under
--stream would inject a raw transcript into the NDJSON. It now runs with
stdout captured and its output travels as final.text. The backend name
is read back from the built argument list rather than guessed, which is
why recw's appended --backend resolves correctly: cobra keeps the last
occurrence and so does this."
```

---

### Task 6: Integration coverage for the flag contract

The existing `integration_test.go` builds the binary and runs it. Extend it with the parts of `--stream` that hold without a microphone: the rejections, the help text, and the non-stream stdout contract that must not have moved.

**Files:** (all in `/home/joe/Development/audiomemo`)
- Modify: `integration_test.go`
- Modify: `flake.nix` (nothing structural; confirm the check still passes)

**Interfaces:**
- Consumes: the `run` helper at `integration_test.go:31`
- Produces: no new exported surface

- [ ] **Step 1: Write the failing test**

Append to `integration_test.go`:

```go
// ---------------------------------------------------------------------------
// record --stream
// ---------------------------------------------------------------------------

func TestRecordStreamRejectsClips(t *testing.T) {
	_, stderr, err := run(t, "record", "--stream", "--clips", "notes")
	if err == nil {
		t.Fatal("--stream --clips should fail")
	}
	if !strings.Contains(stderr, "--clips") {
		t.Errorf("stderr should name the offending flag, got %q", stderr)
	}
}

func TestRecordStreamRejectsListDevices(t *testing.T) {
	_, stderr, err := run(t, "record", "--stream", "--list-devices")
	if err == nil {
		t.Fatal("--stream --list-devices should fail")
	}
	if !strings.Contains(stderr, "device list") {
		t.Errorf("stderr should point at the alternative, got %q", stderr)
	}
}

// Rejections must not put anything on stdout, or a consumer that started
// parsing before checking the exit status would see a half-stream.
func TestRecordStreamRejectionsKeepStdoutClean(t *testing.T) {
	stdout, _, _ := run(t, "record", "--stream", "--clips", "notes")
	if stdout != "" {
		t.Errorf("stdout = %q, want empty", stdout)
	}
}

func TestRecordHelpDocumentsStream(t *testing.T) {
	stdout, _, err := run(t, "record", "--help")
	if err != nil {
		t.Fatalf("record --help failed: %v", err)
	}
	if !strings.Contains(stdout, "--stream") {
		t.Error("record --help does not mention --stream")
	}
	if !strings.Contains(stdout, "newline-delimited JSON") {
		t.Error("the --stream help text should say what it emits")
	}
}

// The regression gate for the flag's whole premise: without --stream, record
// still prints one bare path and nothing else, so `transcribe $(record)` works.
func TestRecordWithoutStreamStillListsDevicesAsText(t *testing.T) {
	stdout, _, err := run(t, "record", "--list-devices")
	if err != nil {
		t.Skipf("no audio device layer available: %v", err)
	}
	for _, line := range strings.Split(strings.TrimSpace(stdout), "\n") {
		if line == "" {
			continue
		}
		if strings.HasPrefix(strings.TrimSpace(line), "{") {
			t.Errorf("plain --list-devices emitted JSON: %q", line)
		}
	}
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
cd /home/joe/Development/audiomemo && go test -run 'TestRecordStream|TestRecordHelp' . 2>&1 | tail -6
```

Expected: the two rejection tests fail because `--stream` does not exist yet at HEAD~; after Tasks 3-5 they pass. If they already pass here, Task 3 landed and this step is a confirmation rather than a red bar.

- [ ] **Step 3: Run everything**

Run:
```bash
cd /home/joe/Development/audiomemo && go test ./... 2>&1 | tail -12
```

Expected: `ok` for every package. `integration_test.go` builds the binary itself in `TestMain`, so this covers the real argv path including the `record`/`rect`/`recw` dispatch in `main.go`.

- [ ] **Step 4: Build through Nix**

Run:
```bash
cd /home/joe/Development/audiomemo && nix build .#audiomemo && ./result/bin/record --help | grep -A1 -- '--stream'
nix flake check 2>&1 | tail -5
```

Expected: the flag appears in the help output, and `nix flake check` passes. The flake's `checks.default` runs `go test` with `whisper-cpp` and a fetched base model in `nativeBuildInputs`, so the batch path is exercised in the sandbox too.

- [ ] **Step 5: Commit and push**

```bash
cd /home/joe/Development/audiomemo
git add -A
git commit -m "test: integration coverage for the --stream flag contract

Covers the rejections, their clean stdout, and the help text. The last
test is the regression gate for the premise of the flag: without
--stream, record's stdout is unchanged."
git push
```

- [ ] **Step 6: Record the new revision for the consumers**

```bash
cd /home/joe/Development/audiomemo && git rev-parse --short HEAD
```

Note the revision. Task 11 and Task 12 bump the `audiomemo` flake input to it; the pin in `dotfiles/flake.lock` is `6018d29` today.

---

### Task 7: `pi-voice` scaffold: parsing, config, and width maths

The first TypeScript task. Everything here is pure and testable without pi and without a microphone.

**Files:** (all in `/home/joe/Development/pi-nix`)
- Create: `packages/first-party/pi-voice/package.json`
- Create: `packages/first-party/pi-voice/voice.ts`
- Create: `packages/first-party/pi-voice/voice.test.ts`

**Interfaces:**
- Consumes: the NDJSON schema from Task 1
- Produces:
  - `type VoiceEvent` (a discriminated union over `type`)
  - `function parseEvent(line: string): VoiceEvent | undefined`
  - `function createLineSplitter(onLine: (line: string) => void): (chunk: string) => void`
  - `function readVoiceConfig(env: Record<string, string | undefined>): VoiceConfig`
  - `function visibleWidth(s: string): number`
  - `function truncateToWidth(s: string, width: number): string`
  - `class Meter` with `push(level: number)` and `get level()`

- [ ] **Step 1: Write `package.json`**

```json
{
  "name": "@joegoldin/pi-voice",
  "version": "0.1.0",
  "description": "Dictation for pi, over audiomemo record --stream",
  "license": "MIT",
  "type": "module",
  "keywords": ["pi-package", "voice", "dictation"],
  "pi": {
    "extensions": ["./voice.ts"]
  },
  "scripts": {
    "test": "bun test"
  }
}
```

- [ ] **Step 2: Write the failing test**

Create `packages/first-party/pi-voice/voice.test.ts`:

```typescript
import { describe, expect, it } from "bun:test";

import {
  createLineSplitter,
  Meter,
  parseEvent,
  readVoiceConfig,
  truncateToWidth,
  visibleWidth,
} from "./voice";

describe("parseEvent", () => {
  it("reads every event type audiomemo emits", () => {
    expect(parseEvent('{"type":"start","t":0,"path":"/tmp/x.ogg","mode":"live"}')).toMatchObject({
      type: "start",
      path: "/tmp/x.ogg",
      mode: "live",
    });
    expect(parseEvent('{"type":"level","t":50,"rms":0.21,"db":-47.4}')).toMatchObject({
      type: "level",
      rms: 0.21,
      db: -47.4,
    });
    expect(parseEvent('{"type":"partial","t":900,"text":"so the"}')).toMatchObject({ type: "partial", text: "so the" });
    expect(parseEvent('{"type":"commit","t":1400,"text":"So the"}')).toMatchObject({ type: "commit", text: "So the" });
    expect(parseEvent('{"type":"final","t":9000,"text":"Done.","source":"batch"}')).toMatchObject({
      type: "final",
      text: "Done.",
      source: "batch",
    });
    expect(parseEvent('{"type":"error","t":1,"scope":"stream","fatal":false,"message":"nope"}')).toMatchObject({
      type: "error",
      scope: "stream",
      fatal: false,
    });
    expect(parseEvent('{"type":"end","t":9100,"reason":"signal","exit_code":0}')).toMatchObject({
      type: "end",
      reason: "signal",
    });
  });

  // A stray line must never take the session down with it.
  it("returns undefined rather than throwing on junk", () => {
    expect(parseEvent("not json")).toBeUndefined();
    expect(parseEvent("")).toBeUndefined();
    expect(parseEvent("   ")).toBeUndefined();
    expect(parseEvent("[1,2,3]")).toBeUndefined();
    expect(parseEvent('{"no":"type"}')).toBeUndefined();
  });

  // The schema is allowed to grow; unknown types are skipped, not fatal.
  it("skips event types it does not know", () => {
    expect(parseEvent('{"type":"device","t":0,"name":"mic"}')).toBeUndefined();
  });
});

describe("createLineSplitter", () => {
  it("reassembles objects split across chunk boundaries", () => {
    const lines: string[] = [];
    const feed = createLineSplitter((l) => lines.push(l));
    feed('{"type":"lev');
    feed('el","t":1}\n{"type":"par');
    feed('tial","t":2}\n');
    expect(lines).toEqual(['{"type":"level","t":1}', '{"type":"partial","t":2}']);
  });

  it("holds a trailing partial line until its newline arrives", () => {
    const lines: string[] = [];
    const feed = createLineSplitter((l) => lines.push(l));
    feed('{"a":1}\n{"b":2}');
    expect(lines).toEqual(['{"a":1}']);
    feed("\n");
    expect(lines).toEqual(['{"a":1}', '{"b":2}']);
  });

  it("tolerates CRLF", () => {
    const lines: string[] = [];
    const feed = createLineSplitter((l) => lines.push(l));
    feed('{"a":1}\r\n');
    expect(lines).toEqual(['{"a":1}']);
  });
});

describe("readVoiceConfig", () => {
  it("defaults to the record binary on PATH", () => {
    const cfg = readVoiceConfig({});
    expect(cfg.recordBin).toBe("record");
    expect(cfg.recordArgs).toEqual(["--stream", "-t"]);
    expect(cfg.barWidth).toBe(12);
    expect(cfg.placement).toBe("belowEditor");
  });

  // Nix passes an absolute store path so the jail does not have to guess.
  it("takes the binary and extra args from the environment", () => {
    const cfg = readVoiceConfig({
      PI_VOICE_RECORD_BIN: "/nix/store/abc-audiomemo/bin/record",
      PI_VOICE_RECORD_ARGS: "-D mic --temp",
    });
    expect(cfg.recordBin).toBe("/nix/store/abc-audiomemo/bin/record");
    expect(cfg.recordArgs).toEqual(["--stream", "-t", "-D", "mic", "--temp"]);
  });

  it("never lets a caller drop --stream", () => {
    const cfg = readVoiceConfig({ PI_VOICE_RECORD_ARGS: "--no-tui" });
    expect(cfg.recordArgs[0]).toBe("--stream");
  });

  it("reads the bar width and clamps nonsense", () => {
    expect(readVoiceConfig({ PI_VOICE_BAR_WIDTH: "20" }).barWidth).toBe(20);
    expect(readVoiceConfig({ PI_VOICE_BAR_WIDTH: "0" }).barWidth).toBe(1);
    expect(readVoiceConfig({ PI_VOICE_BAR_WIDTH: "nope" }).barWidth).toBe(12);
  });
});

describe("visibleWidth", () => {
  it("ignores SGR sequences", () => {
    expect(visibleWidth("\x1b[31mred\x1b[39m")).toBe(3);
  });

  it("counts East Asian wide characters as two cells", () => {
    expect(visibleWidth("日本語")).toBe(6);
    expect(visibleWidth("ab日")).toBe(4);
  });

  it("counts the block glyphs the meter draws as one cell each", () => {
    expect(visibleWidth("████░░░░")).toBe(8);
  });
});

describe("truncateToWidth", () => {
  it("leaves a string that already fits", () => {
    expect(truncateToWidth("hello", 10)).toBe("hello");
  });

  it("cuts to the requested width", () => {
    expect(truncateToWidth("hello world", 5)).toBe("hello");
  });

  // Cutting mid-sequence would leak an unterminated colour into the next row.
  it("keeps SGR sequences whole and resets at the cut", () => {
    const out = truncateToWidth("\x1b[31mhello world\x1b[39m", 5);
    expect(visibleWidth(out)).toBe(5);
    expect(out.endsWith("\x1b[0m")).toBe(true);
  });

  it("never splits a wide character across the boundary", () => {
    const out = truncateToWidth("a日本", 2);
    expect(visibleWidth(out)).toBeLessThanOrEqual(2);
    expect(out.startsWith("a")).toBe(true);
  });
});

describe("Meter", () => {
  // Same attack and decay as audiomemo's TUI meter, so the mic feels the same
  // in pi as it does in `record`.
  it("rises fast and falls slow", () => {
    const m = new Meter();
    m.push(1);
    expect(m.level).toBeCloseTo(0.5, 6);
    m.push(1);
    expect(m.level).toBeCloseTo(0.75, 6);
    m.push(0);
    expect(m.level).toBeCloseTo(0.6375, 6);
  });

  it("stays inside 0..1", () => {
    const m = new Meter();
    for (let i = 0; i < 50; i++) m.push(5);
    expect(m.level).toBeLessThanOrEqual(1);
    for (let i = 0; i < 200; i++) m.push(-5);
    expect(m.level).toBeGreaterThanOrEqual(0);
  });
});
```

- [ ] **Step 3: Run the test to verify it fails**

Run:
```bash
cd /home/joe/Development/pi-nix/packages/first-party/pi-voice && bun test 2>&1 | tail -5
```

Expected: `error: Cannot find module './voice'`.

- [ ] **Step 4: Implement the pure half of `voice.ts`**

```typescript
// pi-voice: dictation for pi, driven by `audiomemo record --stream`.
//
// Everything about devices, backends, formats, and secrets stays in
// audiomemo. This file owns exactly three things: reading the NDJSON,
// drawing it, and telling the statusline the mic is live.
//
// It imports nothing. pi injects @earendil-works/pi-tui as a jiti virtual
// module at runtime (core/extensions/loader.ts:50-74), so an import would
// resolve when pi loads this file from a bare store path, but it would not
// resolve under `bun test` in the Nix check sandbox. The width maths below is
// the price of testing the code that ships.

// ── The wire format ───────────────────────────────────────────────────────

export interface StartEvent {
  type: "start";
  t: number;
  device?: string;
  device_label?: string;
  devices?: string[];
  path?: string;
  format?: string;
  sample_rate?: number;
  channels?: number;
  mode: "live" | "batch" | "none";
  backend?: string;
}

export interface LevelEvent { type: "level"; t: number; rms: number; db: number }
export interface TextEvent { type: "partial" | "commit"; t: number; text: string }
export interface FinalEvent {
  type: "final";
  t: number;
  text: string;
  path?: string;
  transcript_path?: string;
  backend?: string;
  source: "live" | "batch";
}
export interface ErrorEvent {
  type: "error";
  t: number;
  scope: "record" | "stream" | "transcribe" | "config";
  fatal: boolean;
  message: string;
}
export interface EndEvent {
  type: "end";
  t: number;
  reason: "stopped" | "signal" | "error";
  path?: string;
  exit_code: number;
}

export type VoiceEvent = StartEvent | LevelEvent | TextEvent | FinalEvent | ErrorEvent | EndEvent;

const KNOWN_TYPES = new Set(["start", "level", "partial", "commit", "final", "error", "end"]);

/** Parse one NDJSON line. Junk and unknown types return undefined: a stray
 *  line must never take the session down, and the schema is allowed to grow. */
export function parseEvent(line: string): VoiceEvent | undefined {
  const trimmed = line.trim();
  if (trimmed === "") return undefined;
  let parsed: unknown;
  try {
    parsed = JSON.parse(trimmed);
  } catch {
    return undefined;
  }
  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) return undefined;
  const type = (parsed as { type?: unknown }).type;
  if (typeof type !== "string" || !KNOWN_TYPES.has(type)) return undefined;
  return parsed as VoiceEvent;
}

/** Reassemble whole lines from arbitrary stdout chunks. A 4 KiB read can end
 *  mid-object, and JSON.parse on half an object throws. */
export function createLineSplitter(onLine: (line: string) => void): (chunk: string) => void {
  let pending = "";
  return (chunk: string) => {
    pending += chunk;
    for (;;) {
      const idx = pending.indexOf("\n");
      if (idx < 0) break;
      const line = pending.slice(0, idx).replace(/\r$/, "");
      pending = pending.slice(idx + 1);
      if (line !== "") onLine(line);
    }
  };
}

// ── Configuration ─────────────────────────────────────────────────────────

export interface VoiceConfig {
  recordBin: string;
  recordArgs: string[];
  barWidth: number;
  placement: "aboveEditor" | "belowEditor";
  mode: string;
}

/** Read configuration from the environment. ExtensionContext exposes no
 *  settings reader, so Nix hands values in as environment variables. */
export function readVoiceConfig(env: Record<string, string | undefined>): VoiceConfig {
  const extra = (env.PI_VOICE_RECORD_ARGS ?? "").trim();
  // -t is a default rather than an implication in audiomemo, so pi-voice asks
  // for it explicitly: without a batch pass a run with no ElevenLabs key
  // produces no text at all.
  const recordArgs = ["--stream", "-t", ...(extra === "" ? [] : extra.split(/\s+/))];

  let barWidth = 12;
  const raw = env.PI_VOICE_BAR_WIDTH;
  if (raw !== undefined) {
    const n = Number.parseInt(raw, 10);
    if (Number.isFinite(n)) barWidth = Math.max(1, Math.min(64, n));
  }

  return {
    recordBin: env.PI_VOICE_RECORD_BIN ?? "record",
    recordArgs,
    barWidth,
    placement: env.PI_VOICE_PLACEMENT === "aboveEditor" ? "aboveEditor" : "belowEditor",
    mode: env.PI_VOICE_MODE ?? "toggle",
  };
}

// ── Width maths ───────────────────────────────────────────────────────────

// Matches CSI sequences, which is all the theme emits: theme.fg produces
// `${sgr}${text}\x1b[39m`.
const ANSI_RE = /\x1b\[[0-9;]*[A-Za-z]/g;

// East Asian Wide and Fullwidth ranges, plus emoji. Under-counting would let a
// row exceed the width pi gave us, which the differential renderer will not
// forgive; over-counting only truncates early.
const WIDE_RANGES: Array<[number, number]> = [
  [0x1100, 0x115f], [0x2e80, 0x303e], [0x3041, 0x33ff], [0x3400, 0x4dbf],
  [0x4e00, 0x9fff], [0xa000, 0xa4cf], [0xac00, 0xd7a3], [0xf900, 0xfaff],
  [0xfe30, 0xfe6f], [0xff00, 0xff60], [0xffe0, 0xffe6],
  [0x1f300, 0x1f64f], [0x1f900, 0x1f9ff], [0x20000, 0x3fffd],
];

function charWidth(cp: number): number {
  for (const [lo, hi] of WIDE_RANGES) if (cp >= lo && cp <= hi) return 2;
  return 1;
}

/** Visible width in terminal cells, ignoring SGR sequences. */
export function visibleWidth(s: string): number {
  let total = 0;
  for (const ch of s.replace(ANSI_RE, "")) total += charWidth(ch.codePointAt(0) ?? 0);
  return total;
}

/** Truncate to a cell width, keeping escape sequences whole and appending a
 *  reset when anything was cut, so a colour cannot leak into the next row. */
export function truncateToWidth(s: string, width: number): string {
  if (width <= 0) return "";
  if (visibleWidth(s) <= width) return s;

  let out = "";
  let used = 0;
  let i = 0;
  while (i < s.length) {
    if (s[i] === "\x1b") {
      const rest = s.slice(i);
      const m = /^\x1b\[[0-9;]*[A-Za-z]/.exec(rest);
      if (m) {
        out += m[0];
        i += m[0].length;
        continue;
      }
    }
    const cp = s.codePointAt(i) ?? 0;
    const ch = String.fromCodePoint(cp);
    const w = charWidth(cp);
    if (used + w > width) break;
    out += ch;
    used += w;
    i += ch.length;
  }
  return `${out}\x1b[0m`;
}

// ── Metering ──────────────────────────────────────────────────────────────

/** Fast attack, slow decay, matching audiomemo's own VUMeter
 *  (internal/tui/vu.go). The wire carries raw readings; smoothing is a
 *  rendering decision and belongs here. */
export class Meter {
  private smoothed = 0;

  push(level: number): void {
    const diff = level - this.smoothed;
    this.smoothed += diff > 0 ? diff * 0.5 : diff * 0.15;
    this.smoothed = Math.max(0, Math.min(1, this.smoothed));
  }

  get level(): number {
    return this.smoothed;
  }
}
```

- [ ] **Step 5: Run the tests**

Run:
```bash
cd /home/joe/Development/pi-nix/packages/first-party/pi-voice && bun test 2>&1 | tail -5
```

Expected: all tests pass. If `truncateToWidth("a日本", 2)` returns three cells, `charWidth` is not being consulted before the append.

- [ ] **Step 6: Commit**

```bash
cd /home/joe/Development/pi-nix
git add packages/first-party/pi-voice
git commit -m "feat(pi-voice): NDJSON parsing, config, width maths, metering

No imports. pi injects @earendil-works/pi-tui as a jiti virtual module at
runtime, so an import would resolve when pi loads this file, but not
under bun test in the Nix check sandbox; owning 40 lines of width maths
buys the tests. Wide characters count as two cells because under-counting
would emit a row wider than pi's render width."
```

---

### Task 8: The voice state file

The contract that makes the mic indicator light up in both harnesses. `agent-statusline`'s `voice` widget reads it already; nothing writes it today, which is why the widget has never fired.

**What the widget actually reads.** `agent-statusline/internal/voice/voice.go` does not read a bespoke state file. It reads the Claude Code settings layers and looks for a `voice` object:

```
producer writes  →  { "voice": { "enabled": true, "mode": "toggle" } }
reader resolves  →  $CWD/.claude/settings.local.json
                    $CWD/.claude/settings.json
                    $DIR/settings.local.json
                    $DIR/settings.json
                    where $DIR = $CLAUDE_CONFIG_DIR, else $HOME/.claude
```

The reader takes the first layer that carries `voice.enabled`; a layer that exists but has no `voice` key does not shadow the layers below it (`voice_test.go:54-65`). A malformed layer is skipped the same way (`:67-77`). All four candidates missing yields `nil` and the widget hides.

**The contract, stated for any producer, not just pi-voice:**

- Write `$CLAUDE_CONFIG_DIR/settings.local.json`, defaulting to `$HOME/.claude/settings.local.json`. That is the user-level mutable layer: `claude-nix` places `settings.json` itself and deep-merges it on every rebuild (`modules/home-manager.nix:1784-1800`), so a producer writing there would fight the activation script. `settings.local.json` is unmanaged.
- Set `voice.enabled` to `true` while the mic is capturing and `false` when it is not. Do not delete the key: `false` is how the widget learns to hide.
- Set `voice.mode` to a short label the widget renders after the glyph. `toggle` and `hold` are the values already in the reader's tests.
- Merge, never overwrite. `settings.local.json` legitimately holds other Claude Code settings.
- Write atomically. The reader can run at any moment, and a torn read makes the widget silently fall through to a lower layer.
- Extra keys are ignored by the reader's typed struct, so a producer may record `pid` and `since` for its own recovery without affecting rendering.

**Files:** (all in `/home/joe/Development/pi-nix`)
- Modify: `packages/first-party/pi-voice/voice.ts`
- Modify: `packages/first-party/pi-voice/voice.test.ts`

**Interfaces:**
- Consumes: `agent-statusline`'s `internal/voice.Reader` semantics
- Produces:
  - `function voiceStatePath(env, homeDir): string`
  - `function writeVoiceState(path: string, state: VoiceState): void`
  - `function clearVoiceState(path: string): void`
  - `function reconcileStaleState(path: string, isAlive: (pid: number) => boolean): void`

- [ ] **Step 1: Write the failing test**

Append to `voice.test.ts`:

```typescript
import { mkdtempSync, readFileSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { clearVoiceState, reconcileStaleState, voiceStatePath, writeVoiceState } from "./voice";

function tmp(): string {
  return mkdtempSync(join(tmpdir(), "pi-voice-"));
}

describe("voiceStatePath", () => {
  // Must match internal/voice/voice.go's NewReader exactly: CLAUDE_CONFIG_DIR
  // when non-empty, otherwise $HOME/.claude.
  it("honours CLAUDE_CONFIG_DIR", () => {
    expect(voiceStatePath({ CLAUDE_CONFIG_DIR: "/etc/claude" }, "/home/joe")).toBe("/etc/claude/settings.local.json");
  });

  it("falls back to $HOME/.claude", () => {
    expect(voiceStatePath({}, "/home/joe")).toBe("/home/joe/.claude/settings.local.json");
  });

  it("treats an empty CLAUDE_CONFIG_DIR as unset, as the Go reader does", () => {
    expect(voiceStatePath({ CLAUDE_CONFIG_DIR: "" }, "/home/joe")).toBe("/home/joe/.claude/settings.local.json");
  });
});

describe("writeVoiceState", () => {
  it("creates the file and the directory when neither exists", () => {
    const dir = tmp();
    const path = join(dir, "nested", "settings.local.json");
    writeVoiceState(path, { enabled: true, mode: "toggle" });
    expect(JSON.parse(readFileSync(path, "utf8"))).toEqual({ voice: { enabled: true, mode: "toggle" } });
  });

  // settings.local.json legitimately holds other Claude Code settings.
  it("merges into an existing file without dropping other keys", () => {
    const dir = tmp();
    const path = join(dir, "settings.local.json");
    writeFileSync(path, JSON.stringify({ permissions: { allow: ["Bash(git log:*)"] }, theme: "dark" }));
    writeVoiceState(path, { enabled: true, mode: "toggle" });
    const got = JSON.parse(readFileSync(path, "utf8"));
    expect(got.permissions).toEqual({ allow: ["Bash(git log:*)"] });
    expect(got.theme).toBe("dark");
    expect(got.voice).toEqual({ enabled: true, mode: "toggle" });
  });

  it("replaces a previous voice block rather than merging into it", () => {
    const dir = tmp();
    const path = join(dir, "settings.local.json");
    writeFileSync(path, JSON.stringify({ voice: { enabled: true, mode: "hold", pid: 42 } }));
    writeVoiceState(path, { enabled: false });
    expect(JSON.parse(readFileSync(path, "utf8")).voice).toEqual({ enabled: false });
  });

  // A file the producer cannot parse must not be destroyed; the producer is a
  // guest in someone else's settings file.
  it("leaves a malformed file alone", () => {
    const dir = tmp();
    const path = join(dir, "settings.local.json");
    writeFileSync(path, "{not json");
    writeVoiceState(path, { enabled: true });
    expect(readFileSync(path, "utf8")).toBe("{not json");
  });

  it("records the pid so a crashed session can be reconciled", () => {
    const dir = tmp();
    const path = join(dir, "settings.local.json");
    writeVoiceState(path, { enabled: true, mode: "toggle", pid: 4242 });
    expect(JSON.parse(readFileSync(path, "utf8")).voice.pid).toBe(4242);
  });

  it("writes through a temp file so a reader never sees a half-written object", () => {
    const dir = tmp();
    const path = join(dir, "settings.local.json");
    writeVoiceState(path, { enabled: true });
    // The temp file must not survive the rename.
    expect(existsSync(`${path}.pi-voice.tmp`)).toBe(false);
  });
});

describe("clearVoiceState", () => {
  // false rather than absent: the reader falls through when the key is
  // missing, which would let a lower layer turn the indicator back on.
  it("sets enabled to false rather than deleting the key", () => {
    const dir = tmp();
    const path = join(dir, "settings.local.json");
    writeVoiceState(path, { enabled: true, mode: "toggle" });
    clearVoiceState(path);
    expect(JSON.parse(readFileSync(path, "utf8")).voice).toEqual({ enabled: false });
  });

  it("does nothing when the file does not exist", () => {
    const dir = tmp();
    const path = join(dir, "settings.local.json");
    clearVoiceState(path);
    expect(existsSync(path)).toBe(false);
  });
});

describe("reconcileStaleState", () => {
  // A crashed pi leaves enabled:true behind and the mic glyph stays lit
  // forever. On startup, a recorded pid that is gone means the state is stale.
  it("clears state left by a process that is gone", () => {
    const dir = tmp();
    const path = join(dir, "settings.local.json");
    writeVoiceState(path, { enabled: true, mode: "toggle", pid: 999999 });
    reconcileStaleState(path, () => false);
    expect(JSON.parse(readFileSync(path, "utf8")).voice.enabled).toBe(false);
  });

  it("leaves state belonging to a live process alone", () => {
    const dir = tmp();
    const path = join(dir, "settings.local.json");
    writeVoiceState(path, { enabled: true, mode: "toggle", pid: 4242 });
    reconcileStaleState(path, () => true);
    expect(JSON.parse(readFileSync(path, "utf8")).voice.enabled).toBe(true);
  });

  it("leaves a disabled state alone", () => {
    const dir = tmp();
    const path = join(dir, "settings.local.json");
    writeVoiceState(path, { enabled: false });
    reconcileStaleState(path, () => false);
    expect(JSON.parse(readFileSync(path, "utf8")).voice).toEqual({ enabled: false });
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
cd /home/joe/Development/pi-nix/packages/first-party/pi-voice && bun test 2>&1 | tail -5
```

Expected: `SyntaxError: Export named 'voiceStatePath' not found in module`.

- [ ] **Step 3: Implement in `voice.ts`**

```typescript
import { existsSync, mkdirSync, readFileSync, renameSync, unlinkSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";

// ── The voice state file ──────────────────────────────────────────────────
//
// agent-statusline's `voice` widget reads Claude Code's settings layers and
// looks for a `voice` object (internal/voice/voice.go). The producer is
// whoever owns the mic, which makes this contract harness-independent: pi-voice
// writes it under pi, and anything driving Claude Code's dictation writes the
// same shape to the same place.
//
// settings.local.json rather than settings.json: claude-nix places the latter
// and deep-merges it on every activation, so a producer writing there would be
// fighting the rebuild.

export interface VoiceState {
  enabled: boolean;
  mode?: string;
  pid?: number;
  since?: number;
}

/** Resolve the state file, mirroring internal/voice.NewReader: the
 *  CLAUDE_CONFIG_DIR override when non-empty, otherwise $HOME/.claude. */
export function voiceStatePath(env: Record<string, string | undefined>, homeDir: string): string {
  const dir = env.CLAUDE_CONFIG_DIR ? env.CLAUDE_CONFIG_DIR : join(homeDir, ".claude");
  return join(dir, "settings.local.json");
}

function readSettings(path: string): Record<string, unknown> | undefined {
  if (!existsSync(path)) return {};
  try {
    const parsed = JSON.parse(readFileSync(path, "utf8"));
    if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) return undefined;
    return parsed as Record<string, unknown>;
  } catch {
    // Someone else's file that we cannot parse. Refuse rather than clobber.
    return undefined;
  }
}

/** Set the voice block, preserving every other key. The write goes through a
 *  temp file and a rename, because the reader can run at any moment and a torn
 *  read makes the widget fall through to a lower settings layer. */
export function writeVoiceState(path: string, state: VoiceState): void {
  const settings = readSettings(path);
  if (settings === undefined) return;

  const voice: Record<string, unknown> = { enabled: state.enabled };
  if (state.mode !== undefined) voice.mode = state.mode;
  if (state.pid !== undefined) voice.pid = state.pid;
  if (state.since !== undefined) voice.since = state.since;
  settings.voice = voice;

  mkdirSync(dirname(path), { recursive: true });
  const tmpPath = `${path}.pi-voice.tmp`;
  try {
    writeFileSync(tmpPath, `${JSON.stringify(settings, null, 2)}\n`, { mode: 0o600 });
    renameSync(tmpPath, path);
  } catch {
    try {
      unlinkSync(tmpPath);
    } catch {
      /* the temp file was never created */
    }
  }
}

/** Turn the indicator off. enabled:false rather than a deleted key: the reader
 *  falls through when the key is absent, which would let a project-level
 *  settings file switch the indicator back on. */
export function clearVoiceState(path: string): void {
  if (!existsSync(path)) return;
  writeVoiceState(path, { enabled: false });
}

/** Clear state left behind by a pi that died mid-recording. Without this the
 *  mic glyph stays lit until the next successful stop. */
export function reconcileStaleState(path: string, isAlive: (pid: number) => boolean): void {
  const settings = readSettings(path);
  if (!settings) return;
  const voice = settings.voice as VoiceState | undefined;
  if (!voice?.enabled) return;
  if (typeof voice.pid === "number" && isAlive(voice.pid)) return;
  writeVoiceState(path, { enabled: false });
}

/** Default liveness probe. signal 0 checks for the process without touching
 *  it; EPERM means it exists and belongs to someone else. */
export function pidIsAlive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch (err) {
    return (err as NodeJS.ErrnoException)?.code === "EPERM";
  }
}
```

- [ ] **Step 4: Run the tests**

Run:
```bash
cd /home/joe/Development/pi-nix/packages/first-party/pi-voice && bun test 2>&1 | tail -5
```

Expected: every test passes.

- [ ] **Step 5: Prove the Go reader accepts what the writer produces**

This is the seam, so check it against the real reader rather than against the plan's description of it:

```bash
cd /home/joe/Development/pi-nix/packages/first-party/pi-voice
TMPDIR_T=$(mktemp -d)
bun -e "
import { writeVoiceState, voiceStatePath } from './voice.ts';
const p = voiceStatePath({ CLAUDE_CONFIG_DIR: '$TMPDIR_T' }, '/nonexistent');
writeVoiceState(p, { enabled: true, mode: 'toggle', pid: 4242 });
console.log(p);
"
cat "$TMPDIR_T/settings.local.json"
cd /home/joe/Development/agent-statusline
cat > /tmp/voiceprobe_test.go <<'EOF'
package voice

import (
	"os"
	"testing"
)

func TestProbeWrittenState(t *testing.T) {
	r := &Reader{UserDir: os.Getenv("PROBE_DIR")}
	cfg := r.Read(t.TempDir())
	if cfg == nil || !cfg.Enabled || cfg.Mode != "toggle" {
		t.Fatalf("reader saw %+v", cfg)
	}
}
EOF
cp /tmp/voiceprobe_test.go internal/voice/voiceprobe_test.go
PROBE_DIR="$TMPDIR_T" go test ./internal/voice/ -run TestProbeWrittenState -v 2>&1 | tail -4
rm internal/voice/voiceprobe_test.go
```

Expected: `--- PASS: TestProbeWrittenState`. The written file must contain `"voice": {"enabled": true, "mode": "toggle", "pid": 4242}` and the reader must return `Enabled=true, Mode=toggle`, ignoring `pid`. Delete the probe file afterwards; it is a one-off check, not a test to commit.

- [ ] **Step 6: Commit**

```bash
cd /home/joe/Development/pi-nix
git add packages/first-party/pi-voice
git commit -m "feat(pi-voice): write the voice state agent-statusline reads

The widget has never fired because nothing wrote the file. The contract
is harness-independent: any producer that owns the mic writes
{voice:{enabled,mode}} into settings.local.json, and the statusline picks
it up under pi and under Claude Code alike. Writes merge and go through a
rename, because the file belongs to Claude Code and the reader can run
mid-write. Stop writes enabled:false rather than deleting the key, since
an absent key lets a lower settings layer answer instead."
```

---

### Task 9: The TUI widget

Two rows below the editor: a meter row and a transcript row. Rendering is pure, so it is tested against a fake theme.

**Files:** (all in `/home/joe/Development/pi-nix`)
- Modify: `packages/first-party/pi-voice/voice.ts`
- Modify: `packages/first-party/pi-voice/voice.test.ts`

**Interfaces:**
- Consumes: `Meter`, `visibleWidth`, `truncateToWidth` from Task 7
- Produces:
  - `interface VoiceUiState { recording, elapsedMs, level, db, committed, partial, note }`
  - `function renderMeterRow(state, cfg, width, theme): string`
  - `function renderTranscriptRow(state, width, theme): string`
  - `function renderVoiceRows(state, cfg, width, theme): string[]`
  - `function formatElapsed(ms: number): string`

- [ ] **Step 1: Write the failing test**

Append to `voice.test.ts`:

```typescript
import { formatElapsed, renderMeterRow, renderTranscriptRow, renderVoiceRows } from "./voice";

// A stand-in for pi's live theme proxy. Colours are recorded as
// <slot>{...}</slot> so tests assert on which semantic slot was chosen rather
// than on ANSI bytes, which is the whole point of using the theme.
const theme = {
  fg: (slot: string, text: string) => `<${slot}>${text}</${slot}>`,
  bold: (text: string) => `<b>${text}</b>`,
};

const cfg = readVoiceConfig({});

function bare(s: string): string {
  return s.replace(/<\/?[a-zA-Z]+>/g, "");
}

describe("formatElapsed", () => {
  it("counts in minutes and seconds", () => {
    expect(formatElapsed(0)).toBe("0:00");
    expect(formatElapsed(9_000)).toBe("0:09");
    expect(formatElapsed(72_000)).toBe("1:12");
    expect(formatElapsed(3_601_000)).toBe("60:01");
  });
});

describe("renderMeterRow", () => {
  const base = { recording: true, elapsedMs: 12_000, level: 0.5, db: -30, committed: "", partial: "", note: "" };

  it("shows a record dot, the clock, a bar, and a dB readout", () => {
    const row = bare(renderMeterRow(base, cfg, 60, theme));
    expect(row).toContain("0:12");
    expect(row).toContain("-30.0 dB");
    expect(row).toContain("█");
  });

  it("fills the bar in proportion to the level", () => {
    const quiet = bare(renderMeterRow({ ...base, level: 0 }, cfg, 60, theme));
    const loud = bare(renderMeterRow({ ...base, level: 1 }, cfg, 60, theme));
    expect((quiet.match(/█/g) ?? []).length).toBe(0);
    expect((loud.match(/█/g) ?? []).length).toBe(cfg.barWidth);
  });

  // The same thresholds audiomemo's TUI uses, expressed as pi's semantic
  // colour slots rather than as hardcoded RGB.
  it("colours the bar by level using theme slots", () => {
    expect(renderMeterRow({ ...base, level: 0.3 }, cfg, 60, theme)).toContain("<success>");
    expect(renderMeterRow({ ...base, level: 0.7 }, cfg, 60, theme)).toContain("<warning>");
    expect(renderMeterRow({ ...base, level: 0.9 }, cfg, 60, theme)).toContain("<error>");
  });

  it("shows silence as -inf rather than a wrong number", () => {
    expect(bare(renderMeterRow({ ...base, level: 0, db: -60 }, cfg, 60, theme))).toContain("-inf dB");
  });

  it("never exceeds the width it was given", () => {
    for (const w of [8, 20, 40, 120]) {
      expect(visibleWidth(renderMeterRow(base, cfg, w, theme))).toBeLessThanOrEqual(w);
    }
  });

  it("reports the note instead of a meter when not recording", () => {
    const row = bare(renderMeterRow({ ...base, recording: false, note: "transcribing…" }, cfg, 60, theme));
    expect(row).toContain("transcribing…");
    expect(row).not.toContain("█");
  });
});

describe("renderTranscriptRow", () => {
  const base = { recording: true, elapsedMs: 0, level: 0, db: -60, committed: "", partial: "", note: "" };

  it("puts committed text and the current partial on one line", () => {
    const row = renderTranscriptRow({ ...base, committed: "So the thing is,", partial: "we shipped" }, 80, theme);
    expect(bare(row)).toBe("So the thing is, we shipped");
  });

  // Committed text is settled, the partial is still moving; the theme's dim
  // slot is what tells them apart, exactly as audiomemo's TUI does.
  it("dims the partial and leaves committed text in the normal slot", () => {
    const row = renderTranscriptRow({ ...base, committed: "So the", partial: "thing" }, 80, theme);
    expect(row).toContain("<text>So the</text>");
    expect(row).toContain("<dim>thing</dim>");
  });

  // The transcript grows without bound; the row shows the end of it because
  // that is where the user is speaking.
  it("keeps the tail when the text is longer than the row", () => {
    const long = "word ".repeat(60).trim();
    const row = bare(renderTranscriptRow({ ...base, committed: long }, 20, theme));
    expect(visibleWidth(row)).toBeLessThanOrEqual(20);
    expect(row.endsWith("word")).toBe(true);
  });

  it("shows a placeholder before any text has arrived", () => {
    expect(bare(renderTranscriptRow(base, 40, theme))).toContain("listening");
  });

  it("never exceeds the width it was given", () => {
    const st = { ...base, committed: "日本語のテスト".repeat(10) };
    for (const w of [6, 15, 31, 80]) {
      expect(visibleWidth(renderTranscriptRow(st, w, theme))).toBeLessThanOrEqual(w);
    }
  });
});

describe("renderVoiceRows", () => {
  it("returns nothing at all when idle", () => {
    const idle = { recording: false, elapsedMs: 0, level: 0, db: -60, committed: "", partial: "", note: "" };
    expect(renderVoiceRows(idle, cfg, 80, theme)).toEqual([]);
  });

  it("returns exactly two rows while recording", () => {
    const st = { recording: true, elapsedMs: 1000, level: 0.4, db: -36, committed: "hi", partial: "", note: "" };
    expect(renderVoiceRows(st, cfg, 80, theme)).toHaveLength(2);
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
cd /home/joe/Development/pi-nix/packages/first-party/pi-voice && bun test 2>&1 | tail -5
```

Expected: `Export named 'renderMeterRow' not found in module`.

- [ ] **Step 3: Implement the renderers in `voice.ts`**

```typescript
// ── Rendering ─────────────────────────────────────────────────────────────
//
// pi hands the component a live theme proxy and pushes the render width on
// every frame (interactive-mode.ts:2134-2174), so colour and layout are
// decided here rather than upstream in Go. Colours come from the theme's
// semantic slots, which follow the user's /theme choice; pi's own footer uses
// the same success/warning/error progression for its context meter.

/** The subset of pi's Theme this extension uses. Declared structurally so the
 *  tests can pass a recorder in place of the real proxy. */
export interface VoiceTheme {
  fg(slot: string, text: string): string;
  bold?(text: string): string;
}

export interface VoiceUiState {
  recording: boolean;
  elapsedMs: number;
  level: number;
  db: number;
  committed: string;
  partial: string;
  note: string;
}

const FLOOR_DB = -60;

export function formatElapsed(ms: number): string {
  const total = Math.max(0, Math.floor(ms / 1000));
  return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, "0")}`;
}

function levelSlot(level: number): string {
  if (level >= 0.85) return "error";
  if (level >= 0.6) return "warning";
  return "success";
}

/** Row one: a record dot, the elapsed clock, the meter, and the dB readout. */
export function renderMeterRow(state: VoiceUiState, cfg: VoiceConfig, width: number, theme: VoiceTheme): string {
  if (!state.recording) {
    return truncateToWidth(theme.fg("dim", state.note || "voice idle"), width);
  }

  const filled = Math.round(Math.max(0, Math.min(1, state.level)) * cfg.barWidth);
  const bar = theme.fg(levelSlot(state.level), "█".repeat(filled)) + theme.fg("dim", "░".repeat(cfg.barWidth - filled));
  const db = state.db <= FLOOR_DB ? "-inf dB" : `${state.db.toFixed(1)} dB`;

  const parts = [
    theme.fg("error", "●"),
    theme.fg("dim", formatElapsed(state.elapsedMs)),
    bar,
    theme.fg("dim", db),
  ];
  return truncateToWidth(parts.join(" "), width);
}

/** Row two: committed text in the normal slot, the moving partial dimmed
 *  after it. The tail is what matters, because that is where the speaker is. */
export function renderTranscriptRow(state: VoiceUiState, width: number, theme: VoiceTheme): string {
  const committed = state.committed.trim();
  const partial = state.partial.trim();
  if (committed === "" && partial === "") {
    return truncateToWidth(theme.fg("dim", "listening…"), width);
  }

  // Trim from the left first, on plain text, so truncateToWidth never has to
  // cut a coloured run in the middle.
  const partialWidth = partial === "" ? 0 : visibleWidth(partial) + 1;
  let head = committed;
  while (head !== "" && visibleWidth(head) + partialWidth > width) {
    head = head.slice(1);
  }

  const pieces: string[] = [];
  if (head !== "") pieces.push(theme.fg("text", head));
  if (partial !== "") pieces.push(theme.fg("dim", partial));
  return truncateToWidth(pieces.join(" "), width);
}

/** The widget's whole output. An idle widget renders zero rows, which removes
 *  it from the dock entirely rather than leaving a blank line behind. */
export function renderVoiceRows(
  state: VoiceUiState,
  cfg: VoiceConfig,
  width: number,
  theme: VoiceTheme,
): string[] {
  if (!state.recording && state.note === "") return [];
  return [renderMeterRow(state, cfg, width, theme), renderTranscriptRow(state, width, theme)];
}
```

- [ ] **Step 4: Run the tests**

Run:
```bash
cd /home/joe/Development/pi-nix/packages/first-party/pi-voice && bun test 2>&1 | tail -5
```

Expected: every test passes. If the width assertions fail at small widths, `truncateToWidth` is being applied before the join rather than after.

- [ ] **Step 5: Commit**

```bash
cd /home/joe/Development/pi-nix
git add packages/first-party/pi-voice
git commit -m "feat(pi-voice): meter and transcript rows

Rendering is a pure function of state, width, and theme, so it is tested
against a recording theme that names the slot it was asked for. Colours
are semantic slots rather than ANSI, so /theme changes follow. The
transcript row keeps its tail because that is where the speaker is, and
the partial is dimmed because it is still moving."
```

---

### Task 10: The controller and the `/voice` command

Spawning, event wiring, the paste, and cleanup. Tested against a fake `record --stream` written into a temp directory, so it exercises the real spawn and the real SIGINT path without a microphone.

**Files:** (all in `/home/joe/Development/pi-nix`)
- Modify: `packages/first-party/pi-voice/voice.ts`
- Modify: `packages/first-party/pi-voice/voice.test.ts`

**Interfaces:**
- Consumes: everything from Tasks 7-9; `ctx.ui.setWidget`, `ctx.ui.setStatus`, `ctx.ui.pasteToEditor`, `ctx.ui.notify`, `pi.registerCommand`, `pi.on("session_shutdown")`
- Produces:
  - `class VoiceSession` with `start()`, `stop()`, `readonly recording`
  - `export default function register(pi: ExtensionAPI): void`

- [ ] **Step 1: Confirm the pi API surface before writing against it**

Run:
```bash
P=/home/joe/Development/pi-nix/result/lib/node_modules/@earendil-works/pi-coding-agent
grep -n 'pasteToEditor\|setEditorText\|notify(\|setWidget(\|registerCommand(' $P/src/core/extensions/types.ts
```

Expected, and verified on 2026-08-18: `pasteToEditor(text: string): void` at `:213`, `setEditorText` at `:216`, `notify(message, type?)` at `:135`, both `setWidget` overloads at `:170-176`, and `registerCommand(name, options)` at `:1260` with `handler: (args: string, ctx: ExtensionCommandContext) => Promise<void>`.

`pasteToEditor` is the right call rather than `setEditorText`: its doc comment says it triggers paste handling and collapses large content, and unlike `setEditorText` it does not discard what the user already typed.

- [ ] **Step 2: Write the failing test**

Append to `voice.test.ts`:

```typescript
import { chmodSync } from "node:fs";
import { setDefaultTimeout } from "bun:test";

// bun's per-test timeout is 5s, below the waitFor deadline below. A cold run
// (bun's first transpile plus the first subprocess spawn) overshoots it and
// fails a test that is not slow. agent-statusline's suite hit this first.
setDefaultTimeout(30_000);

// bun:test has no vi.waitFor. Polls an assertion until it stops throwing.
// Same helper as agent-statusline/extension/statusline.test.ts.
async function waitFor(fn: () => unknown, timeoutMs = 10_000, stepMs = 10) {
	const deadline = Date.now() + timeoutMs;
	let lastErr: unknown;
	for (;;) {
		try {
			return await fn();
		} catch (err) {
			lastErr = err;
			if (Date.now() > deadline) throw lastErr;
			await new Promise((r) => setTimeout(r, stepMs));
		}
	}
}

/** A stand-in for `record --stream`: prints canned NDJSON, then waits for
 *  SIGINT and closes the stream the way audiomemo does. This is what makes
 *  the controller testable without a microphone. */
function fakeRecordBin(): string {
  const dir = mkdtempSync(join(tmpdir(), "pi-voice-bin-"));
  const path = join(dir, "record");
  writeFileSync(
    path,
    [
      "#!/bin/sh",
      `printf '%s\\n' '{"type":"start","t":0,"device":"mic","device_label":"mic","devices":["mic"],"path":"/tmp/x.ogg","format":"ogg","sample_rate":48000,"channels":1,"mode":"live","backend":"elevenlabs"}'`,
      `printf '%s\\n' '{"type":"level","t":50,"rms":0.8,"db":-12}'`,
      `printf '%s\\n' '{"type":"partial","t":900,"text":"so the thing is"}'`,
      `printf '%s\\n' '{"type":"commit","t":1400,"text":"So the thing is,"}'`,
      `trap 'printf "%s\\n" "{\\"type\\":\\"final\\",\\"t\\":9000,\\"text\\":\\"So the thing is, we shipped it.\\",\\"path\\":\\"/tmp/x.ogg\\",\\"backend\\":\\"elevenlabs\\",\\"source\\":\\"batch\\"}"; printf "%s\\n" "{\\"type\\":\\"end\\",\\"t\\":9010,\\"reason\\":\\"signal\\",\\"path\\":\\"/tmp/x.ogg\\",\\"exit_code\\":0}"; exit 0' INT`,
      "while true; do sleep 0.05; done",
    ].join("\n"),
  );
  chmodSync(path, 0o755);
  return path;
}

function fakePi() {
  const handlers = new Map<string, Function>();
  const commands = new Map<string, { description?: string; handler: Function }>();
  return {
    handlers,
    commands,
    on(event: string, handler: Function) {
      handlers.set(event, handler);
    },
    registerCommand(name: string, options: { description?: string; handler: Function }) {
      commands.set(name, options);
    },
    emit(event: string, payload: unknown, ctx: unknown) {
      return handlers.get(event)?.(payload, ctx);
    },
  };
}

function fakeCtx(stateDir: string) {
  const widgets: Array<[string, unknown, unknown]> = [];
  const statuses: Array<[string, string | undefined]> = [];
  const pastes: string[] = [];
  const notices: Array<[string, string | undefined]> = [];
  const renders: number[] = [];
  const tui = { requestRender: () => renders.push(Date.now()) };
  const theme = { fg: (slot: string, text: string) => `<${slot}>${text}</${slot}>` };
  return {
    widgets,
    statuses,
    pastes,
    notices,
    renders,
    tui,
    theme,
    ctx: {
      cwd: stateDir,
      mode: "tui",
      hasUI: true,
      ui: {
        setWidget: (key: string, content: unknown, opts: unknown) => widgets.push([key, content, opts]),
        setStatus: (key: string, text: string | undefined) => statuses.push([key, text]),
        pasteToEditor: (text: string) => pastes.push(text),
        notify: (message: string, type?: string) => notices.push([message, type]),
        theme,
      },
    },
  };
}

describe("VoiceSession", () => {
  it("streams events into UI state and pastes the final text", async () => {
    const stateDir = tmp();
    process.env.PI_VOICE_RECORD_BIN = fakeRecordBin();
    process.env.CLAUDE_CONFIG_DIR = stateDir;
    try {
      const { VoiceSession } = await import("./voice");
      const { ctx, pastes } = fakeCtx(stateDir);
      const session = new VoiceSession(ctx as never);

      session.start();
      await waitFor(() => expect(session.state.committed).toBe("So the thing is,"));
      expect(session.state.recording).toBe(true);
      expect(session.state.partial).toBe("so the thing is");
      // rms 0.8 with fast attack lands at 0.4 after one sample.
      expect(session.state.level).toBeCloseTo(0.4, 6);
      expect(session.state.db).toBe(-12);

      // The state file must be lit while the mic is live.
      expect(JSON.parse(readFileSync(join(stateDir, "settings.local.json"), "utf8")).voice).toMatchObject({
        enabled: true,
        mode: "toggle",
      });

      await session.stop();
      await waitFor(() => expect(pastes).toEqual(["So the thing is, we shipped it."]));
      expect(session.state.recording).toBe(false);
      expect(JSON.parse(readFileSync(join(stateDir, "settings.local.json"), "utf8")).voice.enabled).toBe(false);
    } finally {
      delete process.env.PI_VOICE_RECORD_BIN;
      delete process.env.CLAUDE_CONFIG_DIR;
    }
  });

  it("mounts a belowEditor widget and a sanitize-safe status token", async () => {
    const stateDir = tmp();
    process.env.PI_VOICE_RECORD_BIN = fakeRecordBin();
    process.env.CLAUDE_CONFIG_DIR = stateDir;
    try {
      const { VoiceSession } = await import("./voice");
      const { ctx, widgets, statuses } = fakeCtx(stateDir);
      const session = new VoiceSession(ctx as never);
      session.start();
      await waitFor(() => expect(widgets.length).toBeGreaterThan(0));

      const [key, content, opts] = widgets[0];
      expect(key).toBe("pi-voice");
      // A component factory, not a string[]: the string[] form is wrapped in
      // Text with paddingX and capped at 10 lines, and we own our own width.
      expect(typeof content).toBe("function");
      expect(opts).toEqual({ placement: "belowEditor" });

      // setStatus runs text through sanitizeStatusText, which collapses runs
      // of spaces and newlines. The meter is space-padded, so only a short
      // token goes through it.
      const [, text] = statuses.at(-1) ?? [];
      expect(String(text)).not.toMatch(/ {2}/);
      expect(String(text)).not.toContain("\n");

      await session.stop();
    } finally {
      delete process.env.PI_VOICE_RECORD_BIN;
      delete process.env.CLAUDE_CONFIG_DIR;
    }
  });

  it("surfaces a missing binary as a notice rather than an exception", async () => {
    const stateDir = tmp();
    process.env.PI_VOICE_RECORD_BIN = "/nonexistent/record";
    process.env.CLAUDE_CONFIG_DIR = stateDir;
    try {
      const { VoiceSession } = await import("./voice");
      const { ctx, notices } = fakeCtx(stateDir);
      const session = new VoiceSession(ctx as never);
      session.start();
      await waitFor(() => expect(notices.length).toBe(1));
      expect(notices[0][1]).toBe("error");
      expect(session.state.recording).toBe(false);
      // A failed start must not leave the mic indicator lit.
      const p = join(stateDir, "settings.local.json");
      if (existsSync(p)) {
        expect(JSON.parse(readFileSync(p, "utf8")).voice.enabled).toBe(false);
      }
    } finally {
      delete process.env.PI_VOICE_RECORD_BIN;
      delete process.env.CLAUDE_CONFIG_DIR;
    }
  });

  it("reports error events without stopping the recording", async () => {
    const { VoiceSession } = await import("./voice");
    const { ctx, notices } = fakeCtx(tmp());
    const session = new VoiceSession(ctx as never);
    session.handleEvent({
      type: "error",
      t: 1,
      scope: "stream",
      fatal: false,
      message: "elevenlabs error (rate_limited)",
    });
    expect(notices[0][1]).toBe("warning");
    expect(session.state.note).toContain("rate_limited");
  });

  it("says so when no transcription backend is available", async () => {
    const { VoiceSession } = await import("./voice");
    const { ctx } = fakeCtx(tmp());
    const session = new VoiceSession(ctx as never);
    session.handleEvent({ type: "start", t: 0, mode: "none", path: "/tmp/x.ogg" });
    expect(session.state.note).toContain("no transcription backend");
  });

  it("tells the user a batch run produces no partials", async () => {
    const { VoiceSession } = await import("./voice");
    const { ctx } = fakeCtx(tmp());
    const session = new VoiceSession(ctx as never);
    session.handleEvent({ type: "start", t: 0, mode: "batch", path: "/tmp/x.ogg" });
    expect(session.state.note).toContain("after recording");
  });

  it("does not paste an empty final", async () => {
    const { VoiceSession } = await import("./voice");
    const { ctx, pastes } = fakeCtx(tmp());
    const session = new VoiceSession(ctx as never);
    session.handleEvent({ type: "final", t: 1, text: "   ", source: "live" });
    expect(pastes).toEqual([]);
  });
});

describe("extension entrypoint", () => {
  it("registers /voice and the lifecycle hooks pi publishes", async () => {
    const { default: register } = await import("./voice");
    const pi = fakePi();
    register(pi as never);
    expect(pi.commands.has("voice")).toBe(true);
    expect(pi.commands.get("voice")?.description).toBeTruthy();
    for (const event of ["session_start", "session_shutdown"]) {
      expect(pi.handlers.has(event), event).toBe(true);
    }
  });

  it("toggles: the first /voice starts, the second stops", async () => {
    const stateDir = tmp();
    process.env.PI_VOICE_RECORD_BIN = fakeRecordBin();
    process.env.CLAUDE_CONFIG_DIR = stateDir;
    try {
      const { default: register } = await import("./voice");
      const pi = fakePi();
      register(pi as never);
      const { ctx, pastes } = fakeCtx(stateDir);

      await pi.commands.get("voice")?.handler("", ctx.ctx);
      await waitFor(() =>
        expect(JSON.parse(readFileSync(join(stateDir, "settings.local.json"), "utf8")).voice.enabled).toBe(true),
      );

      await pi.commands.get("voice")?.handler("", ctx.ctx);
      await waitFor(() => expect(pastes.length).toBe(1));
    } finally {
      delete process.env.PI_VOICE_RECORD_BIN;
      delete process.env.CLAUDE_CONFIG_DIR;
    }
  });

  it("clears the mic indicator on shutdown", async () => {
    const stateDir = tmp();
    process.env.PI_VOICE_RECORD_BIN = fakeRecordBin();
    process.env.CLAUDE_CONFIG_DIR = stateDir;
    try {
      const { default: register } = await import("./voice");
      const pi = fakePi();
      register(pi as never);
      const { ctx } = fakeCtx(stateDir);
      await pi.commands.get("voice")?.handler("", ctx.ctx);
      await waitFor(() =>
        expect(JSON.parse(readFileSync(join(stateDir, "settings.local.json"), "utf8")).voice.enabled).toBe(true),
      );

      await pi.emit("session_shutdown", { type: "session_shutdown" }, ctx.ctx);
      await waitFor(() =>
        expect(JSON.parse(readFileSync(join(stateDir, "settings.local.json"), "utf8")).voice.enabled).toBe(false),
      );
    } finally {
      delete process.env.PI_VOICE_RECORD_BIN;
      delete process.env.CLAUDE_CONFIG_DIR;
    }
  });

  it("clears state left behind by a crashed session on startup", async () => {
    const stateDir = tmp();
    process.env.CLAUDE_CONFIG_DIR = stateDir;
    try {
      writeVoiceState(join(stateDir, "settings.local.json"), { enabled: true, mode: "toggle", pid: 999999 });
      const { default: register } = await import("./voice");
      const pi = fakePi();
      register(pi as never);
      const { ctx } = fakeCtx(stateDir);
      await pi.emit("session_start", { type: "session_start", reason: "startup" }, ctx.ctx);
      expect(JSON.parse(readFileSync(join(stateDir, "settings.local.json"), "utf8")).voice.enabled).toBe(false);
    } finally {
      delete process.env.CLAUDE_CONFIG_DIR;
    }
  });
});
```

- [ ] **Step 3: Run the test to verify it fails**

Run:
```bash
cd /home/joe/Development/pi-nix/packages/first-party/pi-voice && bun test 2>&1 | tail -5
```

Expected: `Export named 'VoiceSession' not found in module`.

- [ ] **Step 4: Implement the controller in `voice.ts`**

```typescript
import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { homedir } from "node:os";

// ── The controller ────────────────────────────────────────────────────────
//
// node's child_process rather than pi.exec: ExecOptions is { signal, timeout,
// cwd } and exec resolves once with the whole stdout, so it cannot deliver
// partials as they arrive.

/** The slice of pi's ExtensionContext this extension touches. */
export interface VoiceContext {
  cwd: string;
  mode?: string;
  hasUI?: boolean;
  ui: {
    setWidget(key: string, content: unknown, options?: { placement?: string }): void;
    setStatus(key: string, text: string | undefined): void;
    pasteToEditor(text: string): void;
    notify(message: string, type?: "info" | "warning" | "error"): void;
    readonly theme?: VoiceTheme;
  };
}

const WIDGET_KEY = "pi-voice";
const STATUS_KEY = "pi-voice";

function emptyState(): VoiceUiState {
  return { recording: false, elapsedMs: 0, level: 0, db: FLOOR_DB, committed: "", partial: "", note: "" };
}

export class VoiceSession {
  readonly state: VoiceUiState = emptyState();

  private readonly cfg: VoiceConfig;
  private readonly statePath: string;
  private child: ChildProcessWithoutNullStreams | undefined;
  private meter = new Meter();
  private startedAt = 0;
  private tui: { requestRender(): void } | undefined;
  private clock: ReturnType<typeof setInterval> | undefined;
  private ended: (() => void) | undefined;

  constructor(private readonly ctx: VoiceContext) {
    this.cfg = readVoiceConfig(process.env as Record<string, string | undefined>);
    this.statePath = voiceStatePath(process.env as Record<string, string | undefined>, homedir());
  }

  get recording(): boolean {
    return this.state.recording;
  }

  start(): void {
    if (this.child) return;

    this.meter = new Meter();
    Object.assign(this.state, emptyState(), { recording: true });
    this.startedAt = Date.now();

    let child: ChildProcessWithoutNullStreams;
    try {
      child = spawn(this.cfg.recordBin, this.cfg.recordArgs, { stdio: ["ignore", "pipe", "pipe"] });
    } catch (err) {
      this.fail(err);
      return;
    }
    this.child = child;

    child.on("error", (err) => this.fail(err));

    const feed = createLineSplitter((line) => {
      const event = parseEvent(line);
      if (event) this.handleEvent(event);
    });
    child.stdout.setEncoding("utf8");
    child.stdout.on("data", (chunk: string) => feed(chunk));

    // audiomemo's own warnings arrive as error events; fd 2 carries ffmpeg's
    // and whisper's diagnostics, which are not ours to reformat or to show.
    child.stderr.resume();

    child.on("close", () => {
      this.child = undefined;
      this.state.recording = false;
      this.stopClock();
      clearVoiceState(this.statePath);
      this.paint();
      this.ended?.();
      this.ended = undefined;
    });

    writeVoiceState(this.statePath, {
      enabled: true,
      mode: this.cfg.mode,
      pid: process.pid,
      since: this.startedAt,
    });
    this.mountWidget();
    this.startClock();
    this.paint();
  }

  /** Stop and resolve once the child has closed, so the caller knows the
   *  final event has been handled and the paste has happened. */
  stop(): Promise<void> {
    const child = this.child;
    if (!child) return Promise.resolve();
    return new Promise<void>((resolve) => {
      this.ended = resolve;
      // SIGINT, not SIGKILL: audiomemo's --stream handler stops ffmpeg the
      // graceful way, runs the batch pass, and emits final and end.
      child.kill("SIGINT");
    });
  }

  handleEvent(event: VoiceEvent): void {
    switch (event.type) {
      case "start":
        this.state.note =
          event.mode === "none"
            ? "no transcription backend configured; audio is still being recorded"
            : event.mode === "batch"
              ? "transcribing after recording; no live text"
              : "";
        break;
      case "level":
        this.meter.push(event.rms);
        this.state.level = this.meter.level;
        this.state.db = event.db;
        break;
      case "partial":
        this.state.partial = event.text;
        break;
      case "commit":
        this.state.committed = this.state.committed === "" ? event.text : `${this.state.committed} ${event.text}`;
        this.state.partial = "";
        break;
      case "final": {
        const text = event.text.trim();
        if (text !== "") this.ctx.ui.pasteToEditor(text);
        break;
      }
      case "error":
        this.state.note = event.message;
        this.ctx.ui.notify(`voice: ${event.message}`, event.fatal ? "error" : "warning");
        break;
      case "end":
        this.state.recording = false;
        break;
    }
    this.paint();
  }

  private fail(err: unknown): void {
    this.child = undefined;
    this.state.recording = false;
    this.stopClock();
    clearVoiceState(this.statePath);
    this.ctx.ui.notify(`voice: could not start ${this.cfg.recordBin}: ${String(err)}`, "error");
    this.paint();
    this.ended?.();
    this.ended = undefined;
  }

  private mountWidget(): void {
    // setWidget and setFooter are no-ops outside TUI mode; guard so a print or
    // rpc run does not carry dead state.
    if (this.ctx.mode !== "tui") return;
    this.ctx.ui.setWidget(
      WIDGET_KEY,
      (tui: { requestRender(): void }, theme: VoiceTheme) => {
        this.tui = tui;
        return {
          invalidate: () => {},
          dispose: () => {
            this.tui = undefined;
          },
          render: (width: number) => renderVoiceRows(this.state, this.cfg, width, theme),
        };
      },
      { placement: this.cfg.placement },
    );
  }

  private startClock(): void {
    this.stopClock();
    // The elapsed clock has to advance without an inbound event. requestRender
    // coalesces at 16 ms, so 1 Hz is free.
    this.clock = setInterval(() => {
      this.state.elapsedMs = Date.now() - this.startedAt;
      this.tui?.requestRender();
    }, 1000);
  }

  private stopClock(): void {
    if (this.clock) clearInterval(this.clock);
    this.clock = undefined;
  }

  private paint(): void {
    // setStatus runs through sanitizeStatusText, which collapses runs of
    // spaces and newlines. The meter row is space-padded and the transcript
    // may contain runs of spaces, so only this one short token goes through
    // it; the real UI is the widget.
    const theme = this.ctx.ui.theme;
    if (this.state.recording) {
      this.ctx.ui.setStatus(STATUS_KEY, theme ? theme.fg("error", "● rec") : "● rec");
    } else {
      this.ctx.ui.setStatus(STATUS_KEY, undefined);
      if (this.ctx.mode === "tui") this.ctx.ui.setWidget(WIDGET_KEY, undefined);
    }
    this.tui?.requestRender();
  }
}

export default function register(pi: {
  on(event: string, handler: (payload: unknown, ctx: VoiceContext) => unknown): void;
  registerCommand(
    name: string,
    options: { description?: string; handler: (args: string, ctx: VoiceContext) => Promise<void> },
  ): void;
}): void {
  let session: VoiceSession | undefined;

  pi.on("session_start", (_payload, ctx) => {
    // A pi that died mid-recording leaves enabled:true behind and the mic
    // glyph stays lit. Clear it if the process that wrote it is gone.
    reconcileStaleState(voiceStatePath(process.env as Record<string, string | undefined>, homedir()), pidIsAlive);
    session ??= new VoiceSession(ctx);
  });

  pi.on("session_shutdown", async () => {
    await session?.stop();
    clearVoiceState(voiceStatePath(process.env as Record<string, string | undefined>, homedir()));
  });

  pi.registerCommand("voice", {
    description: "Start or stop dictation. Speech is pasted into the editor.",
    handler: async (_args, ctx) => {
      session ??= new VoiceSession(ctx);
      if (session.recording) {
        await session.stop();
      } else {
        session.start();
      }
    },
  });
}
```

- [ ] **Step 5: Run the tests**

Run:
```bash
cd /home/joe/Development/pi-nix/packages/first-party/pi-voice && bun test 2>&1 | tail -8
```

Expected: every test passes. If the toggle test times out, the fake binary's `trap` is not firing; POSIX `sh` runs a trap only between commands, which is why the loop sleeps in 50 ms slices rather than blocking.

- [ ] **Step 6: Commit**

```bash
cd /home/joe/Development/pi-nix
git add packages/first-party/pi-voice
git commit -m "feat(pi-voice): controller, /voice command, and the paste

Spawns record --stream over node's child_process because pi.exec resolves
once with the whole of stdout and cannot deliver partials. Stops with
SIGINT so audiomemo's handler finishes the file and emits final; stop()
resolves only after the child closes, which is what makes the paste
observable. The meter lives in a belowEditor widget and only a short
token goes through setStatus, because sanitizeStatusText would eat the
bar's padding."
```

---

### Task 11: Nix packaging, the `voice` option, and the jail

The derivation, the option surface that wires it into pi, and the bubblewrap permissions without which the microphone is simply absent.

**On `mkPiExtension`.** Phase 2's `mkPiExtension` (`docs/plans/2026-08-18-pi-nix-fork.md` Task 3) takes `{ pname, version, url, hash, ... }` and fetches an npm tarball. A first-party extension has no tarball, so this task **consumes its passthru contract without calling it**: `piEntrypoint` (list of str), `piSkills`, `piPrompts`, `settings`, `promptFragment`. That contract is what `extensionPackages` reads (fork plan Task 6), and it is identical for `mkPiExtension` and `mkPiPlugin`, so a locally-built derivation carrying the same five attributes drops into the same list.

**Assumptions recorded because the fork plan is mid-revision:**

- `mkPiPlugin` exists in `lib/` with `{ name, description, version, skills, prompts, extensions, themes }` (fork plan Task 2), but its `extensions` argument shape is not pinned down enough to depend on. This task therefore builds pi-voice with `runCommand` and sets the passthru directly, matching what `agent-statusline`'s `pi-extension` derivation already does. If `mkPiExtension` grows a `src` argument during the revision, replace the derivation body with a call to it: the passthru output is identical either way, so nothing downstream changes.
- Finding F9 records that the fork moved from `buildNpmPackage` to bun2nix. pi-voice has no runtime dependencies at all, so neither builder applies: the derivation copies two files. bun appears only in `checks.pi-voice-tests`.
- `pi.coding-agent.extensionPackages` is assumed to exist with the semantics in fork plan Task 6. If it has not landed, wire the entrypoint through upstream's `extensions` option directly; the option's type is `listOf str` either way.

**Files:** (all in `/home/joe/Development/pi-nix`)
- Create: `packages/first-party/pi-voice/default.nix`
- Create: `packages/first-party/default.nix`
- Modify: `flake.nix` (add `packages.pi-voice`, `checks.pi-voice-tests`, and the `audiomemo` input)
- Modify: `coding-agent/extra-options.nix` (the `voice` option)
- Modify: `tests/options-test.nix`

**Interfaces:**
- Consumes: the passthru contract from fork plan Task 3; `pi.coding-agent.extensionPackages` from fork plan Task 6
- Produces:
  - `packages.<system>.pi-voice`, carrying `passthru.piEntrypoint`, `piSkills`, `piPrompts`, `settings`, `promptFragment`
  - `checks.<system>.pi-voice-tests`
  - `pi.coding-agent.voice` — a submodule with `enable`, `package`, `audiomemo`, `device`, `extraArgs`, `barWidth`, `placement`, `keyFiles`, `configFile`, and the read-only `jailPermissions`

- [ ] **Step 1: Write the derivation**

Create `packages/first-party/pi-voice/default.nix`:

```nix
{
  lib,
  runCommand,
}:
# pi-voice has no runtime dependencies: pi injects @earendil-works/pi-tui and
# @earendil-works/pi-coding-agent as jiti virtual modules, and the extension
# imports neither. So there is no node_modules to materialise and no builder to
# run; the derivation is a copy carrying the passthru contract that
# mkPiExtension and mkPiPlugin both publish.
(runCommand "pi-voice" { } ''
  mkdir -p $out
  cp ${./package.json} $out/package.json
  cp ${./voice.ts} $out/voice.ts
'').overrideAttrs
  (old: {
    passthru = (old.passthru or { }) // {
      # The package root, so pi reads pi.extensions from package.json rather
      # than being told the entrypoint twice.
      piEntrypoint = [ "${placeholder "out"}" ];
      piSkills = [ ];
      piPrompts = [ ];
      settings = { };
      promptFragment = null;
    };
    meta = {
      description = "Dictation for pi, over audiomemo record --stream";
      license = lib.licenses.mit;
      platforms = lib.platforms.unix;
    };
  })
```

`placeholder "out"` does not work inside `passthru`, so use the two-stage form instead:

```nix
{
  lib,
  runCommand,
}:
let
  src = runCommand "pi-voice" { } ''
    mkdir -p $out
    cp ${./package.json} $out/package.json
    cp ${./voice.ts} $out/voice.ts
  '';
in
src.overrideAttrs (old: {
  passthru = (old.passthru or { }) // {
    piEntrypoint = [ "${src}" ];
    piSkills = [ ];
    piPrompts = [ ];
    settings = { };
    promptFragment = null;
  };
  meta = {
    description = "Dictation for pi, over audiomemo record --stream";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
})
```

Use the second form. The first is shown only because the `placeholder` trap costs an hour if you hit it.

Create `packages/first-party/default.nix`:

```nix
{ pkgs, ... }:
{
  pi-voice = pkgs.callPackage ./pi-voice { };
}
```

- [ ] **Step 2: Write the failing check**

Append to `tests/options-test.nix`, in the `let` block:

```nix
  firstParty = import ../packages/first-party { inherit pkgs; };

  withVoice = evalPi {
    pi.coding-agent.voice = {
      enable = true;
      device = "mic";
      keyFiles.ELEVENLABS_API_KEY_FILE = "/run/agenix/elevenlabs_api_key";
      configFile = "/home/joe/.config/audiomemo/config.toml";
    };
  };
```

and these assertions:

```nix
# The extension reaches pi through the same passthru contract the npm pins use.
assert firstParty.pi-voice.passthru.piEntrypoint == [ "${firstParty.pi-voice}" ];
assert firstParty.pi-voice.passthru.piSkills == [ ];
assert firstParty.pi-voice.passthru.settings == { };
assert firstParty.pi-voice.passthru.promptFragment == null;

# Enabling voice mounts the extension and points it at a store path rather
# than at whatever `record` happens to be on PATH inside the jail.
assert flagValues withVoice.finalArgs "--extension" != [ ];
assert lib.hasSuffix "/bin/record" withVoice.environment.PI_VOICE_RECORD_BIN.value;
assert withVoice.environment.PI_VOICE_RECORD_ARGS.value == "-D mic";

# Keys travel as paths. A value here would put a secret in the store.
assert withVoice.environment.ELEVENLABS_API_KEY_FILE.value == "/run/agenix/elevenlabs_api_key";
assert !(withVoice.environment ? ELEVENLABS_API_KEY);

# Disabled by default, and contributing nothing when disabled.
assert !(evalPi { }).environment ? PI_VOICE_RECORD_BIN;
assert (evalPi { }).config.pi.coding-agent.voice.jailPermissions == null
  || lib.length ((evalPi { }).config.pi.coding-agent.voice.jailPermissions fakeCombinators) == 0;
```

with a stand-in for jail.nix's combinators so the permission list can be asserted without building a jail:

```nix
  fakeCombinators = {
    pulse = "pulse";
    pipewire = "pipewire";
    try-readonly = p: "try-readonly:${p}";
    add-pkg-deps = ps: "add-pkg-deps:${toString (builtins.length ps)}";
  };
```

and the permission assertions:

```nix
# Without these the microphone is not merely restricted inside the jail: it is
# absent, and audiomemo reports an empty device list with no error.
assert builtins.elem "pulse" (withVoice.config.pi.coding-agent.voice.jailPermissions fakeCombinators);
assert builtins.elem "pipewire" (withVoice.config.pi.coding-agent.voice.jailPermissions fakeCombinators);
assert builtins.elem "try-readonly:/run/agenix/elevenlabs_api_key"
  (withVoice.config.pi.coding-agent.voice.jailPermissions fakeCombinators);
assert builtins.elem "try-readonly:/home/joe/.config/audiomemo/config.toml"
  (withVoice.config.pi.coding-agent.voice.jailPermissions fakeCombinators);
```

- [ ] **Step 3: Run the check to verify it fails**

Run:
```bash
cd /home/joe/Development/pi-nix && nix build .#checks.x86_64-linux.options -L 2>&1 | tail -4
```

Expected: `error: The option 'pi.coding-agent.voice' does not exist.`

- [ ] **Step 4: Implement the option in `coding-agent/extra-options.nix`**

```nix
    voice = lib.mkOption {
      default = { };
      description = ''
        Dictation through the first-party pi-voice extension, which drives
        `audiomemo record --stream`.
      '';
      type = lib.types.submodule (
        { config, ... }:
        {
          options = {
            enable = lib.mkEnableOption "pi-voice dictation";

            package = lib.mkOption {
              type = lib.types.package;
              default = self.packages.${pkgs.stdenv.hostPlatform.system}.pi-voice;
              description = "The pi-voice extension package.";
            };

            audiomemo = lib.mkOption {
              type = lib.types.package;
              description = ''
                The audiomemo package providing `record`. Its runtime closure
                carries ffmpeg, so binding the closure into the jail is what
                makes recording possible there.
              '';
            };

            device = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              example = "mic";
              description = ''
                Device alias, group, or raw name passed as `-D`. Null uses
                `record.device` from audiomemo's own config, which is where
                that decision belongs.
              '';
            };

            extraArgs = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              example = [ "--temp" ];
              description = "Further arguments for `record`. `--stream` and `-t` are always passed.";
            };

            barWidth = lib.mkOption {
              type = lib.types.ints.between 1 64;
              default = 12;
              description = "Width of the VU bar, in terminal cells.";
            };

            placement = lib.mkOption {
              type = lib.types.enum [ "aboveEditor" "belowEditor" ];
              default = "belowEditor";
              description = "Where the voice widget sits relative to the input editor.";
            };

            keyFiles = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              default = { };
              example = lib.literalExpression ''
                {
                  ELEVENLABS_API_KEY_FILE = "/run/agenix/elevenlabs_api_key";
                  DEEPGRAM_API_KEY_FILE = "/run/agenix/deepgram_api_key";
                }
              '';
              description = ''
                Paths to files holding API keys, passed to audiomemo as
                `*_API_KEY_FILE`. audiomemo reads the files itself
                (internal/config/config.go), so no secret enters the store or
                the process environment. Recognised names:
                ELEVENLABS_API_KEY_FILE, DEEPGRAM_API_KEY_FILE,
                OPENAI_API_KEY_FILE, MISTRAL_API_KEY_FILE, HF_TOKEN_FILE.
              '';
            };

            configFile = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              example = "/home/joe/.config/audiomemo/config.toml";
              description = ''
                audiomemo's config file. Only used to build the jail's read
                bind: jail.nix's base permission puts a tmpfs over $HOME, so
                without this the file is absent and audiomemo silently falls
                back to its defaults.
              '';
            };

            jailPermissions = lib.mkOption {
              type = lib.types.functionTo (lib.types.listOf lib.types.raw);
              readOnly = true;
              internal = false;
              default =
                combinators:
                lib.optionals config.enable (
                  with combinators;
                  [
                    # Verified empirically on 2026-08-18: with the PulseAudio
                    # socket bound, `audiomemo record -L` inside bwrap lists
                    # every device and ffmpeg captures audio. Without it the
                    # list is empty and there is no error.
                    pulse
                    pipewire
                    (add-pkg-deps [ config.audiomemo ])
                  ]
                  ++ lib.optional (config.configFile != null) (try-readonly config.configFile)
                  ++ map try-readonly (lib.attrValues config.keyFiles)
                );
              description = ''
                Permissions this option needs from jail.nix. `jail.permissions`
                is a function-typed option, so module definitions cannot merge
                into it; splice this into your own definition instead:

                  jail.permissions = c: (with c; [ network mount-cwd ])
                    ++ config.programs.pi.coding-agent.voice.jailPermissions c;
              '';
            };
          };
        }
      );
    };
```

and, in the `let` block that assembles the final configuration:

```nix
  voice = cfg.voice;

  voiceArgs = lib.optionals (voice.device != null) [ "-D" voice.device ] ++ voice.extraArgs;

  voiceEnv = lib.optionalAttrs voice.enable (
    {
      PI_VOICE_RECORD_BIN = { value = "${voice.audiomemo}/bin/record"; };
      PI_VOICE_RECORD_ARGS = { value = lib.concatStringsSep " " voiceArgs; };
      PI_VOICE_BAR_WIDTH = { value = toString voice.barWidth; };
      PI_VOICE_PLACEMENT = { value = voice.placement; };
    }
    # Key *paths*, never key values. audiomemo reads the file itself, so the
    # secret never enters the store or this process's environment.
    // lib.mapAttrs (_: path: { value = path; }) voice.keyFiles
  );

  voicePackages = lib.optional voice.enable voice.package;
```

then add `voicePackages` to whatever list feeds `extensionPackages`, and `voiceEnv` to the `environment` merge.

- [ ] **Step 5: Add the flake outputs**

In `flake.nix`, inside the per-system outputs:

```nix
          pi-voice = (import ./packages/first-party { inherit pkgs; }).pi-voice;
```

and a check that runs the extension's tests under bun:

```nix
          pi-voice-tests =
            pkgs.runCommand "pi-voice-tests"
              {
                nativeBuildInputs = [ pkgs.bun ];
                src = ./packages/first-party/pi-voice;
              }
              ''
                cp -r $src work && chmod -R u+w work && cd work
                # bun writes a cache under $HOME and the sandbox has none.
                export HOME=$TMPDIR
                # The extension has no dependencies, so this needs no network.
                bun test
                touch $out
              '';
```

- [ ] **Step 6: Run everything**

Run:
```bash
cd /home/joe/Development/pi-nix && nix fmt && \
  nix build .#pi-voice -L && ls result/ && \
  nix build .#checks.x86_64-linux.pi-voice-tests -L 2>&1 | tail -5 && \
  nix build .#checks.x86_64-linux.options -L 2>&1 | tail -3
```

Expected: `package.json` and `voice.ts` in `result/`, the bun tests pass inside the sandbox, and the options check passes.

- [ ] **Step 7: Verify the jail permissions do what the option claims**

The option's whole justification is that the microphone is absent without it. Prove both directions rather than trusting the combinator names:

```bash
AM=$(nix build --no-link --print-out-paths 'github:joegoldin/audiomemo#audiomemo' 2>/dev/null || echo /run/current-system/sw)
# Without the socket: an empty device list, and no error.
bwrap --ro-bind /nix/store /nix/store --proc /proc --dev /dev --tmpfs /tmp --tmpfs "$HOME" \
  --ro-bind "$HOME/.config/audiomemo/config.toml" "$HOME/.config/audiomemo/config.toml" \
  --setenv HOME "$HOME" --setenv TERM dumb -- "$AM/bin/audiomemo" record -L | wc -l
# With it: the full list.
bwrap --ro-bind /nix/store /nix/store --proc /proc --dev /dev --tmpfs /tmp --tmpfs "$HOME" \
  --ro-bind "$HOME/.config/audiomemo/config.toml" "$HOME/.config/audiomemo/config.toml" \
  --bind "$XDG_RUNTIME_DIR/pulse" "$XDG_RUNTIME_DIR/pulse" \
  --setenv XDG_RUNTIME_DIR "$XDG_RUNTIME_DIR" --setenv HOME "$HOME" --setenv TERM dumb \
  -- "$AM/bin/audiomemo" record -L | wc -l
```

Expected, and observed on elphael on 2026-08-18: `0` then a two-digit count. If the first command prints a usage error about `/dev/tty` instead, the config bind is missing and audiomemo is trying to run its onboarding TUI, which is its own reason the `configFile` bind is not optional.

- [ ] **Step 8: Commit**

```bash
cd /home/joe/Development/pi-nix
git add -A
git commit -m "feat(pi-voice): package it and add the voice option

The derivation is a copy: pi-voice imports nothing, so there is no
node_modules to build. It carries the same five passthru attributes as a
pinned npm extension, so extensionPackages treats them alike.

jailPermissions is a read-only function rather than a contribution to
jail.permissions, because that option is function-typed and module
definitions cannot merge into it. It is not optional: with no audio
socket bound, audiomemo lists zero devices inside the jail and reports
no error, which is the same silent-empty failure the design already
documents for API keys."
```

---

### Task 12: dotfiles wiring and the end-to-end check

The third repo, and the only place the agenix paths are real. Voice is enabled per host, because a headless machine has no microphone worth wiring.

**Files:** (all in `/home/joe/dotfiles`)
- Modify: `flake.nix` (bump the `audiomemo` input past `6018d29`)
- Modify: `modules/ai/pi.nix` (the `voice` block and the jail permission splice)
- Modify: `modules/hosts/elphael/default.nix` (agenix secrets the voice path needs)

**Interfaces:**
- Consumes: `pi.coding-agent.voice` and `voice.jailPermissions` from Task 11
- Produces: no new option surface; `programs.pi.coding-agent.voice` is configured, not redeclared

- [ ] **Step 1: Bump the audiomemo input**

```bash
cd /home/joe/dotfiles && nix flake lock --update-input audiomemo && \
  grep -A3 '"audiomemo"' flake.lock | grep '"rev"'
```

Expected: the revision from Task 6 Step 6, not `6018d29`.

- [ ] **Step 2: Declare the secrets the voice path can use**

audiomemo's autodetect prefers ElevenLabs, falls back to Deepgram, then OpenAI, then Mistral, then a local whisper (`internal/transcribe/dispatch.go:20-40`). Only ElevenLabs is declared on elphael today, and only `elevenlabs_api_key`, `deepgram_api_key`, and `openai_api_key` exist in `dotfiles-secrets`. There is no Mistral secret and no HuggingFace token, so those two `*_FILE` variables are simply not set; audiomemo treats an unset variable as "this backend is unconfigured", which is the correct outcome.

In `modules/hosts/elphael/default.nix`, beside the existing `age.secrets.elevenlabs_api_key`:

```nix
      age.secrets.deepgram_api_key = {
        file = "${inputs.dotfiles-secrets}/deepgram_api_key.age";
        mode = "0400";
        owner = meta.username;
      };
      age.secrets.openai_api_key = {
        file = "${inputs.dotfiles-secrets}/openai_api_key.age";
        mode = "0400";
        owner = meta.username;
      };
```

- [ ] **Step 3: Wire voice in `modules/ai/pi.nix`**

Inside the `den.aspects.pi.homeManager` aspect, in `programs.pi.coding-agent`:

```nix
      voice = {
        enable = pkgs.stdenv.hostPlatform.isLinux;
        audiomemo = pkgs.audiomemo;
        # Null would use audiomemo's own record.device, but the picker is a TUI
        # and --stream is headless, so the device is named here.
        device = "mic";
        keyFiles = {
          ELEVENLABS_API_KEY_FILE = "/run/agenix/elevenlabs_api_key";
          DEEPGRAM_API_KEY_FILE = "/run/agenix/deepgram_api_key";
          OPENAI_API_KEY_FILE = "/run/agenix/openai_api_key";
        };
        configFile = "${config.home.homeDirectory}/.config/audiomemo/config.toml";
      };
```

`configFile` points at the real file rather than a store path on purpose: the audiomemo home-manager module installs it as a writable copy because the device TUI edits it (`audiomemo/nix/home-manager.nix:55-64`), and `settings` there is the declared source of truth. Setting `XDG_CONFIG_HOME` is unnecessary: with `HOME` forwarded into the jail and the file bound at `$HOME/.config/audiomemo/config.toml`, audiomemo's own fallback in `config.Load` finds it.

- [ ] **Step 4: Splice the jail permissions**

Still in `modules/ai/pi.nix`, where `jail` is configured:

```nix
      jail = {
        enable = pkgs.stdenv.hostPlatform.isLinux;
        # jail.permissions is function-typed, so module definitions cannot
        # merge into it. Every contributor has to be spliced in here.
        permissions =
          combinators:
          (with combinators; [
            network
            mount-cwd
            (try-readwrite "${config.home.homeDirectory}/.1password/agent.sock")
            (try-readonly "${config.home.homeDirectory}/.ssh/config")
            (try-readonly "${config.home.homeDirectory}/.ssh/known_hosts")
          ])
          ++ config.programs.pi.coding-agent.voice.jailPermissions combinators;
      };
```

- [ ] **Step 5: Build**

```bash
cd /home/joe/dotfiles && nix build \
  '.#nixosConfigurations.elphael.config.home-manager.users.joe.home.activationPackage' -L 2>&1 | tail -5
```

Expected: the build succeeds. A failure naming `voice.audiomemo` means the option has no default and the host did not set it, which is deliberate: the jail needs the exact derivation whose closure it binds, so guessing would be worse than an error.

- [ ] **Step 6: Prove no secret reached the store**

```bash
cd /home/joe/dotfiles
grep -rIl "$(head -c 8 /run/agenix/elevenlabs_api_key)" ./result/ 2>/dev/null | head
grep -r 'ELEVENLABS_API_KEY=' ./result/ 2>/dev/null | head
```

Expected: both print nothing. The wrapper should contain `export ELEVENLABS_API_KEY_FILE=/run/agenix/elevenlabs_api_key` and no key value; confirm with:

```bash
grep -o 'ELEVENLABS_API_KEY_FILE=[^ ]*' ./result/home-path/bin/pi 2>/dev/null || \
  grep -rho 'ELEVENLABS_API_KEY_FILE=[^ ]*' ./result/ | head -1
```

Expected: `ELEVENLABS_API_KEY_FILE=/run/agenix/elevenlabs_api_key`.

- [ ] **Step 7: End-to-end check with a real microphone**

Activate, then in a terminal:

```bash
pi
```

and inside pi, type `/voice`, speak a sentence, then `/voice` again.

Expected:
1. A two-row widget appears below the input box: a red `●`, a running clock, a bar that moves with your voice, and a dB readout.
2. Text appears on the second row as you speak, dim while the utterance is in flight and normal once committed.
3. The statusline's mic glyph lights up. Confirm the file directly with `jq .voice ~/.claude/settings.local.json`, which should read `{"enabled": true, "mode": "toggle", "pid": <pi's pid>, "since": <ms>}`.
4. The second `/voice` clears the widget, the transcript lands in the input editor, and `jq .voice ~/.claude/settings.local.json` reads `{"enabled": false}`.

If the widget appears but the bar never moves and no text arrives, the jail is missing the audio socket; re-run Task 11 Step 7. If the bar moves but no text arrives and the widget's note says `no transcription backend configured`, the key file bind is missing; check that `/run/agenix/elevenlabs_api_key` is in the permission list and readable by your user.

- [ ] **Step 8: Check it outside the jail too**

```bash
programs.pi.coding-agent.jail.enable = false;  # temporarily, then rebuild
```

Run `/voice` again. Everything should behave identically, which is the proof that the jail permissions are additive rather than load-bearing for the extension's own logic.

- [ ] **Step 9: Commit**

```bash
cd /home/joe/dotfiles
git add -A
git commit -m "feat(pi): wire pi-voice dictation

Keys are agenix paths handed to audiomemo as *_API_KEY_FILE, so nothing
enters the store or pi's environment. The jail permissions come from
voice.jailPermissions and have to be spliced by hand, because
jail.permissions is function-typed and does not merge. Without the audio
socket bound, audiomemo lists zero devices inside the jail and says
nothing about it."
```

---

## Self-Review

**Spec coverage.** Design §18 in full. `record --stream` with its NDJSON schema is Tasks 1-6; the `pi-voice` extension is Tasks 7-10; the voice state file that closes §18's "a gap this closes" is Task 8; Nix packaging against §8's passthru contract is Task 11; the §18 secrets story and the §9 jail are Tasks 11-12. §18's claim that the flag "composes with the existing device, duration, and format flags without duplicating them" is what Task 3 implements and Task 5 relies on, since the batch backend is read back from the argument list `--transcribe-args` already builds.

**The jail verdict, stated plainly.** Microphone capture works inside the bubblewrap jail, and does not work by default. With no audio permission, `audiomemo record -L` inside a jail-shaped bwrap lists zero devices and exits zero, which is the same silent-empty failure mode the design already documents for API keys (F5). With `pulse` bound, the same command lists every device and ffmpeg captures audio; both were run on elphael on 2026-08-18. Four things must be bound and none of them are today: the PulseAudio socket (`$XDG_RUNTIME_DIR/pulse`, which on this host is pipewire-pulse, `Server Name: PulseAudio (on PipeWire 1.6.6)`), the audiomemo closure for ffmpeg, the agenix key files, and `~/.config/audiomemo/config.toml`. `/dev/snd` is not among them: audiomemo shells to `ffmpeg -f pulse` (`internal/record/recorder.go:52-57`) and enumerates with `ffmpeg -sources pulse` (`internal/record/devices.go:189-197`), so nothing touches ALSA directly. `--dev /dev` already supplies `/dev/shm`, so PulseAudio's shared-memory transport has somewhere to land. Only `pactl`, used for mute (`internal/record/mute.go:19`), is absent, and that path already degrades to a no-op.

**What the config bind buys beyond convenience.** With `$HOME` under a tmpfs and no config file, `record` decides it needs onboarding (`config.NeedsOnboarding`) and tries to open `/dev/tty`, which fails. That is why `configFile` is not an optional nicety.

**Known gaps carried forward.** No Mistral or HuggingFace secret exists in `dotfiles-secrets`, so those two `*_FILE` variables are never set; audiomemo reads an unset variable as an unconfigured backend, which is correct rather than degraded. Under the jail the voice state file lands in the jail's tmpfs `$HOME/.claude`, so pi's mic state is visible to the statusline running inside the same jail but not to a Claude Code session outside it. Binding `~/.claude` read-write would close that, and this plan does not, because nothing needs it: the reader is always a child of the writer.

**Type consistency.** The Go event structs in Task 1 and the TypeScript interfaces in Task 7 agree field for field, including `device_label`, `sample_rate`, `transcript_path`, and `exit_code`. `stream.ModeLive`/`ModeBatch`/`ModeNone` are produced by `resolveStreamMode` in Task 3, emitted by `runRecordStream` in Task 4, and consumed by `VoiceSession.handleEvent` in Task 10 under the same three strings. `stream.SourceLive`/`SourceBatch` are set in Task 5 and typed in Task 7. The five passthru attributes in Task 11 match the names the fork plan's Task 6 test asserts on.

**Where this plan could be wrong.** Three places, each with the check that would catch it. `mkPiExtension`'s final argument shape is still moving, so Task 11 consumes the passthru contract rather than the builder and says so; the options check in Task 11 Step 2 fails loudly if the contract changed. Task 10's toggle test depends on a POSIX `sh` trap firing between commands, which is why the fake binary sleeps in 50 ms slices rather than blocking. And `pactl`'s absence inside the jail means mute is inert there, which no test covers because it was already best-effort before this plan touched it.
