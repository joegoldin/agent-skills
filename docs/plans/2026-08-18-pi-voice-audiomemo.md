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
- pi-voice imports nothing. pi injects `@earendil-works/pi-tui` as a jiti virtual module at runtime (`src/core/extensions/loader.ts:50-74`), but `bun test` in the Nix check sandbox does not, and pulling pi-tui in for two width functions would need a bun2nix'd devDependency. The extension owns ~40 lines of width maths instead, under test.
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
