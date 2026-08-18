# agent-statusline: native pi rendering (phase 1b)

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development (recommended) or executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the broken `ctx.ui.setStatus` pi integration with a native pi component that owns layout and colour, driven by structured JSON from the Go binary. Claude Code's rendering must not change by a single byte.

**Architecture:** Hybrid. The Go binary keeps every stateful subsystem it already owns — git cache, the tool-timing sidecar shared byte-for-byte with Claude Code's hooks, compaction tracking, burn rate, transcript parsing, `FromToolTiming` — and gains a second *output encoder*: `--emit json` serialises each widget into semantic **spans** (text plus a colour *intent*, or a bar plus a fill fraction) instead of pre-rendered ANSI. A native pi TypeScript component consumes that snapshot and does all layout and colour against pi's own contract: `render(width): string[]`, the live theme proxy, `setWidget(..., {placement: "belowEditor"})` for the rows, and `setFooter` to blank pi's built-in footer and capture the `FooterDataProvider`. Repaint is a local `setInterval` calling `tui.requestRender()`, so the spinner and live clocks tick without spawning a process.

The pivot is that colour stops being a literal. Today `internal/render/ansi.go` hardcodes SGR 31/32/33/35/36 and `internal/render/gradient.go` hardcodes a 24-bit ramp. After this plan every widget declares an *intent* (`ok`, `warn`, `danger`, `path`, `accent`, ...); Go's ANSI encoder maps intents back to exactly today's SGR codes (the golden files are the proof), and pi's encoder maps them onto theme tokens (`success`, `warning`, `error`, `mdLink`, `accent`, ...). One semantic model, two encoders.

**Tech Stack:** Go 1.26 (stdlib plus vendored `golang.org/x/text`), TypeScript on **bun** (`bun test`, `bun.lock`, bun2nix), Nix flake, garnix CI.

Prerequisite reading: `docs/plans/2026-08-18-agent-statusline.md` (phase 1, shipped). All pi citations are against `@earendil-works/pi-coding-agent@0.84.2` and `@earendil-works/pi-tui@0.84.2`.

### Why this is a rewrite and not a patch

`pi`'s footer sink sanitises what it is given — `src/modes/interactive/components/footer.ts:13-19`:

```ts
function sanitizeStatusText(text: string): string {
	return text
		.replace(/[\r\n\t]/g, " ")
		.replace(/ +/g, " ")
		.trim();
}
```

Every string passed to `ctx.ui.setStatus` goes through that (`footer.ts:232-241`). Two consequences kill the shipped integration outright: newline-joined rows collapse into one line, and `strings.Repeat(" ", n)` flex spacers (`internal/layout/layout.go:188`) collapse to a single space, destroying all alignment. On top of that the extension registers no timer, so `runningSpinnerFrames` (`internal/widgets/activity.go`) and every elapsed clock are frozen between events. Neither problem is fixable inside `setStatus`; both disappear on the component-factory path, which is what all three surveyed real-world pi statusline extensions use (`@narumitw/pi-statusline`, `pi-powerline-footer`, tomsej's `pi-ext`).

## Global Constraints

- **Claude-mode output must remain byte-identical.** `internal/e2e/testdata/{idle,full,narrow}.golden` are the regression gate. They are never regenerated in this plan. If a refactor changes them, the refactor is wrong.
- **`--emit ansi` is the default and stays the default.** Claude Code's `statusLine.command`, the pi ANSI goldens, and humans debugging all keep working with no flag.
- Go stdlib only; the tree vendors its deps and sets `vendorHash = null`. Do not add a Go dependency.
- **The runtime pi extension has zero runtime npm/bun dependencies.** pi loads `.ts` files copied out of the Nix store with no `node_modules` beside them. `@earendil-works/pi-tui` and `@earendil-works/pi-coding-agent` may be **devDependencies only**, imported exclusively from `*.test.ts`.
- **bun is the JavaScript toolchain.** `bun test`, `bun install`, `bun.lock`, `bun2nix`. No `npm`, no `npx`, no `package-lock.json`, no `vitest`. Nix invocations use `nix shell nixpkgs#bun`.
- **The extension reads no config file.** The Go binary echoes its effective config into the snapshot. One config reader (`internal/config`), one resolution order, one set of defaults. `lib/options.nix` stays the single schema.
- Colour in the snapshot is a **semantic intent**, never RGB and never an SGR code. A grep for `38;2;` in `extension/src/**` (excluding tests) must find hits only inside the bar renderer, and those must derive from `theme.getFgAnsi(...)`.
- Only one extension can own pi's footer — last `setFooter` wins (`@narumitw/pi-statusline`'s README documents the same conflict). Because we take it, we are responsible for re-rendering other extensions' `setStatus` lines.
- All UI installation is guarded by `ctx.mode === "tui"`. `setWidget`/`setFooter` are stubbed headless (`runner.ts:246`) and `setFooter` is absent over RPC (`rpc-mode.ts:195-205`).
- Nix formatting: `nixfmt`. Go: `gofmt`. TypeScript: match the existing 2-space style in `extension/statusline.ts`.
- Go is not on `PATH` in this environment. Every Go command is written as `nix shell nixpkgs#go --command go ...`. `bun` **is** on `PATH` (1.3.13); Nix-sandboxed invocations still go through `nix shell nixpkgs#bun`.

### Reference: the intent table

The contract between the two encoders. It appears in code twice — `internal/render/span.go` and `extension/src/intents.ts` — and a test on each side pins its own half.

| intent | meaning | Go SGR (must match today) | pi theme token |
|---|---|---|---|
| `text` | default foreground | *(unwrapped)* | `text` |
| `dim` | metadata, de-emphasised | `2` | `dim` |
| `muted` | chrome / separators (renderer-only) | `2` | `muted` |
| `accent` | primary identity | `36` | `accent` |
| `meta` | derived / secondary identity | `35` | `customMessageLabel` |
| `path` | filesystem location | `33` | `mdLink` |
| `ok` | healthy, complete, low usage | `32` | `success` |
| `warn` | elevated usage | `33` | `warning` |
| `caution` | high usage (5-step 4th step) | `38;5;208` | `warning`, bolded |
| `danger` | critical, billed, over pace | `31` | `error` |

`path` and `warn` share SGR 33 in Go — which is why the Claude goldens do not move — but diverge under pi, where a directory is a link and a rate limit is a warning. That divergence is the entire point of the exercise.

### Reference: bun, and the Bun-built pi

The runtime pi is `pi-nix`'s `packages.coding-agent-bun` (`coding-agent/package-bun.nix`), not the npm build. Everything this plan relies on is identical between the two builds, and that is a claim worth stating rather than assuming:

- Both derivations build the **same** `packages/coding-agent/src` and `packages/tui/src` TypeScript from the same `fetchFromGitHub` `src` (`pi-nix/flake.nix:62-67` — `coding-agent` and `coding-agent-bun` are both `callPackage`'d with the same `inherit src version`).
- `package-bun.nix`'s `preBuild` patches touch only `packages/ai/src/models*.ts`, `packages/agent/src/agent.ts`, `packages/tui/src/utils.ts` (an `@ts-nocheck` header, a typecheck suppression with no runtime effect), the CHANGELOG URL in `interactive-mode.ts`, and npm-to-bun script rewrites in `package.json`. None of `footer.ts`, `theme.ts`, `extensions/types.ts`, or the widget/footer plumbing in `interactive-mode.ts` is modified.
- Therefore `setWidget`/`setFooter`/`Component.render(width)`/`Theme.fg`/`getFgAnsi`/`getColorMode`/`TUI.requestRender`/`sanitizeStatusText` behave identically. Task 10 adds a smoke test against the **bun** build, so this stops being an argument and becomes an observation.

**`bun test` over vitest, decided empirically.** The existing `extension/statusline.test.ts` has 27 passing vitest tests. Porting was measured, not guessed:

```bash
cd /tmp && rm -rf buntest2 && mkdir buntest2 && cd buntest2 \
  && cp /home/joe/Development/agent-statusline/extension/statusline.{ts,test.ts} . \
  && sed -i 's#from "vitest"#from "bun:test"#' statusline.test.ts \
  && bun test
```

That single-line import change is the entire migration; all 27 tests pass (`27 pass, 0 fail`). `bun:test` also covers everything the new tests need — verified on bun 1.3.13: `jest.useFakeTimers()`, `jest.advanceTimersByTime()`, `jest.getTimerCount()`, `mock()`, `toHaveBeenCalledTimes`. With the migration cost at one line and the toolchain-consistency win real, vitest goes.

---

### Task 1: Spans as the semantic render form

Introduce `render.Span` and make ANSI one encoding of it. Nothing is wired to a widget yet, so the golden files cannot move; this task exists to get the encoder under test before anything depends on it.

**Files:**
- Create: `internal/render/span.go`
- Create: `internal/render/span_test.go`
- Modify: `internal/render/ansi.go` (re-express the colour helpers as intent wrappers)
- Modify: `internal/render/threshold.go` (add intent-returning twins)

**Interfaces:**
- Consumes: `render.GradientBar`, `render.BrailleStyle`, `render.BlockStyle`, `render.LineStyle`, `render.Hyperlink` (unchanged, phase 1)
- Produces:
  - `type render.Intent string` with constants `IntentText`, `IntentDim`, `IntentMuted`, `IntentAccent`, `IntentMeta`, `IntentPath`, `IntentOK`, `IntentWarn`, `IntentCaution`, `IntentDanger`
  - `func (Intent) SGR() string`, `func (Intent) Wrap(s string) string`
  - `type render.Span struct` with JSON tags `kind,text,intent,link,fill,cells,style`
  - `type render.Spans []Span`, `func (Spans) ANSI() string`
  - `func render.Text(i Intent, s string) Span`, `func render.Link(i Intent, url, s string) Span`, `func render.Bar(fill float64, cells int, style string) Span`
  - `func render.ThresholdIntent(pct float64) Intent`, `func render.ThresholdIntent5(pct float64) Intent`
  - `const render.BarBraille/BarBlock/BarLine = "braille"/"block"/"line"`

- [ ] **Step 1: Write the failing test**

Create `internal/render/span_test.go`:

```go
package render

import "testing"

func TestIntentSGRMatchesLegacyHelpers(t *testing.T) {
	// The whole refactor rests on this: every intent must re-emit exactly the
	// bytes the old helper emitted, or the Claude goldens move.
	cases := []struct {
		intent Intent
		legacy func(string) string
	}{
		{IntentDim, Dim},
		{IntentOK, Green},
		{IntentWarn, Yellow},
		{IntentPath, Yellow},
		{IntentCaution, Orange},
		{IntentDanger, Red},
		{IntentAccent, Cyan},
		{IntentMeta, Magenta},
	}
	for _, c := range cases {
		if got, want := c.intent.Wrap("x"), c.legacy("x"); got != want {
			t.Errorf("%s.Wrap = %q, legacy = %q", c.intent, got, want)
		}
		if got := c.intent.Wrap(""); got != "" {
			t.Errorf("%s.Wrap(empty) = %q, want empty", c.intent, got)
		}
	}
}

func TestIntentTextIsUnwrapped(t *testing.T) {
	if got := IntentText.Wrap(" | "); got != " | " {
		t.Errorf("IntentText.Wrap = %q, want the input verbatim", got)
	}
}

func TestSpansANSIConcatenates(t *testing.T) {
	got := Spans{
		Text(IntentOK, " main"),
		Text(IntentText, " "),
		Text(IntentDim, "up2"),
	}.ANSI()
	want := Green(" main") + " " + Dim("up2")
	if got != want {
		t.Errorf("ANSI() = %q, want %q", got, want)
	}
}

func TestSpansANSIRendersBarThroughGradientBar(t *testing.T) {
	got := Spans{Bar(0.535, 10, BarBraille)}.ANSI()
	want := GradientBar(53.5, 10, BrailleStyle)
	if got != want {
		t.Errorf("bar span ANSI mismatch:\n got %q\nwant %q", got, want)
	}
}

func TestSpansANSIAppliesLinkOutsideColour(t *testing.T) {
	got := Spans{Link(IntentAccent, "https://x/1", "#12 approved")}.ANSI()
	want := Hyperlink("https://x/1", Cyan("#12 approved"))
	if got != want {
		t.Errorf("linked span = %q, want %q", got, want)
	}
}

func TestThresholdIntentsMatchThresholdColors(t *testing.T) {
	for _, pct := range []float64{0, 29.9, 30, 44.9, 45, 59.9, 60, 74.9, 75, 84.9, 85, 100} {
		if got, want := ThresholdIntent(pct).Wrap("x"), ThresholdColor(pct)("x"); got != want {
			t.Errorf("ThresholdIntent(%v) = %q, ThresholdColor = %q", pct, got, want)
		}
		if got, want := ThresholdIntent5(pct).Wrap("x"), ThresholdColor5(pct)("x"); got != want {
			t.Errorf("ThresholdIntent5(%v) = %q, ThresholdColor5 = %q", pct, got, want)
		}
	}
}

func TestUnknownBarStyleFallsBackToBlock(t *testing.T) {
	// A snapshot from a newer binary must never panic an older renderer.
	if got := (Spans{Bar(0.5, 4, "no-such-style")}).ANSI(); got != GradientBar(50, 4, BlockStyle) {
		t.Errorf("unknown style did not fall back to block")
	}
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
cd /home/joe/Development/agent-statusline && nix shell nixpkgs#go --command go test ./internal/render/ -run 'TestIntent|TestSpans|TestThresholdIntents|TestUnknownBar' 2>&1 | tail -20
```

Expected: FAIL to compile — `undefined: Intent`, `undefined: Spans`, `undefined: Text`, `undefined: Bar`, `undefined: ThresholdIntent`.

- [ ] **Step 3: Write `internal/render/span.go`**

```go
package render

// Intent is a semantic colour role. It is what widgets declare and what the
// pi snapshot carries on the wire; the literal colour is chosen by whichever
// encoder consumes it. Go's encoder (Intent.SGR) reproduces exactly the ANSI
// the hand-written helpers used to emit, which is why the Claude golden files
// do not move when a widget is converted. pi's encoder maps the same intents
// onto theme tokens, so the statusline finally follows /theme.
type Intent string

const (
	IntentText    Intent = "text"
	IntentDim     Intent = "dim"
	IntentMuted   Intent = "muted"
	IntentAccent  Intent = "accent"
	IntentMeta    Intent = "meta"
	IntentPath    Intent = "path"
	IntentOK      Intent = "ok"
	IntentWarn    Intent = "warn"
	IntentCaution Intent = "caution"
	IntentDanger  Intent = "danger"
)

// SGR returns the parameter bytes for the intent's foreground colour, or ""
// for IntentText (emitted unwrapped). IntentPath and IntentWarn deliberately
// collide on 33 here — Claude Code's palette has no separate colour for a
// path — while pi's encoder splits them.
func (i Intent) SGR() string {
	switch i {
	case IntentDim, IntentMuted:
		return "2"
	case IntentAccent:
		return "36"
	case IntentMeta:
		return "35"
	case IntentPath, IntentWarn:
		return "33"
	case IntentOK:
		return "32"
	case IntentCaution:
		return "38;5;208"
	case IntentDanger:
		return "31"
	}
	return ""
}

// Wrap colours s. An empty string stays empty (no dangling escapes), matching
// the behaviour of the helpers this replaces.
func (i Intent) Wrap(s string) string {
	sgr := i.SGR()
	if sgr == "" {
		return s
	}
	return wrap(sgr, s)
}

// Bar style names, carried on the wire so the pi renderer can pick its own
// glyph set without the Go side shipping glyphs it will not draw.
const (
	BarBraille = "braille"
	BarBlock   = "block"
	BarLine    = "line"
)

// Span is one atom of a widget's output: either a run of text with a colour
// intent, or a progress bar expressed as a fill fraction. It is the JSON wire
// shape for --emit json; the omitempty tags keep the snapshot readable.
type Span struct {
	Kind   string  `json:"kind"`
	Text   string  `json:"text,omitempty"`
	Intent Intent  `json:"intent,omitempty"`
	Link   string  `json:"link,omitempty"`
	Fill   float64 `json:"fill,omitempty"`
	Cells  int     `json:"cells,omitempty"`
	Style  string  `json:"style,omitempty"`
}

// Spans is a widget's full output, in draw order.
type Spans []Span

// Text builds a coloured text span.
func Text(i Intent, s string) Span { return Span{Kind: "text", Text: s, Intent: i} }

// Link builds a coloured text span wrapped in an OSC 8 hyperlink.
func Link(i Intent, url, s string) Span {
	return Span{Kind: "text", Text: s, Intent: i, Link: url}
}

// Bar builds a progress-bar span. fill is a fraction in [0,1]; the pi renderer
// needs the fraction rather than a percentage because it re-derives per-cell
// colours from the active theme's ramp.
func Bar(fill float64, cells int, style string) Span {
	return Span{Kind: "bar", Fill: fill, Cells: cells, Style: style}
}

func barStyle(name string) BarStyle {
	switch name {
	case BarBraille:
		return BrailleStyle
	case BarLine:
		return LineStyle
	}
	return BlockStyle
}

// ANSI encodes spans for a terminal that has no theme of its own — i.e. the
// Claude Code path, and --emit ansi generally.
func (s Spans) ANSI() string {
	out := ""
	for _, sp := range s {
		switch sp.Kind {
		case "bar":
			out += GradientBar(sp.Fill*100, sp.Cells, barStyle(sp.Style))
		default:
			t := sp.Intent.Wrap(sp.Text)
			if sp.Link != "" && t != "" {
				t = Hyperlink(sp.Link, t)
			}
			out += t
		}
	}
	return out
}
```

- [ ] **Step 4: Re-express the legacy helpers in terms of intents**

In `internal/render/ansi.go`, replace the six semantic colour functions and `Orange` with delegations, so there is one table rather than two:

```go
// Semantic colors, kept as functions for the many call sites that predate
// intents. Each is now a thin alias over the intent table in span.go, so the
// two can never drift.
func Dim(s string) string     { return IntentDim.Wrap(s) }
func Red(s string) string     { return IntentDanger.Wrap(s) }
func Green(s string) string   { return IntentOK.Wrap(s) }
func Yellow(s string) string  { return IntentWarn.Wrap(s) }
func Magenta(s string) string { return IntentMeta.Wrap(s) }
func Cyan(s string) string    { return IntentAccent.Wrap(s) }
func Orange(s string) string  { return IntentCaution.Wrap(s) }
```

Leave `wrap`, `reset` and `Hyperlink` exactly as they are.

- [ ] **Step 5: Add the intent-returning thresholds**

Append to `internal/render/threshold.go`:

```go
// ThresholdIntent is ThresholdColor expressed semantically.
func ThresholdIntent(pct float64) Intent {
	switch {
	case pct >= 85:
		return IntentDanger
	case pct >= 70:
		return IntentWarn
	default:
		return IntentOK
	}
}

// ThresholdIntent5 is ThresholdColor5 expressed semantically. The caution step
// is the one pi cannot reproduce exactly: themes expose no orange slot, so the
// pi encoder renders it as a bolded warning.
func ThresholdIntent5(pct float64) Intent {
	switch {
	case pct >= 75:
		return IntentDanger
	case pct >= 60:
		return IntentCaution
	case pct >= 45:
		return IntentWarn
	case pct >= 30:
		return IntentOK
	default:
		return IntentDim
	}
}
```

and rewrite the two existing colour functions as one-liners over them:

```go
func ThresholdColor(pct float64) func(string) string  { return ThresholdIntent(pct).Wrap }
func ThresholdColor5(pct float64) func(string) string { return ThresholdIntent5(pct).Wrap }
```

- [ ] **Step 6: Run the tests**

Run:
```bash
cd /home/joe/Development/agent-statusline && nix shell nixpkgs#go --command go test ./... 2>&1 | tail -15
```

Expected: `ok` for all twelve packages including `internal/e2e`. The golden files must pass untouched — this task changed how colours are produced but not which bytes come out.

- [ ] **Step 7: Prove the goldens really are untouched**

Run:
```bash
cd /home/joe/Development/agent-statusline && git status --porcelain internal/e2e/testdata/
```

Expected: no output. Any modified `.golden` means Step 4 or 5 changed a byte; fix the code, never the golden.

- [ ] **Step 8: Commit**

```bash
cd /home/joe/Development/agent-statusline
nix shell nixpkgs#go --command gofmt -w internal/render
git add -A
git commit -m "feat(render): introduce semantic spans, with ANSI as one encoding

Colour becomes an intent that widgets declare rather than an SGR code they
emit. The Go encoder reproduces today's bytes exactly — the untouched golden
files are the proof — and a second encoder in the pi extension will map the
same intents onto pi theme tokens. path and warn share SGR 33 here because
Claude Code's palette has no separate colour for a directory; pi splits them."
```

---

### Task 2: Convert the text-only widgets to spans

Eleven widgets whose output is plain coloured text. Each gains `RenderSpans`; `Render` becomes a one-line delegation. Existing widget tests assert on strings and stay untouched, which is exactly what makes this safe.

**Files:**
- Modify: `internal/widgets/widget.go` (add `SpanRenderer` and `SafeRenderSpans`)
- Modify: `internal/widgets/model.go`, `cwd.go`, `git.go`, `duration.go`, `tokens.go`, `voice.go`, `compaction.go`, `pr.go`, `cost.go`, `effort.go`, `session_name.go`
- Create: `internal/widgets/spans_test.go`

**Interfaces:**
- Consumes: `render.Spans`, `render.Text`, `render.Link`, `render.Intent*` from Task 1
- Produces:
  - `type widgets.SpanRenderer interface { RenderSpans(ctx *Context) (render.Spans, bool) }`
  - `func widgets.SafeRenderSpans(w Widget, ctx *Context) (render.Spans, bool)` — panic-safe; for a widget that does not implement `SpanRenderer`, returns a single `{kind:"text", intent:"text"}` span holding the raw ANSI

- [ ] **Step 1: Write the failing test**

Create `internal/widgets/spans_test.go`:

```go
package widgets

import (
	"testing"
	"time"

	"github.com/joegoldin/agent-statusline/internal/config"
	"github.com/joegoldin/agent-statusline/internal/gitcache"
	"github.com/joegoldin/agent-statusline/internal/input"
	"github.com/joegoldin/agent-statusline/internal/render"
	"github.com/joegoldin/agent-statusline/internal/voice"
)

// everySpanWidget lists the widgets converted so far. A widget lands here the
// moment it implements SpanRenderer, and the round-trip below keeps the two
// code paths honest.
func everySpanWidget() []Widget {
	return []Widget{
		Model{}, CWD{}, Git{}, Duration{}, Tokens{}, Voice{},
		Compaction{}, PR{}, Cost{}, Effort{}, SessionName{},
	}
}

func TestSpansRoundTripToRenderOutput(t *testing.T) {
	ctx := fixtureContext(t)
	for _, w := range everySpanWidget() {
		text, visible := SafeRender(w, ctx)
		spans, spanVisible := SafeRenderSpans(w, ctx)
		if visible != spanVisible {
			t.Errorf("%s: Render visible=%v, RenderSpans visible=%v", w.Name(), visible, spanVisible)
			continue
		}
		if got := spans.ANSI(); got != text {
			t.Errorf("%s: spans.ANSI() = %q, Render() = %q", w.Name(), got, text)
		}
	}
}

func TestSpansCarryNoRawEscapes(t *testing.T) {
	ctx := fixtureContext(t)
	for _, w := range everySpanWidget() {
		spans, visible := SafeRenderSpans(w, ctx)
		if !visible {
			continue
		}
		for _, s := range spans {
			for _, r := range s.Text {
				if r == 0x1b {
					t.Errorf("%s: span text contains a raw escape: %q", w.Name(), s.Text)
					break
				}
			}
			if s.Kind == "text" && s.Intent == "" {
				t.Errorf("%s: text span %q has no intent", w.Name(), s.Text)
			}
		}
	}
}

type legacyOnlyWidget struct{}

func (legacyOnlyWidget) Name() string                   { return "legacy" }
func (legacyOnlyWidget) Render(*Context) (string, bool) { return "legacy", true }

func TestSafeRenderSpansFallsBackForNonSpanWidget(t *testing.T) {
	spans, visible := SafeRenderSpans(legacyOnlyWidget{}, fixtureContext(t))
	if !visible {
		t.Fatal("fallback widget reported invisible")
	}
	if len(spans) != 1 || spans[0].Intent != render.IntentText || spans[0].Text != "legacy" {
		t.Errorf("fallback spans = %+v, want one text-intent span holding the raw output", spans)
	}
}

// fixtureContext makes every widget in everySpanWidget() visible at once, so
// the round-trip covers real output rather than eleven hidden widgets.
func fixtureContext(t *testing.T) *Context {
	t.Helper()
	used := 53.5
	return &Context{
		Mode: input.ModePi,
		Cfg:  config.Defaults(),
		Now:  time.Unix(1748260800, 0).UTC(),
		Status: input.Status{
			CWD:         "/home/joe/Development/agent-statusline",
			SessionName: "native-pi",
			Model:       input.Model{ID: "gpt-5.6-sol", DisplayName: "Sol"},
			Effort:      &input.Effort{Level: "xhigh"},
			Cost:        &input.Cost{TotalCostUSD: 4.20, TotalDurationMS: 4_530_000},
			PR:          &input.PR{Number: 12, URL: "https://example.test/pr/12", ReviewState: "approved"},
			ContextWindow: &input.ContextWindow{
				ContextWindowSize: 400_000,
				UsedPercentage:    &used,
				TotalInputTokens:  214_000,
			},
		},
		GitProvider:        func() *gitcache.Git { return &gitcache.Git{Branch: "main", Dirty: true, Ahead: 2, Behind: 1} },
		VoiceProvider:      func() *voice.Config { return &voice.Config{Enabled: true, Mode: "dictate"} },
		CompactionProvider: func() int { return 3 },
	}
}
```

Reconcile the struct literals against the real field names before running — `voice.Config` in particular. Run `nix shell nixpkgs#go --command go doc ./internal/voice Config` if unsure.

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
cd /home/joe/Development/agent-statusline && nix shell nixpkgs#go --command go test ./internal/widgets/ -run TestSpans -v 2>&1 | tail -20
```

Expected: FAIL to compile — `undefined: SafeRenderSpans`.

- [ ] **Step 3: Add the SpanRenderer seam**

Append to `internal/widgets/widget.go` (and add the `render` import):

```go
// SpanRenderer is the semantic half of a widget: the same content Render
// produces, but as intents rather than escape codes. Every widget implements
// it; the interface stays optional so a future widget can be added ANSI-first
// and converted later without breaking the emitter.
type SpanRenderer interface {
	RenderSpans(ctx *Context) (render.Spans, bool)
}

// SafeRenderSpans is SafeRender's span twin. A widget that does not implement
// SpanRenderer degrades to a single text-intent span holding its raw output:
// pi then renders it in the theme's default foreground, losing colour but
// never losing the widget.
func SafeRenderSpans(w Widget, ctx *Context) (spans render.Spans, visible bool) {
	defer func() {
		if r := recover(); r != nil {
			spans, visible = nil, false
		}
	}()
	if sr, ok := w.(SpanRenderer); ok {
		return sr.RenderSpans(ctx)
	}
	text, vis := w.Render(ctx)
	if !vis || text == "" {
		return nil, false
	}
	return render.Spans{render.Text(render.IntentText, text)}, true
}
```

- [ ] **Step 4: Convert the eleven widgets**

The mechanical shape, using `session_name.go` as the template:

```go
func (SessionName) Render(ctx *Context) (string, bool) {
	spans, ok := SessionName{}.RenderSpans(ctx)
	return spans.ANSI(), ok
}

func (SessionName) RenderSpans(ctx *Context) (render.Spans, bool) {
	name := ctx.Status.SessionName
	if name == "" {
		return nil, false
	}
	return render.Spans{render.Text(render.IntentDim, sessionNameGlyph+name)}, true
}
```

Apply the same transformation to each, with these intent assignments — chosen so `spans.ANSI()` reproduces today's bytes exactly:

| widget | spans |
|---|---|
| `model` | one `IntentAccent` span (glyph, name, inline effort), replacing `render.Cyan` |
| `cwd` | one **`IntentPath`** span, replacing `render.Yellow` — same SGR 33, different meaning |
| `git` | `IntentOK` branch label; then for each of ahead / behind / worktree an `IntentText` `" "` span followed by an `IntentDim` span. Do **not** emit one pre-joined string: the separators must be their own spans or pi loses the colour boundaries. |
| `duration` | one `IntentDim` span |
| `tokens` | one span whose intent is `render.ThresholdIntent5(pct)` |
| `voice` | one `IntentMeta` span |
| `compaction` | one `IntentDim` span |
| `pr` | `render.Link(render.IntentAccent, p.URL, text)`; when `p.URL == ""`, `render.Text(render.IntentAccent, text)` |
| `cost` | one `IntentDanger` span |
| `effort` | one `IntentMeta` span |
| `sessionName` | one `IntentDim` span |

`git.go` is the only non-trivial one:

```go
func (Git) RenderSpans(ctx *Context) (render.Spans, bool) {
	g := ctx.Git()
	if g == nil {
		return nil, false
	}
	var label string
	switch {
	case g.Detached && g.SHA != "":
		label = g.SHA
		if len(label) > 7 {
			label = label[:7]
		}
	case g.Branch != "":
		label = g.Branch
	default:
		return nil, false
	}
	if g.Dirty {
		label += "*"
	}
	spans := render.Spans{render.Text(render.IntentOK, gitGlyph+label)}
	add := func(s string) {
		spans = append(spans,
			render.Text(render.IntentText, " "),
			render.Text(render.IntentDim, s))
	}
	if g.Ahead > 0 {
		add(fmt.Sprintf("↑%d", g.Ahead))
	}
	if g.Behind > 0 {
		add(fmt.Sprintf("↓%d", g.Behind))
	}
	if wt := ctx.Status.Workspace.GitWorktree; wt != "" {
		add("[" + worktreeGlyph + wt + "]")
	}
	return spans, true
}
```

Keep the exact glyph literals already in `git.go` rather than the escapes shown above — copy them out of the current source so no byte changes. `strings.Join(parts, " ")` in the old body produced exactly the same bytes as this interleaving, which is what `TestSpansRoundTripToRenderOutput` verifies.

- [ ] **Step 5: Run the widget tests**

Run:
```bash
cd /home/joe/Development/agent-statusline && nix shell nixpkgs#go --command go test ./internal/widgets/ 2>&1 | tail -20
```

Expected: `ok`. Every pre-existing per-widget test still asserts on strings and must pass unchanged — that is the signal the conversion was lossless.

- [ ] **Step 6: Run the full suite and re-check the goldens**

Run:
```bash
cd /home/joe/Development/agent-statusline && nix shell nixpkgs#go --command go test ./... 2>&1 | tail -15 && git status --porcelain internal/e2e/testdata/
```

Expected: all `ok`, and `git status` prints nothing.

- [ ] **Step 7: Commit**

```bash
cd /home/joe/Development/agent-statusline
nix shell nixpkgs#go --command gofmt -w internal/widgets
git add -A
git commit -m "refactor(widgets): text widgets render spans, ANSI derives from them

Eleven widgets now declare intents; Render is a one-line delegation through
spans.ANSI(). The pre-existing string-asserting tests are untouched and still
pass, and the golden files did not move — together that is the proof the
conversion is byte-lossless. cwd moves to the new path intent, which shares
SGR 33 with warn under Claude Code and diverges under pi."
```

---
### Task 3: Convert the bar and threshold widgets

`context`, `usage5h`, `usage7d` and `burnRate` are the widgets whose output is width-sensitive (they have compact forms) and whose colour is threshold-derived. They also own the only bar spans.

**Files:**
- Modify: `internal/widgets/context_bar.go`, `usage.go`, `burn.go`
- Modify: `internal/widgets/spans_test.go` (extend `everySpanWidget`, add compact coverage)

**Interfaces:**
- Consumes: `render.Bar`, `render.BarBraille/BarBlock/BarLine`, `render.ThresholdIntent`, `render.ThresholdIntent5` from Task 1; `SpanRenderer` from Task 2
- Produces: no new API — four more `SpanRenderer` implementations. `ctx.Compact()` remains the only width input, which Task 5 exploits by rendering each widget twice.

- [ ] **Step 1: Extend the failing test**

In `internal/widgets/spans_test.go`, add the four widgets to `everySpanWidget()`:

```go
		ContextBar{}, Usage5h{}, Usage7d{}, BurnRate{},
```

Add rate limits and a transcript to `fixtureContext` so they are visible. Inside its `input.Status`:

```go
			RateLimits: &input.RateLimits{
				FiveHour: &input.Window{UsedPercentage: 62, ResetsAt: 1748260800 + 2*3600},
				SevenDay: &input.Window{UsedPercentage: 71, ResetsAt: 1748260800 + 3*24*3600},
			},
```

and alongside the other providers:

```go
		TranscriptProvider: func() *transcript.Entries {
			base := time.Unix(1748260800, 0).UTC()
			return &transcript.Entries{Requests: []transcript.Request{
				{Timestamp: base.Add(-120 * time.Second), InputTokens: 40_000},
				{Timestamp: base.Add(-30 * time.Second), InputTokens: 60_000},
			}}
		},
```

Then append:

```go
func TestSpansRoundTripInCompactMode(t *testing.T) {
	ctx := fixtureContext(t)
	ctx.Width = 40 // below DefaultCompactWidth, so Compact() is true
	for _, w := range everySpanWidget() {
		text, visible := SafeRender(w, ctx)
		spans, spanVisible := SafeRenderSpans(w, ctx)
		if visible != spanVisible {
			t.Errorf("%s (compact): visible mismatch %v vs %v", w.Name(), visible, spanVisible)
			continue
		}
		if got := spans.ANSI(); got != text {
			t.Errorf("%s (compact): spans.ANSI() = %q, Render() = %q", w.Name(), got, text)
		}
	}
}

func TestContextBarEmitsAFillFractionNotAPercentage(t *testing.T) {
	ctx := fixtureContext(t)
	spans, ok := SafeRenderSpans(ContextBar{}, ctx)
	if !ok {
		t.Fatal("context widget hidden")
	}
	var bars int
	for _, s := range spans {
		if s.Kind != "bar" {
			continue
		}
		bars++
		if s.Fill < 0.534 || s.Fill > 0.536 {
			t.Errorf("bar fill = %v, want ~0.535 (a fraction, not 53.5)", s.Fill)
		}
		if s.Cells != ctx.Cfg.BarWidth {
			t.Errorf("bar cells = %d, want %d", s.Cells, ctx.Cfg.BarWidth)
		}
		if s.Style != render.BarBraille {
			t.Errorf("bar style = %q, want %q", s.Style, render.BarBraille)
		}
	}
	if bars != 1 {
		t.Errorf("got %d bar spans, want exactly 1", bars)
	}
}

func TestCompactContextDropsTheBar(t *testing.T) {
	ctx := fixtureContext(t)
	ctx.Width = 40
	spans, _ := SafeRenderSpans(ContextBar{}, ctx)
	for _, s := range spans {
		if s.Kind == "bar" {
			t.Fatal("compact context still emits a bar span")
		}
	}
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
cd /home/joe/Development/agent-statusline && nix shell nixpkgs#go --command go test ./internal/widgets/ -run TestSpans -v 2>&1 | tail -25
```

Expected: FAIL — `TestSpansRoundTripToRenderOutput` reports the four new widgets returning a single `text`-intent span containing raw escapes (the Task 2 fallback), and `TestContextBarEmits...` reports 0 bar spans.

- [ ] **Step 3: Convert `context_bar.go`**

```go
func (ContextBar) Render(ctx *Context) (string, bool) {
	spans, ok := ContextBar{}.RenderSpans(ctx)
	return spans.ANSI(), ok
}

func (ContextBar) RenderSpans(ctx *Context) (render.Spans, bool) {
	pct, ok := contextPercent(ctx.Status)
	if !ok {
		return nil, false
	}
	intent := render.ThresholdIntent5(pct)
	pctText := fmt.Sprintf("%d%%", int(pct+0.5))
	if ctx.Compact() {
		return render.Spans{
			render.Text(intent, contextGlyph),
			render.Text(render.IntentText, " "),
			render.Text(intent, pctText),
		}, true
	}
	width := ctx.Cfg.BarWidth
	if width <= 0 {
		width = 10
	}
	// The bar paints a smooth per-cell ramp; the glyph and percent use the
	// step palette so the alarm signal stays sharp. Only the fraction crosses
	// the wire — the pi renderer re-derives the ramp from the active theme.
	return render.Spans{
		render.Text(intent, contextGlyph),
		render.Bar(pct/100, width, render.BarBraille),
		render.Text(render.IntentText, " "),
		render.Text(intent, pctText),
	}, true
}
```

- [ ] **Step 4: Convert `usage.go`**

```go
func (Usage5h) Render(ctx *Context) (string, bool) {
	spans, ok := Usage5h{}.RenderSpans(ctx)
	return spans.ANSI(), ok
}

func (Usage5h) RenderSpans(ctx *Context) (render.Spans, bool) {
	if ctx.Status.RateLimits == nil || ctx.Status.RateLimits.FiveHour == nil {
		return nil, false
	}
	return usageWindowSpans(ctx, "5h", ctx.Status.RateLimits.FiveHour, 5*time.Hour, render.BarBlock), true
}

func (Usage7d) Render(ctx *Context) (string, bool) {
	spans, ok := Usage7d{}.RenderSpans(ctx)
	return spans.ANSI(), ok
}

func (Usage7d) RenderSpans(ctx *Context) (render.Spans, bool) {
	if ctx.Status.RateLimits == nil || ctx.Status.RateLimits.SevenDay == nil {
		return nil, false
	}
	w := ctx.Status.RateLimits.SevenDay
	if threshold := float64(ctx.Cfg.SevenDayThreshold); threshold > 0 && w.UsedPercentage < threshold {
		return nil, false
	}
	return usageWindowSpans(ctx, "7d", w, 7*24*time.Hour, render.BarLine), true
}

// usageWindowSpans mirrors the old renderUsageWindow exactly, one fmt segment
// at a time. The single Sprintf is decomposed because each piece carries a
// different intent: the label is plain, the percentage is threshold-coloured,
// the countdown is metadata, the pace arrow is a judgement.
func usageWindowSpans(ctx *Context, label string, w *input.Window, total time.Duration, style string) render.Spans {
	intent := render.ThresholdIntent(w.UsedPercentage)
	spans := render.Spans{render.Text(render.IntentText, usageGlyph+label+" ")}
	if !ctx.Compact() {
		width := ctx.Cfg.BarWidth
		if width <= 0 {
			width = 10
		}
		spans = append(spans,
			render.Bar(w.UsedPercentage/100, width, style),
			render.Text(render.IntentText, " "))
	}
	spans = append(spans,
		render.Text(intent, fmt.Sprintf("%d%%", int(w.UsedPercentage+0.5))),
		render.Text(render.IntentText, " ("),
		render.Text(render.IntentDim, formatCountdown(ctx.Now, time.Unix(w.ResetsAt, 0))),
		render.Text(render.IntentText, ")"))
	if pace, paceIntent, ok := paceSpan(ctx.Now, time.Unix(w.ResetsAt, 0), total, w.UsedPercentage); ok {
		spans = append(spans,
			render.Text(render.IntentText, " "),
			render.Text(paceIntent, pace))
	}
	return spans
}

// paceSpan is formatPace split into its text and its intent.
func paceSpan(now, reset time.Time, total time.Duration, usedPct float64) (string, render.Intent, bool) {
	if total <= 0 {
		return "", "", false
	}
	elapsed := total - reset.Sub(now)
	if elapsed <= 0 || elapsed > total {
		return "", "", false
	}
	delta := usedPct - float64(elapsed)/float64(total)*100
	if delta > 2 {
		return fmt.Sprintf("%s%d%%", paceOverGlyph, int(delta+0.5)), render.IntentDanger, true
	}
	if delta < -2 {
		return fmt.Sprintf("%s%d%%", paceUnderGlyph, int(-delta+0.5)), render.IntentOK, true
	}
	return "", "", false
}
```

Copy the two pace arrow glyphs verbatim out of the current `formatPace` (declaring them as `paceOverGlyph` / `paceUnderGlyph` consts, or inlining them) — do not retype them. Delete `renderUsageWindow`; before deleting `formatPace`, run `grep -n 'formatPace\|renderUsageWindow' internal/widgets/usage_test.go` and keep whichever the tests still reference as a thin wrapper. `formatCountdown` is unchanged.

The `(` and `)` are now their own `IntentText` spans rather than baked into a `Sprintf`. `spans.ANSI()` still concatenates to the identical byte sequence, because `render.Dim(countdown)` was already a separately-wrapped run inside that Sprintf.

- [ ] **Step 5: Convert `burn.go`**

```go
func (BurnRate) Render(ctx *Context) (string, bool) {
	spans, ok := BurnRate{}.RenderSpans(ctx)
	return spans.ANSI(), ok
}

func (BurnRate) RenderSpans(ctx *Context) (render.Spans, bool) {
	entries := ctx.Transcript()
	if entries == nil || len(entries.Requests) == 0 {
		return nil, false
	}
	size, ok := contextWindowSize(ctx.Status)
	if !ok || size <= 0 {
		return nil, false
	}
	tau := time.Duration(ctx.Cfg.TranscriptWindowSeconds) * time.Second
	if tau <= 0 {
		tau = 60 * time.Second
	}
	tps := transcript.TokensPerSecondEMA(entries.Requests, burnNow(ctx.Now), tau)
	if tps <= 0 {
		return nil, false
	}
	pctPerMin := tps * 60 / float64(size) * 100
	if pctPerMin < 0.01 {
		return nil, false
	}
	spans := render.Spans{
		render.Text(render.IntentMeta, fmt.Sprintf("%s %s", burnGlyph, formatRate(pctPerMin))),
	}
	if ctx.Compact() {
		return spans, true
	}
	pct, _ := contextPercent(ctx.Status)
	eta := etaToFull(size, pct, tps)
	const etaCap = 24 * time.Hour
	if eta <= 0 || eta > etaCap {
		return spans, true
	}
	etaIntent := render.IntentDim
	if eta < 15*time.Minute {
		etaIntent = render.IntentDanger
	}
	return append(spans,
		render.Text(render.IntentText, " "),
		render.Text(etaIntent, "ETA "+formatDuration(eta))), true
}
```

- [ ] **Step 6: Run the tests**

Run:
```bash
cd /home/joe/Development/agent-statusline && nix shell nixpkgs#go --command go test ./... 2>&1 | tail -15 && git status --porcelain internal/e2e/testdata/
```

Expected: all `ok`, `git status` silent. `TestSpansRoundTripInCompactMode` passing is the assurance that the compact forms — which Task 5 ships as a second span list — really are today's compact forms.

- [ ] **Step 7: Commit**

```bash
cd /home/joe/Development/agent-statusline
nix shell nixpkgs#go --command gofmt -w internal/widgets
git add -A
git commit -m "refactor(widgets): bar and threshold widgets render spans

Bars cross the wire as a fill fraction plus a style name, never as glyphs or
colours, so the pi renderer can re-derive the ramp from the active theme.
Threshold colours become ThresholdIntent/ThresholdIntent5. Compact forms get
their own round-trip test because the emitter renders each widget twice —
once wide, once narrow — and ships both."
```

---

### Task 4: Structured activity snapshot

The activity stack cannot be spans. `Tools` budgets per-tool truncation against the terminal width, `runningGlyph` animates against wall-clock seconds, and every elapsed counter must keep climbing between binary invocations. All three are properties the renderer owns, not the data source. So the activity section carries **items with absolute timestamps** plus the grace-window constants, and the renderer does the sorting, capping, truncation, spinner and elapsed maths locally.

**Files:**
- Create: `internal/widgets/activity_snapshot.go`
- Create: `internal/widgets/activity_snapshot_test.go`

**Interfaces:**
- Consumes: `transcript.Entries`, `toolclock.Entry`, `Context.Transcript()`, `Context.ToolTiming()`, `foldMCPCounts`, and the four grace constants from phase 1
- Produces:
  - `type widgets.ActivityItem struct` — `{ID, Name, Target, State string; EmittedAtMs, StartedAtMs, EndedAtMs int64}`
  - `type widgets.ToolCountItem struct` — `{Name string; Count int}`
  - `type widgets.AgentItem struct` — `{Name, Model, Description string; StartedAtMs, EndedAtMs int64}`
  - `type widgets.TodoItem struct` — `{Subject string; Done, Total int; AllComplete bool; TimestampMs int64}`
  - `type widgets.ActivityGraces struct` — `{ToolCompleteMs, AgentCompleteMs, AgentRunningStaleMs, TodoCompleteMs int64}`
  - `type widgets.ActivitySnapshot struct` — `{Graces; Tools; ToolCounts; Agents; Todos}`
  - `func widgets.BuildActivitySnapshot(ctx *Context) ActivitySnapshot`

Note: `transcript.TodoItem` already exists with different fields. Name the new one `widgets.TodoItem` and keep it in the `widgets` package; there is no collision because they live in different packages.

- [ ] **Step 1: Write the failing test**

Create `internal/widgets/activity_snapshot_test.go`:

```go
package widgets

import (
	"testing"
	"time"

	"github.com/joegoldin/agent-statusline/internal/toolclock"
	"github.com/joegoldin/agent-statusline/internal/transcript"
)

func activityCtx(now time.Time, e *transcript.Entries, timing map[string]toolclock.Entry) *Context {
	return &Context{
		Now:                now,
		TranscriptProvider: func() *transcript.Entries { return e },
		ToolTimingProvider: func() map[string]toolclock.Entry { return timing },
	}
}

func TestActivitySnapshotEmitsAbsoluteTimestampsNotElapsed(t *testing.T) {
	now := time.Unix(1748260800, 0).UTC()
	started := now.Add(-42 * time.Second)
	snap := BuildActivitySnapshot(activityCtx(now,
		&transcript.Entries{Tools: []transcript.Tool{{ID: "c1", Name: "bash", Target: "bun test", Timestamp: started}}},
		map[string]toolclock.Entry{"c1": {StartedAt: started, Name: "bash", Target: "bun test"}},
	))
	if len(snap.Tools) != 1 {
		t.Fatalf("got %d tools, want 1", len(snap.Tools))
	}
	got := snap.Tools[0]
	if got.StartedAtMs != started.UnixMilli() {
		t.Errorf("StartedAtMs = %d, want %d", got.StartedAtMs, started.UnixMilli())
	}
	if got.EndedAtMs != 0 {
		t.Errorf("EndedAtMs = %d, want 0 while running", got.EndedAtMs)
	}
	if got.State != "running" {
		t.Errorf("State = %q, want running", got.State)
	}
	if got.Target != "bun test" {
		t.Errorf("Target = %q", got.Target)
	}
}

func TestActivitySnapshotMarksQueuedToolsWaiting(t *testing.T) {
	now := time.Unix(1748260800, 0).UTC()
	live := now.Add(-10 * time.Second)
	snap := BuildActivitySnapshot(activityCtx(now,
		&transcript.Entries{Tools: []transcript.Tool{
			{ID: "running", Name: "bash", Timestamp: live},
			{ID: "queued", Name: "read", Timestamp: now.Add(-3 * time.Second)},
		}},
		map[string]toolclock.Entry{"running": {StartedAt: live, Name: "bash"}},
	))
	states := map[string]string{}
	for _, it := range snap.Tools {
		states[it.ID] = it.State
	}
	if states["running"] != "running" || states["queued"] != "waiting" {
		t.Errorf("states = %v, want running/waiting", states)
	}
}

func TestActivitySnapshotDoesNotApplyGraceWindows(t *testing.T) {
	// Grace filtering belongs to the renderer, which re-evaluates it every
	// second against its own clock. If the Go side filtered here, a finished
	// tool would sit on screen until the next binary invocation.
	now := time.Unix(1748260800, 0).UTC()
	old := now.Add(-10 * time.Minute)
	snap := BuildActivitySnapshot(activityCtx(now,
		&transcript.Entries{RecentTools: []transcript.Tool{{ID: "c1", Name: "read", Timestamp: old, EndedAt: old}}},
		nil,
	))
	if len(snap.Tools) != 1 {
		t.Fatalf("a long-finished tool was filtered out; got %d items", len(snap.Tools))
	}
	if snap.Tools[0].State != "done" {
		t.Errorf("State = %q, want done", snap.Tools[0].State)
	}
	if snap.Graces.ToolCompleteMs != int64(toolCompleteGrace/time.Millisecond) {
		t.Errorf("ToolCompleteMs = %d, want %d", snap.Graces.ToolCompleteMs, toolCompleteGrace/time.Millisecond)
	}
	if snap.Graces.AgentRunningStaleMs != int64(agentRunningStale/time.Millisecond) {
		t.Errorf("AgentRunningStaleMs = %d", snap.Graces.AgentRunningStaleMs)
	}
}

func TestActivitySnapshotIsWidthIndependent(t *testing.T) {
	now := time.Unix(1748260800, 0).UTC()
	e := &transcript.Entries{Tools: []transcript.Tool{
		{ID: "a", Name: "bash", Target: "one", Timestamp: now},
		{ID: "b", Name: "bash", Target: "two", Timestamp: now},
		{ID: "c", Name: "bash", Target: "three", Timestamp: now},
		{ID: "d", Name: "bash", Target: "four", Timestamp: now},
	}}
	narrow := activityCtx(now, e, nil)
	narrow.Width = 40
	wide := activityCtx(now, e, nil)
	wide.Width = 200
	if len(BuildActivitySnapshot(narrow).Tools) != len(BuildActivitySnapshot(wide).Tools) {
		t.Error("snapshot tool count varies with Width; capping belongs to the renderer")
	}
	for _, it := range BuildActivitySnapshot(narrow).Tools {
		if it.Target == "" {
			t.Error("target was truncated away in the snapshot")
		}
	}
}

func TestActivitySnapshotFoldsMCPCounts(t *testing.T) {
	now := time.Unix(1748260800, 0).UTC()
	snap := BuildActivitySnapshot(activityCtx(now, &transcript.Entries{ToolCounts: []transcript.ToolCount{
		{Name: "read", Count: 3},
		{Name: "mcp__nixos__nix", Count: 4},
		{Name: "mcp__other__thing", Count: 1},
	}}, nil))
	got := map[string]int{}
	for _, c := range snap.ToolCounts {
		got[c.Name] = c.Count
	}
	if got["MCP"] != 5 || got["read"] != 3 || len(got) != 2 {
		t.Errorf("ToolCounts = %v, want read=3 MCP=5", got)
	}
}

func TestActivitySnapshotSurvivesNilTranscript(t *testing.T) {
	snap := BuildActivitySnapshot(&Context{Now: time.Unix(1748260800, 0).UTC()})
	if snap.Graces.TodoCompleteMs == 0 {
		t.Error("grace constants must ship even with no activity")
	}
	if len(snap.Tools) != 0 || snap.Todos != nil {
		t.Error("empty snapshot should be empty")
	}
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
cd /home/joe/Development/agent-statusline && nix shell nixpkgs#go --command go test ./internal/widgets/ -run TestActivitySnapshot -v 2>&1 | tail -15
```

Expected: FAIL to compile — `undefined: BuildActivitySnapshot`.

- [ ] **Step 3: Implement `internal/widgets/activity_snapshot.go`**

```go
package widgets

import (
	"sort"
	"time"

	"github.com/joegoldin/agent-statusline/internal/transcript"
)

// ActivitySnapshot is the activity stack in structured form, for renderers
// that own their own layout and their own clock.
//
// Three things are deliberately NOT done here, because all three belong to the
// renderer and doing them in Go would freeze them between invocations:
//
//  1. no elapsed durations — only absolute epoch-millisecond timestamps, so a
//     1 Hz repaint keeps the counters climbing without respawning anything;
//  2. no grace-window filtering — the constants ship in Graces and the
//     renderer applies them against its own now, so a finished tool drops off
//     on time rather than at the next invocation;
//  3. no capping or truncation — those depend on the terminal width, which
//     only the renderer knows.
type ActivitySnapshot struct {
	Graces     ActivityGraces  `json:"graces"`
	Tools      []ActivityItem  `json:"tools"`
	ToolCounts []ToolCountItem `json:"toolCounts"`
	Agents     []AgentItem     `json:"agents"`
	Todos      *TodoItem       `json:"todos"`
}

// ActivityGraces are the linger/staleness windows, in milliseconds, that the
// renderer applies. They live in the snapshot rather than in the renderer so
// there is one definition of "how long a finished tool lingers".
type ActivityGraces struct {
	ToolCompleteMs      int64 `json:"toolCompleteMs"`
	AgentCompleteMs     int64 `json:"agentCompleteMs"`
	AgentRunningStaleMs int64 `json:"agentRunningStaleMs"`
	TodoCompleteMs      int64 `json:"todoCompleteMs"`
}

// ActivityItem is one tool call. State is running, waiting or done — the
// distinction the sidecar makes and the transcript alone cannot.
type ActivityItem struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Target      string `json:"target,omitempty"`
	State       string `json:"state"`
	EmittedAtMs int64  `json:"emittedAtMs,omitempty"`
	StartedAtMs int64  `json:"startedAtMs,omitempty"`
	EndedAtMs   int64  `json:"endedAtMs,omitempty"`
}

type ToolCountItem struct {
	Name  string `json:"name"`
	Count int    `json:"count"`
}

type AgentItem struct {
	Name        string `json:"name"`
	Model       string `json:"model,omitempty"`
	Description string `json:"description,omitempty"`
	StartedAtMs int64  `json:"startedAtMs"`
	EndedAtMs   int64  `json:"endedAtMs,omitempty"`
}

type TodoItem struct {
	Subject     string `json:"subject,omitempty"`
	Done        int    `json:"done"`
	Total       int    `json:"total"`
	AllComplete bool   `json:"allComplete"`
	TimestampMs int64  `json:"timestampMs,omitempty"`
}

func epochMs(t time.Time) int64 {
	if t.IsZero() {
		return 0
	}
	return t.UnixMilli()
}

func firstNonZero(vs ...int64) int64 {
	for _, v := range vs {
		if v != 0 {
			return v
		}
	}
	return 0
}

// BuildActivitySnapshot projects the transcript plus the timing sidecar into
// the structured form. It never panics: a nil transcript yields an empty
// snapshot that still carries the grace constants.
func BuildActivitySnapshot(ctx *Context) ActivitySnapshot {
	snap := ActivitySnapshot{Graces: ActivityGraces{
		ToolCompleteMs:      int64(toolCompleteGrace / time.Millisecond),
		AgentCompleteMs:     int64(agentCompleteGrace / time.Millisecond),
		AgentRunningStaleMs: int64(agentRunningStale / time.Millisecond),
		TodoCompleteMs:      int64(todoCompleteGrace / time.Millisecond),
	}}
	entries := ctx.Transcript()
	if entries == nil {
		return snap
	}
	timing := ctx.ToolTiming()

	// Live-runner scoping is identical to Tools.Render: a tool with no
	// recorded start is only waiting if something else is genuinely running,
	// so a missed hook never strands a tool as a perpetual hourglass.
	liveRunner := false
	for _, t := range entries.Tools {
		if e, ok := timing[t.ID]; ok && !e.StartedAt.IsZero() && e.EndedAt.IsZero() {
			liveRunner = true
			break
		}
	}
	for _, t := range entries.Tools {
		e := timing[t.ID]
		state := "running"
		if e.StartedAt.IsZero() && liveRunner {
			state = "waiting"
		}
		snap.Tools = append(snap.Tools, ActivityItem{
			ID: t.ID, Name: t.Name, Target: t.Target, State: state,
			EmittedAtMs: epochMs(t.Timestamp), StartedAtMs: epochMs(e.StartedAt),
		})
	}
	for _, t := range entries.RecentTools {
		e := timing[t.ID]
		snap.Tools = append(snap.Tools, ActivityItem{
			ID: t.ID, Name: t.Name, Target: t.Target, State: "done",
			EmittedAtMs: epochMs(t.Timestamp), StartedAtMs: epochMs(e.StartedAt),
			EndedAtMs: firstNonZero(epochMs(e.EndedAt), epochMs(t.EndedAt)),
		})
	}

	for _, c := range foldMCPCounts(entries.ToolCounts) {
		snap.ToolCounts = append(snap.ToolCounts, ToolCountItem{Name: c.Name, Count: c.Count})
	}
	sort.SliceStable(snap.ToolCounts, func(i, j int) bool {
		if snap.ToolCounts[i].Count != snap.ToolCounts[j].Count {
			return snap.ToolCounts[i].Count > snap.ToolCounts[j].Count
		}
		return snap.ToolCounts[i].Name < snap.ToolCounts[j].Name
	})

	for _, a := range entries.Agents {
		snap.Agents = append(snap.Agents, AgentItem{
			Name: a.Name, Model: a.Model, Description: a.Description,
			StartedAtMs: epochMs(a.StartedAt), EndedAtMs: epochMs(a.EndedAt),
		})
	}
	sort.SliceStable(snap.Agents, func(i, j int) bool {
		return snap.Agents[i].StartedAtMs > snap.Agents[j].StartedAtMs
	})

	if len(entries.Todos) > 0 {
		latest := entries.Todos[len(entries.Todos)-1]
		if len(latest.Todos) > 0 {
			item := TodoItem{Total: len(latest.Todos), TimestampMs: epochMs(latest.Timestamp)}
			for _, td := range latest.Todos {
				if td.Status == "completed" {
					item.Done++
				}
				if td.Status == "in_progress" && item.Subject == "" {
					item.Subject = td.Subject
				}
			}
			item.AllComplete = item.Done == item.Total
			snap.Todos = &item
		}
	}
	return snap
}

var _ = transcript.Entries{} // keep the import honest if the compiler disagrees
```

Delete the trailing `var _` line and any unused import that `gofmt`/`go vet` flags.

- [ ] **Step 4: Run the tests**

Run:
```bash
cd /home/joe/Development/agent-statusline && nix shell nixpkgs#go --command go test ./... 2>&1 | tail -15 && git status --porcelain internal/e2e/testdata/
```

Expected: all `ok`, `git status` silent. `BuildActivitySnapshot` is additive — nothing calls it yet.

- [ ] **Step 5: Commit**

```bash
cd /home/joe/Development/agent-statusline
nix shell nixpkgs#go --command gofmt -w internal/widgets
git add -A
git commit -m "feat(widgets): structured activity snapshot for external renderers

Absolute timestamps instead of elapsed strings, grace constants instead of
grace filtering, and no capping or truncation — all three depend on a clock or
a width the Go process does not own once rendering moves into pi. The existing
Tools/Agents/Todos widgets are untouched and still serve the Claude path."
```

---

### Task 5: `--emit json`

Assemble the snapshot document and add the flag. The Claude path gains nothing but a default-valued flag.

**Files:**
- Create: `internal/emit/emit.go`, `internal/emit/emit_test.go`
- Modify: `cmd/agent-statusline/main.go`, `internal/e2e/golden_test.go`, `internal/layout/layout_test.go`
- Create: `internal/e2e/testdata/pi-full.json.golden` (generated, then reviewed)

**Interfaces:**
- Consumes: `render.Spans` (Task 1), `widgets.SafeRenderSpans` (Task 2), `widgets.BuildActivitySnapshot` (Task 4), `config.Config`, `widgets.Context`, `widgets.Registry`, `widgets.DefaultCompactWidth`, and `dropPriority` from `main.go`
- Produces:
  - `const emit.SchemaVersion = 1`, `const emit.MaxLines = 6`
  - `type emit.Snapshot`, `type emit.SnapshotConfig`, `type emit.WidgetSnapshot`
  - `func emit.Build(ctx *widgets.Context, reg widgets.Registry, dropPriority []string) Snapshot`
  - `func emit.Write(w io.Writer, s Snapshot) error`
  - CLI: `agent-statusline --mode pi --emit json`
  - Every field name below is consumed verbatim by `extension/src/snapshot.ts` in Task 7.

The document, by example:

```json
{
  "schema": 1,
  "mode": "pi",
  "asOfMs": 1748260800000,
  "config": {
    "barWidth": 10,
    "compactWidth": 70,
    "activityRows": 4,
    "hideWhenIdle": true,
    "padding": 0,
    "refreshIntervalMs": 1000,
    "maxLines": 6,
    "separator": " | ",
    "flexName": "flex",
    "row1": ["model", "cwd", "git", "duration", "usage5h", "usage7d"],
    "row2": ["context", "tokens", "burnRate", "voice", "compaction", "pr", "cost"],
    "hide": [],
    "dropPriority": ["sessionName", "compaction", "pr", "voice", "cost", "burnRate", "duration", "tokens", "effort", "context", "usage7d", "usage5h", "git", "cwd", "model"]
  },
  "widgets": {
    "context": {
      "visible": true,
      "spans": [
        { "kind": "text", "text": "<glyph>", "intent": "warn" },
        { "kind": "bar", "fill": 0.535, "cells": 10, "style": "braille" },
        { "kind": "text", "text": " ", "intent": "text" },
        { "kind": "text", "text": "54%", "intent": "warn" }
      ],
      "compact": [
        { "kind": "text", "text": "<glyph>", "intent": "warn" },
        { "kind": "text", "text": " ", "intent": "text" },
        { "kind": "text", "text": "54%", "intent": "warn" }
      ]
    },
    "cost": { "visible": false }
  },
  "activity": {
    "graces": { "toolCompleteMs": 30000, "agentCompleteMs": 30000, "agentRunningStaleMs": 1800000, "todoCompleteMs": 60000 },
    "tools": [
      { "id": "call-1", "name": "bash", "target": "bun test", "state": "running", "emittedAtMs": 1748260789000, "startedAtMs": 1748260790000 }
    ],
    "toolCounts": [{ "name": "read", "count": 3 }],
    "agents": [],
    "todos": null
  }
}
```

`separator` is the real `layout.Separator`, not the ASCII pipe shown here. `compact` is present only when it differs from `spans`. Widget keys are a Go map, so `encoding/json` sorts them and the golden is stable.

- [ ] **Step 1: Write the failing test**

Create `internal/emit/emit_test.go`:

```go
package emit

import (
	"bytes"
	"encoding/json"
	"testing"
	"time"

	"github.com/joegoldin/agent-statusline/internal/config"
	"github.com/joegoldin/agent-statusline/internal/input"
	"github.com/joegoldin/agent-statusline/internal/render"
	"github.com/joegoldin/agent-statusline/internal/widgets"
)

func testCtx() *widgets.Context {
	used := 53.5
	return &widgets.Context{
		Mode: input.ModePi,
		Cfg:  config.Defaults(),
		Now:  time.Unix(1748260800, 0).UTC(),
		Status: input.Status{
			CWD:   "/home/joe/p",
			Model: input.Model{ID: "gpt-5.6-sol", DisplayName: "Sol"},
			ContextWindow: &input.ContextWindow{
				ContextWindowSize: 400_000,
				UsedPercentage:    &used,
				TotalInputTokens:  214_000,
			},
		},
	}
}

func testRegistry() widgets.Registry {
	r := widgets.Registry{}
	for _, w := range []widgets.Widget{widgets.Model{}, widgets.CWD{}, widgets.ContextBar{}, widgets.Tokens{}, widgets.Cost{}} {
		r[w.Name()] = w
	}
	return r
}

func TestBuildEmitsEveryConfiguredWidgetIncludingHiddenOnes(t *testing.T) {
	s := Build(testCtx(), testRegistry(), []string{"cost", "context", "model"})
	for _, name := range []string{"model", "cwd", "context", "tokens", "cost"} {
		if _, ok := s.Widgets[name]; !ok {
			t.Errorf("widget %q missing from the snapshot", name)
		}
	}
	// A hidden widget is present with visible:false, never absent. The renderer
	// must be able to tell "configured but hidden" from "unknown widget".
	if s.Widgets["cost"].Visible {
		t.Error("cost should be hidden with no cost recorded")
	}
}

func TestBuildCarriesNoTerminalWidth(t *testing.T) {
	ctx := testCtx()
	ctx.Width = 200
	wide, _ := json.Marshal(Build(ctx, testRegistry(), nil).Widgets)
	ctx.Width = 30
	narrow, _ := json.Marshal(Build(ctx, testRegistry(), nil).Widgets)
	if !bytes.Equal(wide, narrow) {
		t.Error("snapshot widgets vary with ctx.Width; the emitter must be width-independent")
	}
}

func TestBuildEmitsCompactOnlyWhenItDiffers(t *testing.T) {
	s := Build(testCtx(), testRegistry(), nil)
	if s.Widgets["context"].Compact == nil {
		t.Error("context has a distinct compact form and must emit it")
	}
	if s.Widgets["model"].Compact != nil {
		t.Error("model has no compact form; emitting one bloats the wire and the golden")
	}
}

func TestBuildEmitsFillFractionsWithinRange(t *testing.T) {
	s := Build(testCtx(), testRegistry(), nil)
	for name, w := range s.Widgets {
		all := append(append(render.Spans{}, w.Spans...), w.Compact...)
		for _, sp := range all {
			if sp.Kind != "bar" {
				continue
			}
			if sp.Fill < 0 || sp.Fill > 1 {
				t.Errorf("%s: bar fill %v outside [0,1]", name, sp.Fill)
			}
			if sp.Cells <= 0 {
				t.Errorf("%s: bar cells = %d", name, sp.Cells)
			}
		}
	}
}

func TestBuildEchoesConfigSoTheRendererNeedsNoFile(t *testing.T) {
	ctx := testCtx()
	ctx.Cfg.BarWidth = 8
	ctx.Cfg.RefreshInterval = 2
	ctx.Cfg.Widgets.Hide = []string{"pr"}
	s := Build(ctx, testRegistry(), []string{"cost"})
	if s.Config.BarWidth != 8 {
		t.Errorf("BarWidth = %d, want 8", s.Config.BarWidth)
	}
	if s.Config.RefreshIntervalMs != 2000 {
		t.Errorf("RefreshIntervalMs = %d, want 2000", s.Config.RefreshIntervalMs)
	}
	if len(s.Config.Hide) != 1 || s.Config.Hide[0] != "pr" {
		t.Errorf("Hide = %v", s.Config.Hide)
	}
	if len(s.Config.DropPriority) != 1 || s.Config.DropPriority[0] != "cost" {
		t.Errorf("DropPriority = %v", s.Config.DropPriority)
	}
	if s.Config.CompactWidth != widgets.DefaultCompactWidth {
		t.Errorf("CompactWidth = %d, want %d", s.Config.CompactWidth, widgets.DefaultCompactWidth)
	}
}

func TestWriteIsDeterministic(t *testing.T) {
	s := Build(testCtx(), testRegistry(), nil)
	var a, b bytes.Buffer
	if err := Write(&a, s); err != nil {
		t.Fatal(err)
	}
	if err := Write(&b, s); err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(a.Bytes(), b.Bytes()) {
		t.Error("Write is not deterministic; the golden would flap")
	}
	if a.Bytes()[a.Len()-1] != '\n' {
		t.Error("Write must end with a newline")
	}
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
cd /home/joe/Development/agent-statusline && nix shell nixpkgs#go --command go test ./internal/emit/ 2>&1 | tail -10
```

Expected: FAIL — the `internal/emit` package does not exist.

- [ ] **Step 3: Implement `internal/emit/emit.go`**

```go
// Package emit serialises a rendered statusline into structured JSON, for
// renderers that own their own layout, colours and clock.
//
// The Claude Code path does not use this: it takes the ANSI encoding, where
// the terminal has no theme to consult and the harness re-invokes the binary
// on a timer. pi is the opposite on both counts — it has a live theme proxy
// and it pushes the viewport width into render(width) on every frame — so it
// gets the semantic form and does the drawing itself.
package emit

import (
	"encoding/json"
	"io"
	"reflect"

	"github.com/joegoldin/agent-statusline/internal/widgets"
	"github.com/joegoldin/agent-statusline/internal/render"
)

// SchemaVersion is bumped only for breaking changes. The renderer refuses a
// snapshot whose schema it does not know rather than drawing a wrong line.
const SchemaVersion = 1

// MaxLines mirrors the total line budget main.go applies to the ANSI path, so
// both renderers cap in the same place.
const MaxLines = 6

// Separator and FlexName are inlined rather than imported from internal/layout,
// which already imports internal/widgets and would cycle. A test in
// internal/layout pins the two literals.
const (
	separatorLiteral = " | " // REPLACE with the exact layout.Separator value
	flexNameLiteral  = "flex"
)

type Snapshot struct {
	Schema   int                       `json:"schema"`
	Mode     string                    `json:"mode"`
	AsOfMs   int64                     `json:"asOfMs"`
	Config   SnapshotConfig            `json:"config"`
	Widgets  map[string]WidgetSnapshot `json:"widgets"`
	Activity widgets.ActivitySnapshot  `json:"activity"`
}

// SnapshotConfig is the binary's effective configuration, echoed so the
// renderer never reads a config file. One reader, one resolution order, one
// set of defaults — the alternative is two implementations of
// config.ResolvePath drifting apart.
type SnapshotConfig struct {
	BarWidth          int      `json:"barWidth"`
	CompactWidth      int      `json:"compactWidth"`
	ActivityRows      int      `json:"activityRows"`
	HideWhenIdle      bool     `json:"hideWhenIdle"`
	Padding           int      `json:"padding"`
	RefreshIntervalMs int      `json:"refreshIntervalMs"`
	MaxLines          int      `json:"maxLines"`
	Separator         string   `json:"separator"`
	FlexName          string   `json:"flexName"`
	Row1              []string `json:"row1"`
	Row2              []string `json:"row2"`
	Hide              []string `json:"hide"`
	DropPriority      []string `json:"dropPriority"`
}

// WidgetSnapshot is one widget. Compact is nil when the widget renders the
// same either way, which keeps the wire and the golden files small.
type WidgetSnapshot struct {
	Visible bool         `json:"visible"`
	Spans   render.Spans `json:"spans,omitempty"`
	Compact render.Spans `json:"compact,omitempty"`
}

// Build renders every configured widget twice — once at full width and once
// narrow enough to trip Compact() — and packages the result. It mutates and
// restores ctx.Width, the only width input the dashboard widgets have, so no
// widget needs a second code path.
func Build(ctx *widgets.Context, reg widgets.Registry, dropPriority []string) Snapshot {
	cfg := ctx.Cfg
	compactWidth := ctx.CompactWidth
	if compactWidth <= 0 {
		compactWidth = widgets.DefaultCompactWidth
	}

	restore := ctx.Width
	defer func() { ctx.Width = restore }()

	names := map[string]bool{}
	for _, n := range append(append([]string{}, cfg.Widgets.Row1...), cfg.Widgets.Row2...) {
		names[n] = true
	}

	out := map[string]WidgetSnapshot{}
	for name := range names {
		w := reg.Lookup(name)
		if w == nil {
			continue // "flex" and any unknown name; the renderer handles flex itself
		}
		ctx.Width = 0 // Compact() is false when width is unknown
		full, visible := widgets.SafeRenderSpans(w, ctx)
		snap := WidgetSnapshot{Visible: visible}
		if !visible {
			out[name] = snap
			continue
		}
		snap.Spans = full
		ctx.Width = compactWidth - 1
		compact, compactVisible := widgets.SafeRenderSpans(w, ctx)
		if compactVisible && !reflect.DeepEqual(compact, full) {
			snap.Compact = compact
		}
		out[name] = snap
	}

	ctx.Width = 0
	refresh := cfg.RefreshInterval
	if refresh <= 0 {
		refresh = 1
	}
	return Snapshot{
		Schema: SchemaVersion,
		Mode:   string(ctx.Mode),
		AsOfMs: ctx.Now.UnixMilli(),
		Config: SnapshotConfig{
			BarWidth:          cfg.BarWidth,
			CompactWidth:      compactWidth,
			ActivityRows:      cfg.ActivityRows,
			HideWhenIdle:      cfg.HideWhenIdle,
			Padding:           cfg.Padding,
			RefreshIntervalMs: refresh * 1000,
			MaxLines:          MaxLines,
			Separator:         separatorLiteral,
			FlexName:          flexNameLiteral,
			Row1:              nonNil(cfg.Widgets.Row1),
			Row2:              nonNil(cfg.Widgets.Row2),
			Hide:              nonNil(cfg.Widgets.Hide),
			DropPriority:      nonNil(dropPriority),
		},
		Widgets:  out,
		Activity: widgets.BuildActivitySnapshot(ctx),
	}
}

// nonNil keeps JSON arrays as [] rather than null, so the renderer can iterate
// without a guard on every list.
func nonNil(xs []string) []string {
	if xs == nil {
		return []string{}
	}
	return xs
}

// Write emits the snapshot indented and newline-terminated. Indented because
// the golden files are reviewed by humans, and a one-line diff on a 6 kB blob
// is not a review.
func Write(w io.Writer, s Snapshot) error {
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	enc.SetEscapeHTML(false)
	return enc.Encode(s)
}
```

Set `separatorLiteral` by copying the exact value out of `internal/layout/layout.go`'s `Separator` const — do not retype the box-drawing character.

- [ ] **Step 4: Pin the inlined literals**

Add to `internal/layout/layout_test.go`:

```go
func TestSeparatorAndFlexNameMatchTheEmitter(t *testing.T) {
	// internal/emit inlines these two literals because importing this package
	// would cycle (layout already imports widgets, and emit imports both).
	// Keep them in step here.
	if want := "│"; !strings.Contains(Separator, want) {
		t.Errorf("Separator = %q; update emit.separatorLiteral to match", Separator)
	}
	if FlexName != "flex" {
		t.Errorf("FlexName = %q; update emit.flexNameLiteral to match", FlexName)
	}
}
```

- [ ] **Step 5: Run the emit tests**

Run:
```bash
cd /home/joe/Development/agent-statusline && nix shell nixpkgs#go --command go test ./internal/emit/ ./internal/layout/ -v 2>&1 | tail -25
```

Expected: PASS for all six `emit` cases and the layout pin.

- [ ] **Step 6: Wire the `--emit` flag into `cmd/agent-statusline/main.go`**

Move `registry := buildRegistry()` up so it sits immediately after the `ctx.ToolTimingProvider = memoize(...)` block, then insert directly below it:

```go
	// --emit selects the OUTPUT encoding, orthogonally to --mode, which selects
	// the INPUT decoder. Default "ansi" is today's behaviour byte for byte, so
	// Claude Code and every existing invocation are unaffected.
	switch flagValue("--emit") {
	case "", "ansi":
		// fall through to the ANSI renderer below
	case "json":
		// Width is deliberately not detected: the pi renderer is told the
		// viewport width on every frame and would ignore ours anyway.
		if err := emit.Write(os.Stdout, emit.Build(ctx, registry, dropPriority)); err != nil {
			debugLog("emit.Write: %v", err)
		}
		return
	default:
		debugLog("unknown --emit %q (want ansi or json)", flagValue("--emit"))
		os.Exit(0)
	}
```

Delete the now-duplicated `registry := buildRegistry()` further down, and add `"github.com/joegoldin/agent-statusline/internal/emit"` to the imports.

- [ ] **Step 7: Add the JSON golden fixture**

In `internal/e2e/golden_test.go`:

```go
type fixture struct {
	name  string
	width string
	mode  string // "" means no --mode flag, exercising autodetect
	emit  string // "" means the default ansi encoding
}

// goldenName distinguishes the two encodings of one input fixture.
func (f fixture) goldenName() string {
	if f.emit == "" || f.emit == "ansi" {
		return f.name
	}
	return f.name + "." + f.emit
}

func TestGolden(t *testing.T) {
	tests := []fixture{
		{"idle", "80", "", ""},
		{"full", "120", "", ""},
		{"narrow", "40", "", ""},
		{"pi-full", "120", "", ""},
		{"pi-narrow", "40", "", ""},
		{"pi-full", "120", "", "json"},
	}
	for _, tc := range tests {
		t.Run(tc.goldenName(), func(t *testing.T) {
			runGolden(t, tc)
		})
	}
}
```

and in `runGolden`, take the golden path from `goldenName()` while stdin still comes from `tc.name`, and pass the flag:

```go
	stdinPath := filepath.Join("testdata", tc.name+".json")
	goldenPath := filepath.Join("testdata", tc.goldenName()+".golden")
	...
	if tc.emit != "" {
		args = append(args, "--emit", tc.emit)
	}
```

- [ ] **Step 8: Verify the new fixture fails, then generate only it**

Run:
```bash
cd /home/joe/Development/agent-statusline && nix shell nixpkgs#go --command go test ./internal/e2e/ -run 'TestGolden/pi-full.json' -v 2>&1 | tail -8
```

Expected: FAIL — `missing golden file "testdata/pi-full.json.golden"`.

Then:
```bash
cd /home/joe/Development/agent-statusline && nix shell nixpkgs#go --command go test ./internal/e2e/ -run 'TestGolden/pi-full.json' -update && git status --porcelain internal/e2e/testdata/
```

Expected: exactly one line, `?? internal/e2e/testdata/pi-full.json.golden`. If any existing `.golden` shows as modified, `-update` matched too broadly: `git checkout -- internal/e2e/testdata/` and redo with the exact `-run` filter.

- [ ] **Step 9: Review the generated snapshot by eye**

Run:
```bash
cd /home/joe/Development/agent-statusline && head -40 internal/e2e/testdata/pi-full.json.golden && echo "--- escapes:" && grep -c 'u001b' internal/e2e/testdata/pi-full.json.golden && echo "--- bars:" && grep -c '"kind": "bar"' internal/e2e/testdata/pi-full.json.golden
```

Confirm all four before committing:
1. `"schema": 1` and `"mode": "pi"`;
2. `"asOfMs": 1748260800000` — pinned by `CLAUDE_STATUSLINE_NOW`, so the golden cannot flap;
3. the escape count is **0**. A raw escape in the snapshot means some widget is still falling through `SafeRenderSpans`'s legacy path;
4. at least one `"kind": "bar"` with `fill` in [0,1] and `cells` 10 — the `context` widget.

- [ ] **Step 10: Run everything**

Run:
```bash
cd /home/joe/Development/agent-statusline && nix shell nixpkgs#go --command go test ./... 2>&1 | tail -15 && git diff --stat internal/e2e/testdata/
```

Expected: all `ok`, and `git diff --stat` empty (the new golden is untracked, not a modification of an existing one).

- [ ] **Step 11: Commit**

```bash
cd /home/joe/Development/agent-statusline
nix shell nixpkgs#go --command gofmt -w ./cmd ./internal
git add -A
git commit -m "feat: --emit json, a structured snapshot for native renderers

--emit selects the output encoding orthogonally to --mode, which selects the
input decoder; the default stays ansi so every existing caller is unaffected.
Widgets render twice, wide and narrow, and both span lists ship, because the
consumer learns the viewport width only at paint time. The effective config is
echoed into the snapshot so the pi renderer reads no config file: one reader,
one resolution order, one set of defaults."
```

---
### Task 6: Move the extension toolchain to bun

Small and self-contained, and it must land before any new TypeScript is written so there is only ever one test runner in the tree.

**Files:**
- Modify: `extension/package.json`
- Delete: `extension/package-lock.json`, `extension/node_modules/`
- Create: `extension/bun.lock`
- Create: `extension/bunfig.toml`
- Modify: `extension/statusline.test.ts` (import line only)
- Modify: `.gitignore`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `bun test` as the sole test command, run from `extension/`
  - devDependencies `@earendil-works/pi-tui@0.84.2` and `@earendil-works/pi-coding-agent@0.84.2`, used only by tests (Tasks 7 and 10)
  - `extension/bun.lock`, the input to `bun2nix` in Task 11

- [ ] **Step 1: Record the baseline so the migration is provably lossless**

```bash
cd /home/joe/Development/agent-statusline/extension && npx vitest run 2>&1 | tail -6
```

Expected: `Test Files 1 passed (1)` and `Tests 27 passed (27)`. Write the number 27 down; it is the gate for Step 4.

- [ ] **Step 2: Rewrite `extension/package.json`**

```json
{
  "name": "@joegoldin/agent-statusline-pi",
  "version": "0.3.0",
  "description": "pi extension that renders the agent-statusline dashboard natively",
  "license": "MIT",
  "type": "module",
  "keywords": ["pi-package", "statusline"],
  "pi": {
    "extensions": ["./statusline.ts"]
  },
  "scripts": {
    "test": "bun test"
  },
  "devDependencies": {
    "@earendil-works/pi-tui": "0.84.2",
    "@earendil-works/pi-coding-agent": "0.84.2"
  }
}
```

There is no `dependencies` block and there must never be one: pi copies these `.ts` files out of the Nix store with no `node_modules` beside them, so a runtime import of anything but a relative path fails at load. Both devDependencies exist solely so tests can compare against pi's real implementation.

- [ ] **Step 3: Create `extension/bunfig.toml`**

```toml
# bun test discovers *.test.ts under the package root. The runtime extension
# sources live in src/ and must stay import-free of node_modules, so tests are
# kept beside them and nothing else is scanned.
[test]
root = "."
coverageSkipTestFiles = true
```

- [ ] **Step 4: Swap the runner and install**

```bash
cd /home/joe/Development/agent-statusline/extension
rm -rf node_modules package-lock.json
sed -i 's#from "vitest"#from "bun:test"#' statusline.test.ts
bun install
bun test 2>&1 | tail -6
```

Expected: `27 pass`, `0 fail`. The import line is the entire migration — verified before this plan was written by running exactly this sequence in a scratch copy. If `vi.` appears anywhere in the file, replace it with `jest.` from `bun:test`; `bun test` on 1.3.13 supports `jest.useFakeTimers`, `jest.advanceTimersByTime`, `jest.getTimerCount`, `mock()` and `toHaveBeenCalledTimes`.

- [ ] **Step 5: Confirm the lockfile landed and node_modules is ignored**

```bash
cd /home/joe/Development/agent-statusline
test -f extension/bun.lock && echo "bun.lock present"
grep -q '^extension/node_modules$' .gitignore || printf 'extension/node_modules\n' >> .gitignore
git status --porcelain | head -20
```

Expected: `bun.lock present`, and `git status` shows `extension/package.json` and `extension/statusline.test.ts` modified, `extension/package-lock.json` deleted, `extension/bun.lock` and `extension/bunfig.toml` new — and no `node_modules` entries.

- [ ] **Step 6: Commit**

```bash
cd /home/joe/Development/agent-statusline
git add -A
git commit -m "chore(extension): move the JS toolchain from npm/vitest to bun

pi runs on the bun-built coding agent, so the extension's toolchain follows.
The vitest-to-bun:test migration was one import line and all 27 tests pass
unchanged. pi-tui and pi-coding-agent join as devDependencies so tests can
compare against pi's real implementations; the runtime extension keeps zero
dependencies, because pi loads these files out of the Nix store with no
node_modules beside them."
```

---

### Task 7: A width function that agrees with pi's

Every line the component returns must fit the width pi pushed in — that is the contract the differential renderer enforces. Our own `visibleWidth` therefore has to agree with pi-tui's on every string we can produce, and the only credible way to establish that is to run both over a shared corpus.

**Files:**
- Create: `extension/src/width.ts`
- Create: `extension/src/width.test.ts`
- Create: `extension/testdata/width-corpus.json`
- Create: `internal/render/corpus_test.go`

**Interfaces:**
- Consumes: `@earendil-works/pi-tui`'s `visibleWidth` and `truncateToWidth` (devDependency, tests only); Go's `render.VisibleWidth` and `render.Truncate`/`render.TruncateMiddle`
- Produces:
  - `export function visibleWidth(s: string): number`
  - `export function truncateEnd(s: string, max: number, ellipsis?: string): string`
  - `export function truncateMiddle(s: string, max: number): string`
  - `export function padTo(s: string, width: number): string`
  - `extension/testdata/width-corpus.json` — a shared fixture consumed by both the TS parity test and a new Go test, so all three implementations are pinned to each other

- [ ] **Step 1: Write the corpus**

Create `extension/testdata/width-corpus.json`. It must contain every glyph class the renderer can emit plus the pathological cases:

```json
[
  "",
  "main",
  "main*",
  "53%",
  " | ",
  "ETA 1h12m",
  "\u001b[32mmain\u001b[0m",
  "\u001b[2mup2\u001b[0m \u001b[2mdown1\u001b[0m",
  "\u001b[38;5;208m60%\u001b[0m",
  "\u001b[38;2;88;204;78m⣿\u001b[0m",
  "⣿⣿⣿⣇⠀⠀",
  "██▌    ",
  "━━━━",
  "▷▷",
  "▶▷",
  "✓ Read ×3",
  "↡2%",
  "↣5%",
  "~/Development/agent-statusline",
  "/.../src/modes/interactive",
  "bun test --coverage",
  "日本語のパス",
  "emoji 🚀 rocket",
  "🏳️‍🌈 flag",
  "combining é accent",
  "\u001b]8;;https://example.test/pr/12\u001b\\#12 approved\u001b]8;;\u001b\\",
  "tab\there",
  "trailing spaces   ",
  "\u001b[2m\u001b[0m"
]
```

The OSC-8 entry matters most: the `pr` widget emits one, and a width function that counts the URL bytes would blow the line budget by fifty columns.

- [ ] **Step 2: Write the failing parity test**

Create `extension/src/width.test.ts`:

```ts
import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

import {
  truncateToWidth as piTruncateToWidth,
  visibleWidth as piVisibleWidth,
} from "@earendil-works/pi-tui";

import { padTo, truncateEnd, truncateMiddle, visibleWidth } from "./width";

const corpus: string[] = JSON.parse(
  readFileSync(join(import.meta.dir, "..", "testdata", "width-corpus.json"), "utf8"),
);

describe("visibleWidth", () => {
  // pi-tui's visibleWidth is what pi's own differential renderer measures with.
  // If ours disagrees by one cell, our lines overflow or under-fill and the
  // frame corrupts. So pi is the authority and we are pinned to it.
  it("agrees with pi-tui on every corpus entry", () => {
    for (const s of corpus) {
      expect([s, visibleWidth(s)]).toEqual([s, piVisibleWidth(s)]);
    }
  });

  it("agrees with pi-tui on fuzzed unicode", () => {
    let seed = 20260818;
    const rand = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648;
    for (let i = 0; i < 2000; i++) {
      let s = "";
      for (let j = 0; j < 1 + Math.floor(rand() * 12); j++) {
        const cp = Math.floor(rand() * 0x2ffff);
        if (cp >= 0xd800 && cp <= 0xdfff) continue;
        s += String.fromCodePoint(cp);
      }
      expect([s, visibleWidth(s)]).toEqual([s, piVisibleWidth(s)]);
    }
  });

  it("ignores OSC 8 hyperlink payloads", () => {
    const link = "\x1b]8;;https://example.test/pr/12\x1b\\#12\x1b]8;;\x1b\\";
    expect(visibleWidth(link)).toBe(3);
  });
});

describe("truncateEnd", () => {
  it("never exceeds the budget, measured by pi-tui", () => {
    for (const s of corpus) {
      for (const max of [0, 1, 3, 7, 20, 200]) {
        expect(piVisibleWidth(truncateEnd(s, max))).toBeLessThanOrEqual(max);
      }
    }
  });

  it("matches pi-tui's own truncateToWidth for plain text", () => {
    for (const s of corpus.filter((c) => !c.includes("\x1b") && !c.includes("\t"))) {
      expect(truncateEnd(s, 10)).toBe(piTruncateToWidth(s, 10));
    }
  });

  it("leaves a string that already fits untouched", () => {
    expect(truncateEnd("main", 10)).toBe("main");
  });
});

describe("truncateMiddle", () => {
  it("keeps the head and the tail", () => {
    const got = truncateMiddle("/home/joe/Development/agent-statusline/internal/render", 20);
    expect(visibleWidth(got)).toBeLessThanOrEqual(20);
    expect(got.startsWith("/home")).toBe(true);
    expect(got.endsWith("render")).toBe(true);
  });

  it("degrades to an end truncation when the budget is tiny", () => {
    expect(visibleWidth(truncateMiddle("abcdefgh", 2))).toBeLessThanOrEqual(2);
  });
});

describe("padTo", () => {
  it("pads to exactly the requested width", () => {
    expect(piVisibleWidth(padTo("main", 10))).toBe(10);
  });

  it("never shrinks a string that is already wider", () => {
    expect(padTo("main", 2)).toBe("main");
  });
});
```

- [ ] **Step 3: Run it to verify it fails**

Run:
```bash
cd /home/joe/Development/agent-statusline/extension && bun test src/width.test.ts 2>&1 | tail -12
```

Expected: FAIL — `Cannot find module './width'`.

- [ ] **Step 4: Implement `extension/src/width.ts`**

```ts
// Cell-width arithmetic, ANSI- and wide-char-aware.
//
// This is a deliberate re-implementation of the subset of
// @earendil-works/pi-tui's utils.ts that the statusline needs, NOT an import.
// pi loads this extension as bare .ts files copied out of the Nix store with
// no node_modules beside them, so a runtime dependency would fail at load.
//
// Re-implementing a width function is normally a mistake: pi's differential
// renderer measures with pi-tui's visibleWidth, so a one-cell disagreement
// corrupts the frame. width.test.ts therefore pins this file against the real
// pi-tui over a shared corpus plus 2000 fuzzed strings. If pi's ever changes,
// that test fails and this file is re-derived.

const ANSI_CSI = /\x1b\[[0-9;?]*[ -/]*[@-~]/g;
const ANSI_OSC = /\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)/g;
const ANSI_APC = /\x1b_[^\x1b]*\x1b\\/g;

/** Strip the escape sequences pi-tui strips, in the order it strips them. */
export function stripAnsi(s: string): string {
  if (!s.includes("\x1b")) return s;
  return s.replace(ANSI_APC, "").replace(ANSI_OSC, "").replace(ANSI_CSI, "");
}

// East Asian Wide / Fullwidth ranges, matching pi-tui's table. Anything not
// listed is one cell; zero-width joiners, variation selectors and combining
// marks are zero.
const WIDE_RANGES: ReadonlyArray<readonly [number, number]> = [
  [0x1100, 0x115f], [0x2e80, 0x303e], [0x3041, 0x33ff], [0x3400, 0x4dbf],
  [0x4e00, 0x9fff], [0xa000, 0xa4cf], [0xac00, 0xd7a3], [0xf900, 0xfaff],
  [0xfe10, 0xfe19], [0xfe30, 0xfe6f], [0xff00, 0xff60], [0xffe0, 0xffe6],
  [0x1f300, 0x1f64f], [0x1f900, 0x1f9ff], [0x1fa70, 0x1faff],
  [0x20000, 0x2fffd], [0x30000, 0x3fffd],
];

const ZERO_RANGES: ReadonlyArray<readonly [number, number]> = [
  [0x0300, 0x036f], [0x200b, 0x200f], [0xfe00, 0xfe0f], [0xfeff, 0xfeff],
];

function inRanges(cp: number, ranges: ReadonlyArray<readonly [number, number]>): boolean {
  let lo = 0;
  let hi = ranges.length - 1;
  while (lo <= hi) {
    const mid = (lo + hi) >> 1;
    const [a, b] = ranges[mid]!;
    if (cp < a) hi = mid - 1;
    else if (cp > b) lo = mid + 1;
    else return true;
  }
  return false;
}

export function runeWidth(cp: number): number {
  if (inRanges(cp, ZERO_RANGES)) return 0;
  if (inRanges(cp, WIDE_RANGES)) return 2;
  return 1;
}

/** On-screen cell width, ignoring escape sequences. Tabs count as 3, as pi does. */
export function visibleWidth(s: string): number {
  if (s.length === 0) return 0;
  const clean = stripAnsi(s).replace(/\t/g, "   ");
  let total = 0;
  for (const ch of clean) total += runeWidth(ch.codePointAt(0)!);
  return total;
}

/**
 * Walk s emitting whole graphemes-ish chunks while carrying escape state, so a
 * truncation never severs an escape sequence and leaves the terminal coloured.
 */
function sliceCells(s: string, max: number): { text: string; width: number } {
  if (max <= 0) return { text: "", width: 0 };
  let out = "";
  let width = 0;
  let i = 0;
  while (i < s.length) {
    if (s[i] === "\x1b") {
      const rest = s.slice(i);
      const m =
        /^\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)/.exec(rest) ??
        /^\x1b_[^\x1b]*\x1b\\/.exec(rest) ??
        /^\x1b\[[0-9;?]*[ -/]*[@-~]/.exec(rest);
      if (m) {
        out += m[0];
        i += m[0].length;
        continue;
      }
    }
    const cp = s.codePointAt(i)!;
    const ch = String.fromCodePoint(cp);
    const w = ch === "\t" ? 3 : runeWidth(cp);
    if (width + w > max) break;
    out += ch;
    width += w;
    i += ch.length;
  }
  return { text: out, width };
}

/** Truncate to max cells, appending an ellipsis when anything was dropped. */
export function truncateEnd(s: string, max: number, ellipsis = "..."): string {
  if (max <= 0) return "";
  if (visibleWidth(s) <= max) return s;
  const ew = visibleWidth(ellipsis);
  if (ew >= max) return sliceCells(ellipsis, max).text;
  return sliceCells(s, max - ew).text + ellipsis;
}

/**
 * Truncate from the middle, keeping the head and the tail. Long bash commands
 * and deep paths are unreadable when only the head survives.
 */
export function truncateMiddle(s: string, max: number): string {
  if (max <= 0) return "";
  const total = visibleWidth(s);
  if (total <= max) return s;
  const ellipsis = "…";
  if (max <= 2) return sliceCells(s, max).text;
  const budget = max - 1;
  const head = Math.ceil(budget / 2);
  const tail = budget - head;
  const headText = sliceCells(s, head).text;
  // Take the tail by slicing from the far end of the stripped string; escape
  // runs in the tail are dropped rather than half-emitted.
  const plain = stripAnsi(s);
  let tailText = "";
  let w = 0;
  const chars = Array.from(plain);
  for (let i = chars.length - 1; i >= 0 && w < tail; i--) {
    const cw = runeWidth(chars[i]!.codePointAt(0)!);
    if (w + cw > tail) break;
    tailText = chars[i]! + tailText;
    w += cw;
  }
  return headText + ellipsis + tailText;
}

/** Right-pad to exactly width cells. Never shrinks. */
export function padTo(s: string, width: number): string {
  const w = visibleWidth(s);
  return w >= width ? s : s + " ".repeat(width - w);
}
```

The `WIDE_RANGES` / `ZERO_RANGES` tables are a first approximation. Run Step 5; where the fuzz test disagrees with pi-tui, read the failing codepoint out of the assertion message, look it up in `node_modules/@earendil-works/pi-tui/src/utils.ts`, and adjust the tables until the test is green. Do not weaken the test to make it pass.

- [ ] **Step 5: Run the parity test**

Run:
```bash
cd /home/joe/Development/agent-statusline/extension && bun test src/width.test.ts 2>&1 | tail -15
```

Expected: all cases pass, including the 2000-string fuzz.

- [ ] **Step 6: Pin the Go implementation to the same corpus**

Create `internal/render/corpus_test.go`:

```go
package render

import (
	"encoding/json"
	"os"
	"testing"
)

// The corpus is shared with extension/src/width.test.ts, which pins the
// TypeScript port against the real pi-tui. Pinning Go against the same strings
// closes the triangle: Go, our TS port and pi-tui all agree, so the compact
// forms the emitter chooses and the widths the renderer measures cannot drift.
func TestVisibleWidthMatchesTheSharedCorpus(t *testing.T) {
	raw, err := os.ReadFile("../../extension/testdata/width-corpus.json")
	if err != nil {
		t.Skipf("corpus unavailable: %v", err)
	}
	var corpus []string
	if err := json.Unmarshal(raw, &corpus); err != nil {
		t.Fatalf("corpus is not valid JSON: %v", err)
	}
	if len(corpus) < 20 {
		t.Fatalf("corpus has %d entries; it should cover every glyph class", len(corpus))
	}
	for _, s := range corpus {
		if w := VisibleWidth(s); w < 0 {
			t.Errorf("VisibleWidth(%q) = %d", s, w)
		}
		if got := VisibleWidth(Truncate(s, 10)); got > 10 {
			t.Errorf("Truncate(%q, 10) is %d cells wide", s, got)
		}
	}
}
```

This asserts self-consistency rather than exact equality with pi-tui: Go's tab and emoji handling is its own, and the Claude goldens pin that half. The corpus's job here is to guarantee the two suites exercise the same strings, so a glyph that breaks one is exercised against the other.

- [ ] **Step 7: Run both suites**

Run:
```bash
cd /home/joe/Development/agent-statusline && nix shell nixpkgs#go --command go test ./internal/render/ 2>&1 | tail -5 && cd extension && bun test 2>&1 | tail -6
```

Expected: Go `ok`, and bun reporting the 27 migrated tests plus the new width cases, `0 fail`.

- [ ] **Step 8: Commit**

```bash
cd /home/joe/Development/agent-statusline
git add -A
git commit -m "feat(extension): cell-width arithmetic pinned to pi-tui

pi's differential renderer measures with pi-tui's visibleWidth, so a one-cell
disagreement corrupts the frame. The extension cannot import pi-tui at runtime
(pi copies bare .ts out of the Nix store), so this is a re-implementation held
in place by a differential test: a shared corpus of every glyph class we emit,
plus 2000 fuzzed strings, checked against the real pi-tui. Go reads the same
corpus, closing the triangle."
```

---

### Task 8: Snapshot types, intent mapping and the theme-derived bar

Three small modules and the first real use of pi's `Theme`.

**Files:**
- Create: `extension/src/snapshot.ts`, `extension/src/intents.ts`, `extension/src/bars.ts`
- Create: `extension/src/intents.test.ts`, `extension/src/bars.test.ts`
- Create: `extension/src/testing.ts` (a recording theme double, shared by later tasks)

**Interfaces:**
- Consumes: the `--emit json` document from Task 5, field for field; `visibleWidth` from Task 7
- Produces:
  - `export interface Snapshot, SnapshotConfig, WidgetSnapshot, Span, ActivitySnapshot, ActivityItem, AgentItem, TodoItem, ToolCountItem`
  - `export const SUPPORTED_SCHEMA = 1`
  - `export function parseSnapshot(raw: string): Snapshot | undefined`
  - `export interface ThemeLike { fg(color, text): string; getFgAnsi(color): string; bold(text): string; getColorMode(): "truecolor" | "256color" }`
  - `export function paint(spans: Span[], theme: ThemeLike, cfg: SnapshotConfig): string`
  - `export const INTENT_TOKENS: Record<Intent, { token: string; bold?: boolean }>`
  - `export function renderBar(fill: number, cells: number, style: string, theme: ThemeLike): string`
  - `export function recordingTheme(): { theme: ThemeLike; tokens(): string[]; calls(): Array<[string, string]> }`

- [ ] **Step 1: Write `extension/src/snapshot.ts`**

No test of its own — it is types plus one guard, exercised by every later suite.

```ts
// The wire format emitted by `agent-statusline --mode pi --emit json`.
// Every field name here matches a JSON tag in internal/emit/emit.go and
// internal/render/span.go. Changing one without the other breaks the pi path
// silently, which is why internal/e2e/testdata/pi-full.json.golden exists.

export type Intent =
  | "text" | "dim" | "muted" | "accent" | "meta"
  | "path" | "ok" | "warn" | "caution" | "danger";

export interface Span {
  kind: "text" | "bar";
  text?: string;
  intent?: Intent;
  link?: string;
  /** bar only: fraction in [0,1], NOT a percentage */
  fill?: number;
  cells?: number;
  style?: "braille" | "block" | "line";
}

export interface WidgetSnapshot {
  visible: boolean;
  spans?: Span[];
  /** Present only when the widget's narrow form differs from its wide one. */
  compact?: Span[];
}

export interface SnapshotConfig {
  barWidth: number;
  compactWidth: number;
  activityRows: number;
  hideWhenIdle: boolean;
  padding: number;
  refreshIntervalMs: number;
  maxLines: number;
  separator: string;
  flexName: string;
  row1: string[];
  row2: string[];
  hide: string[];
  dropPriority: string[];
}

export interface ActivityItem {
  id: string;
  name: string;
  target?: string;
  state: "running" | "waiting" | "done";
  emittedAtMs?: number;
  startedAtMs?: number;
  endedAtMs?: number;
}

export interface ToolCountItem { name: string; count: number }

export interface AgentItem {
  name: string;
  model?: string;
  description?: string;
  startedAtMs: number;
  endedAtMs?: number;
}

export interface TodoItem {
  subject?: string;
  done: number;
  total: number;
  allComplete: boolean;
  timestampMs?: number;
}

export interface ActivityGraces {
  toolCompleteMs: number;
  agentCompleteMs: number;
  agentRunningStaleMs: number;
  todoCompleteMs: number;
}

export interface ActivitySnapshot {
  graces: ActivityGraces;
  tools: ActivityItem[] | null;
  toolCounts: ToolCountItem[] | null;
  agents: AgentItem[] | null;
  todos: TodoItem | null;
}

export interface Snapshot {
  schema: number;
  mode: string;
  asOfMs: number;
  config: SnapshotConfig;
  widgets: Record<string, WidgetSnapshot>;
  activity: ActivitySnapshot;
}

export const SUPPORTED_SCHEMA = 1;

/**
 * Parse a snapshot, refusing anything this renderer does not understand.
 *
 * A wrong statusline is worse than none, so a schema bump, malformed JSON or a
 * missing config block all return undefined and the component keeps drawing
 * the last good snapshot.
 */
export function parseSnapshot(raw: string): Snapshot | undefined {
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return undefined;
  }
  const s = parsed as Partial<Snapshot>;
  if (!s || typeof s !== "object") return undefined;
  if (s.schema !== SUPPORTED_SCHEMA) return undefined;
  if (!s.config || typeof s.config.separator !== "string") return undefined;
  if (!s.widgets || typeof s.widgets !== "object") return undefined;
  return s as Snapshot;
}
```

- [ ] **Step 2: Write the failing intent test**

Create `extension/src/testing.ts` first — later tasks reuse it:

```ts
import type { ThemeLike } from "./intents";

/**
 * A Theme double that records every colour request, so tests can assert which
 * theme tokens a renderer used rather than which bytes it produced. That is
 * the whole point of going native: assertions on token names survive a theme
 * change, assertions on escape codes do not.
 */
export function recordingTheme(
  options: { colorMode?: "truecolor" | "256color"; ansi?: Record<string, string> } = {},
) {
  const seen: Array<[string, string]> = [];
  const ansi = options.ansi ?? {
    text: "\x1b[38;2;220;220;220m",
    dim: "\x1b[38;2;130;135;140m",
    muted: "\x1b[38;2;150;150;150m",
    accent: "\x1b[38;2;0;175;215m",
    success: "\x1b[38;2;88;204;78m",
    warning: "\x1b[38;2;236;200;64m",
    error: "\x1b[38;2;224;71;71m",
    mdLink: "\x1b[38;2;95;175;255m",
    customMessageLabel: "\x1b[38;2;200;120;255m",
  };
  const theme: ThemeLike = {
    fg(color, text) {
      seen.push([color, text]);
      return `<${color}>${text}</${color}>`;
    },
    getFgAnsi(color) {
      seen.push([color, ""]);
      const v = ansi[color];
      if (!v) throw new Error(`Unknown theme color: ${color}`);
      return v;
    },
    bold(text) {
      return `<b>${text}</b>`;
    },
    getColorMode: () => options.colorMode ?? "truecolor",
  };
  return {
    theme,
    calls: () => seen,
    tokens: () => Array.from(new Set(seen.map(([c]) => c))),
  };
}
```

Then `extension/src/intents.test.ts`:

```ts
import { describe, expect, it } from "bun:test";

import { INTENT_TOKENS, paint } from "./intents";
import type { Snapshot, SnapshotConfig, Span } from "./snapshot";
import { recordingTheme } from "./testing";

const cfg = { barWidth: 10, separator: " | " } as SnapshotConfig;

// Exactly the intents internal/render/span.go can emit. If Go grows one and
// this list is not updated, the mapping test below fails rather than silently
// painting it in the default foreground.
const GO_INTENTS = [
  "text", "dim", "muted", "accent", "meta",
  "path", "ok", "warn", "caution", "danger",
] as const;

describe("INTENT_TOKENS", () => {
  it("maps every intent Go can emit", () => {
    for (const i of GO_INTENTS) {
      expect(INTENT_TOKENS[i]).toBeDefined();
      expect(typeof INTENT_TOKENS[i].token).toBe("string");
    }
    expect(Object.keys(INTENT_TOKENS).sort()).toEqual([...GO_INTENTS].sort());
  });

  it("uses only real pi theme colour slots", () => {
    // From ThemeColor in pi's src/modes/interactive/theme/theme.ts:112-159.
    const SLOTS = new Set([
      "accent", "border", "borderAccent", "borderMuted", "success", "error",
      "warning", "muted", "dim", "text", "thinkingText", "searchMatchText",
      "userMessageText", "customMessageText", "customMessageLabel",
      "toolTitle", "toolOutput", "mdHeading", "mdLink", "mdLinkUrl", "mdCode",
    ]);
    for (const i of GO_INTENTS) {
      expect([i, SLOTS.has(INTENT_TOKENS[i].token)]).toEqual([i, true]);
    }
  });

  it("splits path from warn, which Go cannot", () => {
    expect(INTENT_TOKENS.path.token).not.toBe(INTENT_TOKENS.warn.token);
  });

  it("expresses caution as a bolded warning, the closest a theme can get", () => {
    expect(INTENT_TOKENS.caution.token).toBe("warning");
    expect(INTENT_TOKENS.caution.bold).toBe(true);
  });
});

describe("paint", () => {
  it("routes every text span through theme.fg, never through a literal escape", () => {
    const rec = recordingTheme();
    const spans: Span[] = [
      { kind: "text", text: "main", intent: "ok" },
      { kind: "text", text: " ", intent: "text" },
      { kind: "text", text: "60%", intent: "caution" },
    ];
    const out = paint(spans, rec.theme, cfg);
    expect(out).not.toMatch(/\x1b\[3[0-9]m/);
    expect(rec.tokens().sort()).toEqual(["success", "text", "warning"]);
  });

  it("bolds the caution intent", () => {
    const rec = recordingTheme();
    const out = paint([{ kind: "text", text: "60%", intent: "caution" }], rec.theme, cfg);
    expect(out).toContain("<b>");
  });

  it("treats a missing intent as text rather than dropping the span", () => {
    const rec = recordingTheme();
    expect(paint([{ kind: "text", text: "raw" }], rec.theme, cfg)).toContain("raw");
  });

  it("emits an empty string for empty text, with no dangling escapes", () => {
    const rec = recordingTheme();
    expect(paint([{ kind: "text", text: "", intent: "ok" }], rec.theme, cfg)).toBe("");
  });

  it("wraps a linked span in OSC 8 outside the colour", () => {
    const rec = recordingTheme();
    const out = paint(
      [{ kind: "text", text: "#12", intent: "accent", link: "https://x/1" }],
      rec.theme,
      cfg,
    );
    expect(out.startsWith("\x1b]8;;https://x/1\x1b\\")).toBe(true);
    expect(out.endsWith("\x1b]8;;\x1b\\")).toBe(true);
    expect(out).toContain("#12");
  });

  it("renders a bar span through the bar renderer, not as text", () => {
    const rec = recordingTheme();
    const out = paint([{ kind: "bar", fill: 0.5, cells: 4, style: "block" }], rec.theme, cfg);
    expect(out.length).toBeGreaterThan(0);
    expect(rec.tokens()).toContain("success");
  });

  it("survives an unknown intent from a newer binary", () => {
    const rec = recordingTheme();
    const span = { kind: "text", text: "x", intent: "brand-new" } as unknown as Span;
    expect(paint([span], rec.theme, cfg)).toContain("x");
  });
});
```

- [ ] **Step 3: Run it to verify it fails**

Run:
```bash
cd /home/joe/Development/agent-statusline/extension && bun test src/intents.test.ts 2>&1 | tail -12
```

Expected: FAIL — `Cannot find module './intents'`.

- [ ] **Step 4: Implement `extension/src/intents.ts`**

```ts
import { renderBar } from "./bars";
import type { Intent, SnapshotConfig, Span } from "./snapshot";

/**
 * The slice of pi's Theme this renderer uses. Declared structurally rather than
 * imported so the runtime file has no dependency; pi hands the real Theme to
 * the component factory and it satisfies this shape.
 * See pi's src/modes/interactive/theme/theme.ts:350-436.
 */
export interface ThemeLike {
  fg(color: string, text: string): string;
  getFgAnsi(color: string): string;
  bold(text: string): string;
  getColorMode(): "truecolor" | "256color";
}

/**
 * Semantic intent to pi theme token. This is the other half of the table in
 * internal/render/span.go, and the reason the statusline finally follows
 * /theme instead of hardcoding SGR 31..36.
 *
 * Two entries are worth reading twice:
 *
 *  - `path` maps to mdLink while `warn` maps to warning. Under Claude Code
 *    both emit SGR 33, because that palette has no separate colour for a
 *    directory. A theme does, so here they part company.
 *  - `caution` is the 4th step of the five-step context ramp, which is orange
 *    in the Claude palette. pi themes expose no orange slot (ThemeColor,
 *    theme.ts:112-159), so it becomes a bolded warning: still visibly hotter
 *    than warn, still a colour the user chose.
 */
export const INTENT_TOKENS: Record<Intent, { token: string; bold?: boolean }> = {
  text: { token: "text" },
  dim: { token: "dim" },
  muted: { token: "muted" },
  accent: { token: "accent" },
  meta: { token: "customMessageLabel" },
  path: { token: "mdLink" },
  ok: { token: "success" },
  warn: { token: "warning" },
  caution: { token: "warning", bold: true },
  danger: { token: "error" },
};

function colourise(text: string, intent: Intent | undefined, theme: ThemeLike): string {
  if (text === "") return "";
  const mapping = INTENT_TOKENS[intent ?? "text"] ?? INTENT_TOKENS.text;
  let out: string;
  try {
    out = theme.fg(mapping.token, text);
  } catch {
    // An older or hand-written theme may lack an optional slot; falling back
    // to the default foreground loses a colour, never a widget.
    out = theme.fg("text", text);
  }
  return mapping.bold ? theme.bold(out) : out;
}

/** OSC 8 hyperlink, applied outside the colour so the link covers the run. */
function hyperlink(url: string, text: string): string {
  return `\x1b]8;;${url}\x1b\\${text}\x1b]8;;\x1b\\`;
}

/** Render one widget's spans into a coloured string. */
export function paint(spans: Span[], theme: ThemeLike, cfg: SnapshotConfig): string {
  let out = "";
  for (const span of spans) {
    if (span.kind === "bar") {
      out += renderBar(span.fill ?? 0, span.cells ?? cfg.barWidth, span.style ?? "block", theme);
      continue;
    }
    const coloured = colourise(span.text ?? "", span.intent, theme);
    out += span.link && coloured ? hyperlink(span.link, coloured) : coloured;
  }
  return out;
}
```

- [ ] **Step 5: Write the failing bar test**

Create `extension/src/bars.test.ts`:

```ts
import { describe, expect, it } from "bun:test";

import { renderBar } from "./bars";
import { visibleWidth } from "./width";
import { recordingTheme } from "./testing";

describe("renderBar", () => {
  it("is exactly `cells` columns wide at every fill", () => {
    const { theme } = recordingTheme();
    for (const fill of [0, 0.01, 0.25, 0.5, 0.535, 0.99, 1]) {
      for (const style of ["braille", "block", "line"] as const) {
        expect([fill, style, visibleWidth(renderBar(fill, 10, style, theme))]).toEqual([
          fill, style, 10,
        ]);
      }
    }
  });

  it("derives its ramp from theme tokens, never from a hardcoded palette", () => {
    const rec = recordingTheme();
    renderBar(0.6, 10, "block", rec.theme);
    expect(rec.tokens().sort()).toEqual(["dim", "error", "success", "warning"]);
  });

  it("interpolates per cell on a truecolor theme", () => {
    const { theme } = recordingTheme({ colorMode: "truecolor" });
    const out = renderBar(1, 10, "block", theme);
    const colours = new Set(out.match(/38;2;\d+;\d+;\d+/g) ?? []);
    expect(colours.size).toBeGreaterThan(4);
  });

  it("uses discrete theme colours on a 256-colour theme", () => {
    const rec = recordingTheme({ colorMode: "256color" });
    const out = renderBar(1, 10, "block", rec.theme);
    // No interpolated truecolor sequences; every cell went through theme.fg.
    expect(out).not.toMatch(/38;2;/);
    expect(rec.calls().filter(([, text]) => text !== "").length).toBeGreaterThan(0);
  });

  it("clamps out-of-range fills instead of throwing", () => {
    const { theme } = recordingTheme();
    expect(visibleWidth(renderBar(-1, 6, "block", theme))).toBe(6);
    expect(visibleWidth(renderBar(9, 6, "block", theme))).toBe(6);
  });

  it("returns empty for a zero-width bar", () => {
    const { theme } = recordingTheme();
    expect(renderBar(0.5, 0, "block", theme)).toBe("");
  });

  it("falls back to block glyphs for an unknown style", () => {
    const { theme } = recordingTheme();
    expect(visibleWidth(renderBar(0.5, 8, "no-such-style", theme))).toBe(8);
  });
});
```

- [ ] **Step 6: Implement `extension/src/bars.ts`**

```ts
import type { ThemeLike } from "./intents";

/**
 * Glyph sets, mirroring internal/render/gradient.go. Edge[0] is the empty
 * sentinel; Edge[1..] are monotonically larger partial fills, giving the
 * leading cell sub-cell resolution.
 */
const STYLES: Record<string, { body: string; ghost: string; edge: string[] }> = {
  braille: { body: "⣿", ghost: "⣿", edge: Array.from("⠀⡀⡄⡆⡇⣇⣧⣷⣿") },
  block: { body: "█", ghost: "█", edge: Array.from(" ▏▎▍▌▋▊▉█") },
  line: { body: "━", ghost: "━", edge: Array.from(" ━") },
};

/**
 * The ramp anchors, as theme tokens rather than RGB. These are the semantic
 * equivalent of SmoothGradient's stops in internal/render/gradient.go, which
 * hardcodes grey to green to yellow to orange to red. The orange stop has no
 * theme slot, so the pi ramp has four anchors rather than five — the one
 * fidelity loss of going native, and a deliberate one.
 */
const RAMP: ReadonlyArray<readonly [number, string]> = [
  [0.0, "dim"],
  [0.3, "success"],
  [0.5, "warning"],
  [1.0, "error"],
];

interface RGB { r: number; g: number; b: number }

const CUBE = [0, 95, 135, 175, 215, 255];

/**
 * Recover RGB from a theme's foreground SGR prefix. pi builds these with
 * fgAnsi(value, mode) (theme.ts), which emits 38;2;r;g;b on truecolor themes
 * and 38;5;N on 256-colour ones, so both forms are parseable. Returns
 * undefined for anything else, which pushes the caller onto the discrete path.
 */
export function parseFgAnsi(ansi: string): RGB | undefined {
  const truecolor = /38;2;(\d+);(\d+);(\d+)/.exec(ansi);
  if (truecolor) {
    return { r: +truecolor[1]!, g: +truecolor[2]!, b: +truecolor[3]! };
  }
  const indexed = /38;5;(\d+)/.exec(ansi);
  if (!indexed) return undefined;
  const n = +indexed[1]!;
  if (n >= 232) {
    const v = 8 + (n - 232) * 10;
    return { r: v, g: v, b: v };
  }
  if (n >= 16) {
    const i = n - 16;
    return { r: CUBE[Math.floor(i / 36)]!, g: CUBE[Math.floor(i / 6) % 6]!, b: CUBE[i % 6]! };
  }
  const base = n % 8;
  const bright = n >= 8 ? 255 : 170;
  return { r: base & 1 ? bright : 0, g: base & 2 ? bright : 0, b: base & 4 ? bright : 0 };
}

function lerp(a: number, b: number, t: number): number {
  return Math.max(0, Math.min(255, Math.round(a + (b - a) * t)));
}

// The ghost track: unfilled cells mixed toward near-black with a faint violet
// bias, matching internal/render/gradient.go's shadow and shadowMix.
const SHADOW: RGB = { r: 22, g: 18, b: 28 };
const SHADOW_MIX = 0.83;

function darken(c: RGB): RGB {
  return {
    r: lerp(c.r, SHADOW.r, SHADOW_MIX),
    g: lerp(c.g, SHADOW.g, SHADOW_MIX),
    b: lerp(c.b, SHADOW.b, SHADOW_MIX),
  };
}

function tokenAt(t: number): string {
  let token = RAMP[0]![1];
  for (const [stop, name] of RAMP) {
    if (t >= stop) token = name;
  }
  return token;
}

function sampleRamp(t: number, anchors: Array<[number, RGB]>): RGB {
  if (t <= anchors[0]![0]) return anchors[0]![1];
  const last = anchors[anchors.length - 1]!;
  if (t >= last[0]) return last[1];
  for (let i = 0; i < anchors.length - 1; i++) {
    const [ta, ca] = anchors[i]!;
    const [tb, cb] = anchors[i + 1]!;
    if (t <= tb) {
      const local = (t - ta) / (tb - ta);
      return { r: lerp(ca.r, cb.r, local), g: lerp(ca.g, cb.g, local), b: lerp(ca.b, cb.b, local) };
    }
  }
  return last[1];
}

function truecolor(c: RGB, glyph: string): string {
  return `\x1b[38;2;${c.r};${c.g};${c.b}m${glyph}\x1b[39m`;
}

/**
 * Render a width-`cells` bar at `fill` (a fraction in [0,1]).
 *
 * On a truecolor theme the ramp anchors are parsed back out of
 * theme.getFgAnsi and interpolated per cell, reproducing the smooth sweep of
 * the Go renderer in the user's own colours. On a 256-colour theme
 * interpolation would land on cube indices the theme never chose, so each cell
 * instead goes through theme.fg with the nearest anchor's token — coarser, but
 * every colour on screen is one the theme actually declares.
 */
export function renderBar(fill: number, cells: number, style: string, theme: ThemeLike): string {
  if (cells <= 0) return "";
  const clamped = Math.max(0, Math.min(1, Number.isFinite(fill) ? fill : 0));
  const set = STYLES[style] ?? STYLES.block!;
  const edgeSteps = set.edge.length - 1;
  const filled = clamped * cells;
  const whole = Math.floor(filled);
  const partial = filled - whole;

  let anchors: Array<[number, RGB]> | undefined;
  if (theme.getColorMode() === "truecolor") {
    const parsed: Array<[number, RGB]> = [];
    for (const [stop, token] of RAMP) {
      let rgb: RGB | undefined;
      try {
        rgb = parseFgAnsi(theme.getFgAnsi(token));
      } catch {
        rgb = undefined;
      }
      if (rgb) parsed.push([stop, rgb]);
    }
    if (parsed.length >= 2) anchors = parsed;
  }

  let out = "";
  for (let i = 0; i < cells; i++) {
    const t = (i + 0.5) / cells;
    let glyph: string;
    let lit = true;
    if (i < whole) {
      glyph = set.body;
    } else if (i === whole && partial > 0) {
      const idx = Math.min(edgeSteps, Math.max(1, Math.round(partial * edgeSteps)));
      glyph = set.edge[idx]!;
    } else {
      glyph = set.ghost;
      lit = false;
    }
    if (anchors) {
      const base = sampleRamp(t, anchors);
      out += truecolor(lit ? base : darken(base), glyph);
    } else {
      const token = lit ? tokenAt(t) : "dim";
      out += theme.fg(token, glyph);
    }
  }
  return out;
}
```

The braille edge glyphs above are placeholders written as escapes; before running, copy the exact `BrailleStyle.Edge`, `BlockStyle.Edge` and `LineStyle.Edge` rune strings out of `internal/render/gradient.go` so the two renderers draw the same shapes.

- [ ] **Step 7: Run the new suites**

Run:
```bash
cd /home/joe/Development/agent-statusline/extension && bun test src/intents.test.ts src/bars.test.ts 2>&1 | tail -15
```

Expected: all cases pass. The two that matter most are `derives its ramp from theme tokens` (asserting the exact token set `dim/error/success/warning`) and `routes every text span through theme.fg` (asserting no literal `\x1b[3Xm` in the output) — together they are the machine-checkable form of "no hardcoded colours".

- [ ] **Step 8: Add the no-hardcoded-colour grep as a test**

Append to `extension/src/intents.test.ts`:

```ts
import { readdirSync, readFileSync } from "node:fs";

describe("runtime sources", () => {
  it("contain no literal SGR colour codes outside the bar renderer", () => {
    const dir = import.meta.dir;
    const offenders: string[] = [];
    for (const f of readdirSync(dir)) {
      if (!f.endsWith(".ts") || f.endsWith(".test.ts") || f === "testing.ts" || f === "bars.ts") continue;
      const body = readFileSync(join(dir, f), "utf8");
      if (/\\u001b\[[0-9;]*m/.test(body)) offenders.push(f);
    }
    expect(offenders).toEqual([]);
  });

  it("import nothing from node_modules at runtime", () => {
    const dir = import.meta.dir;
    const offenders: string[] = [];
    for (const f of readdirSync(dir)) {
      if (!f.endsWith(".ts") || f.endsWith(".test.ts") || f === "testing.ts") continue;
      const body = readFileSync(join(dir, f), "utf8");
      for (const m of body.matchAll(/from\s+"([^"]+)"/g)) {
        const spec = m[1]!;
        if (!spec.startsWith(".") && !spec.startsWith("node:")) offenders.push(`${f}: ${spec}`);
      }
    }
    expect(offenders).toEqual([]);
  });
});
```

`bars.ts` is the single exemption from the first rule, and only for the OSC-8 and truecolor sequences it composes from parsed theme anchors. `intents.ts` composes OSC-8 too, so if that test flags it, narrow the pattern to `\[[0-9;]*m` (SGR) rather than all escapes — hyperlinks are structure, not colour.

- [ ] **Step 9: Run everything and commit**

Run:
```bash
cd /home/joe/Development/agent-statusline/extension && bun test 2>&1 | tail -8
```

Expected: `0 fail`.

```bash
cd /home/joe/Development/agent-statusline
git add -A
git commit -m "feat(extension): intent-to-theme mapping and a theme-derived bar

Colour now comes from the user's theme. Intents map onto real ThemeColor slots
(path->mdLink, meta->customMessageLabel, caution->bolded warning, since themes
expose no orange). The gradient bar re-derives its ramp by parsing theme.getFgAnsi
back to RGB and interpolating on truecolor themes, and falls back to discrete
theme.fg calls on 256-colour ones so every colour on screen is one the theme
declares. Two tests enforce the rule mechanically: no literal SGR outside the
bar renderer, and no node_modules import in any runtime source."
```

---
### Task 9: Layout and the activity stack

The port of `internal/layout/layout.go` and the width-and-clock-dependent half of `internal/widgets/activity.go`. This is where `render(width): string[]` actually gets its rows.

**Files:**
- Create: `extension/src/layout.ts`, `extension/src/activity.ts`, `extension/src/rows.ts`
- Create: `extension/src/layout.test.ts`, `extension/src/activity.test.ts`, `extension/src/rows.test.ts`
- Create: `extension/testdata/snapshot-full.json`, `extension/testdata/rows-120.golden`, `extension/testdata/rows-40.golden`

**Interfaces:**
- Consumes: `Snapshot`, `paint`, `ThemeLike` (Task 8); `visibleWidth`, `truncateEnd`, `truncateMiddle`, `padTo` (Task 7)
- Produces:
  - `export function composeRow(names: string[], snap: Snapshot, width: number, theme: ThemeLike): string`
  - `export function wrapRow(names: string[], snap: Snapshot, width: number, theme: ThemeLike): string[]`
  - `export function activityRows(snap: Snapshot, width: number, theme: ThemeLike, now: number, budget: number): string[]`
  - `export function spinnerFrame(now: number): string`
  - `export function renderRows(snap: Snapshot, width: number, theme: ThemeLike, now: number): string[]` — the single entry point the component calls

- [ ] **Step 1: Capture a real snapshot as the test fixture**

```bash
cd /home/joe/Development/agent-statusline
nix shell nixpkgs#go --command go build -o /tmp/agent-statusline-emit ./cmd/agent-statusline
CLAUDE_STATUSLINE_NOW=1748260800 CLAUDE_STATUSLINE_CONFIG=/dev/null \
  HOME=/tmp/claude-statusline-test-home \
  /tmp/agent-statusline-emit --emit json < internal/e2e/testdata/pi-full.json \
  > extension/testdata/snapshot-full.json
head -12 extension/testdata/snapshot-full.json
```

Expected: valid JSON beginning `{ "schema": 1, "mode": "pi", "asOfMs": 1748260800000,`. Using the binary's real output rather than a hand-written fixture is the point: the TypeScript suite then breaks the moment the Go schema moves.

- [ ] **Step 2: Write the failing layout test**

Create `extension/src/layout.test.ts`:

```ts
import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

import { visibleWidth as piVisibleWidth } from "@earendil-works/pi-tui";

import { composeRow, renderRows, wrapRow } from "./layout";
import { parseSnapshot, type Snapshot } from "./snapshot";
import { recordingTheme } from "./testing";

const snap = parseSnapshot(
  readFileSync(join(import.meta.dir, "..", "testdata", "snapshot-full.json"), "utf8"),
) as Snapshot;

const NOW = 1748260800000;

describe("composeRow", () => {
  it("joins visible widgets with the snapshot's separator", () => {
    const { theme } = recordingTheme();
    const row = composeRow(["model", "cwd"], snap, 200, theme);
    expect(row).toContain(snap.config.separator.trim());
  });

  it("skips widgets marked invisible and collapses their separators", () => {
    const { theme } = recordingTheme();
    const hidden: Snapshot = {
      ...snap,
      widgets: { ...snap.widgets, cwd: { visible: false } },
    };
    const row = composeRow(["model", "cwd", "git"], hidden, 200, theme);
    const seps = row.split(snap.config.separator).length - 1;
    expect(seps).toBe(1);
  });

  it("honours config.hide regardless of row membership", () => {
    const { theme } = recordingTheme();
    const hidden: Snapshot = { ...snap, config: { ...snap.config, hide: ["cwd"] } };
    expect(composeRow(["model", "cwd"], hidden, 200, theme)).not.toContain(snap.config.separator);
  });

  it("expands a flex marker to fill the remaining width", () => {
    const { theme } = recordingTheme();
    const row = composeRow(["model", snap.config.flexName, "cwd"], snap, 100, theme);
    expect(piVisibleWidth(row)).toBe(100);
  });

  it("drops the lowest-priority widget first on overflow", () => {
    const { theme } = recordingTheme();
    const names = ["model", "cwd", "git", "duration"];
    const wide = composeRow(names, snap, 300, theme);
    const narrow = composeRow(names, snap, 30, theme);
    expect(piVisibleWidth(narrow)).toBeLessThanOrEqual(30);
    expect(narrow.length).toBeLessThan(wide.length);
  });

  it("selects the compact span list below config.compactWidth", () => {
    const { theme } = recordingTheme();
    const wide = composeRow(["context"], snap, 200, theme);
    const narrow = composeRow(["context"], snap, snap.config.compactWidth - 1, theme);
    expect(narrow).not.toBe(wide);
    // The compact context form drops the bar, so it is strictly narrower.
    expect(piVisibleWidth(narrow)).toBeLessThan(piVisibleWidth(wide));
  });
});

describe("wrapRow", () => {
  it("packs segments across lines rather than dropping them", () => {
    const { theme } = recordingTheme();
    const lines = wrapRow(snap.config.row1, snap, 40, theme);
    expect(lines.length).toBeGreaterThan(1);
    for (const l of lines) expect(piVisibleWidth(l)).toBeLessThanOrEqual(40);
  });
});

describe("renderRows", () => {
  // The contract pi enforces: every returned line fits the width it pushed in.
  // Measured with pi-tui's own visibleWidth, not ours, so this is pi's verdict.
  for (const width of [20, 40, 60, 80, 120, 200]) {
    it(`returns only lines that fit at width ${width}`, () => {
      const { theme } = recordingTheme();
      for (const line of renderRows(snap, width, theme, NOW)) {
        expect([width, line, piVisibleWidth(line)]).toEqual([
          width, line, Math.min(piVisibleWidth(line), width),
        ]);
        expect(piVisibleWidth(line)).toBeLessThanOrEqual(width);
      }
    });
  }

  it("never exceeds config.maxLines", () => {
    const { theme } = recordingTheme();
    expect(renderRows(snap, 40, theme, NOW).length).toBeLessThanOrEqual(snap.config.maxLines);
  });

  it("returns no empty rows, which would leave blank gaps in the dock", () => {
    const { theme } = recordingTheme();
    for (const line of renderRows(snap, 120, theme, NOW)) {
      expect(line.trim().length).toBeGreaterThan(0);
    }
  });

  it("uses only theme tokens, so switching themes changes the output", () => {
    const a = recordingTheme();
    const b = recordingTheme({
      ansi: {
        text: "[38;2;0;0;0m", dim: "[38;2;1;1;1m", muted: "[38;2;2;2;2m",
        accent: "[38;2;3;3;3m", success: "[38;2;4;4;4m", warning: "[38;2;5;5;5m",
        error: "[38;2;6;6;6m", mdLink: "[38;2;7;7;7m", customMessageLabel: "[38;2;8;8;8m",
      },
    });
    const ra = renderRows(snap, 120, a.theme, NOW);
    const rb = renderRows(snap, 120, b.theme, NOW);
    // Same structure, different bar colours: the ramp came from the theme.
    expect(ra.length).toBe(rb.length);
    expect(ra.join("\n")).not.toBe(rb.join("\n"));
    expect(a.tokens().length).toBeGreaterThan(3);
  });

  it("survives a snapshot with no widgets at all", () => {
    const { theme } = recordingTheme();
    const empty: Snapshot = { ...snap, widgets: {}, activity: { ...snap.activity, tools: [], toolCounts: [], agents: [], todos: null } };
    expect(renderRows(empty, 80, theme, NOW)).toEqual([]);
  });
});
```

- [ ] **Step 3: Write the failing activity test**

Create `extension/src/activity.test.ts`:

```ts
import { describe, expect, it } from "bun:test";

import { visibleWidth as piVisibleWidth } from "@earendil-works/pi-tui";

import { activityRows, spinnerFrame } from "./activity";
import type { Snapshot } from "./snapshot";
import { recordingTheme } from "./testing";

const NOW = 1748260800000;

function snapWith(activity: Partial<Snapshot["activity"]>): Snapshot {
  return {
    schema: 1,
    mode: "pi",
    asOfMs: NOW,
    config: {
      barWidth: 10, compactWidth: 70, activityRows: 4, hideWhenIdle: true,
      padding: 0, refreshIntervalMs: 1000, maxLines: 6, separator: " | ",
      flexName: "flex", row1: [], row2: [], hide: [], dropPriority: [],
    },
    widgets: {},
    activity: {
      graces: { toolCompleteMs: 30000, agentCompleteMs: 30000, agentRunningStaleMs: 1800000, todoCompleteMs: 60000 },
      tools: [], toolCounts: [], agents: [], todos: null,
      ...activity,
    },
  };
}

describe("spinnerFrame", () => {
  it("advances once per second and cycles", () => {
    const frames = [0, 1000, 2000, 3000, 4000].map((d) => spinnerFrame(NOW + d));
    expect(new Set(frames.slice(0, 4)).size).toBe(4);
    expect(frames[4]).toBe(frames[0]);
  });

  it("keeps every frame the same cell width, so nothing after it shifts", () => {
    const widths = new Set([0, 1000, 2000, 3000].map((d) => piVisibleWidth(spinnerFrame(NOW + d))));
    expect(widths.size).toBe(1);
  });
});

describe("activityRows", () => {
  it("computes elapsed against the render clock, not the snapshot", () => {
    const { theme } = recordingTheme();
    const snap = snapWith({
      tools: [{ id: "c1", name: "bash", target: "bun test", state: "running", startedAtMs: NOW - 5000 }],
    });
    const at5 = activityRows(snap, 200, theme, NOW, 4).join("");
    const at90 = activityRows(snap, 200, theme, NOW + 85_000, 4).join("");
    expect(at5).toContain("5s");
    expect(at90).toContain("1m30s");
  });

  it("drops a finished tool once its grace window expires, with no new snapshot", () => {
    const { theme } = recordingTheme();
    const snap = snapWith({
      tools: [{ id: "c1", name: "read", state: "done", startedAtMs: NOW - 4000, endedAtMs: NOW - 1000 }],
    });
    expect(activityRows(snap, 200, theme, NOW, 4).length).toBe(1);
    expect(activityRows(snap, 200, theme, NOW + 40_000, 4).length).toBe(0);
  });

  it("drops an agent stuck running past the staleness cap", () => {
    const { theme } = recordingTheme();
    const snap = snapWith({ agents: [{ name: "Explore", startedAtMs: NOW - 3_600_000 }] });
    expect(activityRows(snap, 200, theme, NOW, 4).length).toBe(0);
  });

  it("shows 3 tools on a wide terminal and 2 on a normal one", () => {
    const { theme } = recordingTheme();
    const tools = ["a", "b", "c", "d"].map((id) => ({
      id, name: "bash", target: `command-${id}`, state: "running" as const, startedAtMs: NOW - 1000,
    }));
    const snap = snapWith({ tools });
    const wide = activityRows(snap, 130, theme, NOW, 4)[0]!;
    const normal = activityRows(snap, 80, theme, NOW, 4)[0]!;
    expect(wide.match(/command-/g)?.length).toBe(3);
    expect(normal.match(/command-/g)?.length).toBe(2);
  });

  it("middle-truncates each tool to its share of the line", () => {
    const { theme } = recordingTheme();
    const snap = snapWith({
      tools: [{
        id: "c1", name: "bash", state: "running", startedAtMs: NOW - 1000,
        target: "nix shell nixpkgs#go --command go test ./internal/widgets/ -run TestSpans -v",
      }],
    });
    const row = activityRows(snap, 60, theme, NOW, 4)[0]!;
    expect(piVisibleWidth(row)).toBeLessThanOrEqual(60);
    expect(row).toContain("…");
  });

  it("respects the row budget", () => {
    const { theme } = recordingTheme();
    const snap = snapWith({
      tools: [{ id: "c1", name: "bash", state: "running", startedAtMs: NOW }],
      toolCounts: [{ name: "read", count: 3 }],
      agents: [{ name: "Explore", startedAtMs: NOW }],
      todos: { subject: "ship it", done: 1, total: 3, allComplete: false, timestampMs: NOW },
    });
    expect(activityRows(snap, 200, theme, NOW, 4).length).toBe(4);
    expect(activityRows(snap, 200, theme, NOW, 2).length).toBe(2);
    expect(activityRows(snap, 200, theme, NOW, 0).length).toBe(0);
  });

  it("marks waiting tools with the queued glyph and dims them", () => {
    const rec = recordingTheme();
    const snap = snapWith({
      tools: [{ id: "q", name: "read", state: "waiting", emittedAtMs: NOW - 2000 }],
    });
    activityRows(snap, 200, rec.theme, NOW, 4);
    expect(rec.tokens()).toContain("dim");
  });

  it("tolerates null activity arrays from an older snapshot", () => {
    const { theme } = recordingTheme();
    const snap = snapWith({ tools: null, toolCounts: null, agents: null });
    expect(activityRows(snap, 200, theme, NOW, 4)).toEqual([]);
  });
});
```

- [ ] **Step 4: Run both to verify they fail**

Run:
```bash
cd /home/joe/Development/agent-statusline/extension && bun test src/layout.test.ts src/activity.test.ts 2>&1 | tail -12
```

Expected: FAIL — `Cannot find module './layout'` and `'./activity'`.

- [ ] **Step 5: Implement `extension/src/layout.ts`**

Port `internal/layout/layout.go` structurally. The pieces, in order:

1. `segments(names, snap, width, theme)` — for each name: skip if in `config.hide`; emit a flex marker for `config.flexName`; look up `snap.widgets[name]`, skip when absent or `visible === false`; choose `compact ?? spans` when `width > 0 && width < config.compactWidth`, else `spans`; `paint(...)` it; record its index in `config.dropPriority` (absent means `dropPriority.length + 1`).
2. `joinSegments(segs, width)` — a direct port of Go's, including the "separator only between two adjacent non-flex segments" rule and the flex-remainder distribution.
3. `composeRow` — loop: join, and while `width > 0 && visibleWidth(body) > width`, drop the segment with the lowest `drop` index; when none remain, `truncateEnd(body, width)`.
4. `wrapRow` — greedy packing at `separator` boundaries, ignoring flex, then `truncateEnd` any line still over budget.
5. `renderRows(snap, width, theme, now)` — the port of `main.go`'s budget:

```ts
export function renderRows(snap: Snapshot, width: number, theme: ThemeLike, now: number): string[] {
  const cfg = snap.config;
  const sep = cfg.separator;

  // Natural widths first: if both rows fit on one line together, merge them,
  // exactly as the ANSI renderer does.
  const row1 = composeRow(cfg.row1, snap, 0, theme);
  const row2 = composeRow(cfg.row2, snap, 0, theme);
  const w1 = visibleWidth(row1);
  const w2 = visibleWidth(row2);

  let dashboard: string[];
  if (w1 > 0 && w2 > 0 && w1 + visibleWidth(sep) + w2 <= width) {
    dashboard = [row1 + sep + row2];
  } else {
    // Wrap rather than truncate: the dashboard is higher priority than the
    // activity rows, so it takes extra lines and they get squeezed instead.
    dashboard = [...wrapRow(cfg.row1, snap, width, theme), ...wrapRow(cfg.row2, snap, width, theme)];
  }
  dashboard = dashboard.filter((l) => l.trim().length > 0).slice(0, cfg.maxLines);

  const budget = Math.min(cfg.maxLines - dashboard.length, cfg.activityRows);
  const activity = budget > 0 ? activityRows(snap, width, theme, now, budget) : [];

  const pad = cfg.padding > 0 ? " ".repeat(cfg.padding) : "";
  return [...dashboard, ...activity].map((l) => (pad ? pad + truncateEnd(l, width - cfg.padding) : l));
}
```

Note `composeRow(..., 0, ...)` for the natural-width pass: width 0 means "no budget, do not drop, do not compact", matching Go's `layout.Options{Width: 0}`.

- [ ] **Step 6: Implement `extension/src/activity.ts`**

Port the render-time half of `internal/widgets/activity.go`. The behaviour the tests pin:

- `SPINNER_FRAMES` copied verbatim from `runningSpinnerFrames`; `spinnerFrame(now)` indexes by `Math.floor(now / 1000) % frames.length` and right-pads every frame to the widest frame's `visibleWidth`, so the play button pulses in place and the per-tool truncation budget does not shift by a cell each second.
- Grace filtering against the render clock: a `done` tool survives while `now - endedAtMs <= graces.toolCompleteMs`; an agent with no `endedAtMs` survives while `now - startedAtMs <= graces.agentRunningStaleMs`; a finished agent while `now - endedAtMs <= graces.agentCompleteMs`; an all-complete todo while `now - timestampMs <= graces.todoCompleteMs`.
- Elapsed per state: `waiting` counts from `emittedAtMs`; `running` from `startedAtMs ?? emittedAtMs`; `done` is `endedAtMs - (startedAtMs ?? emittedAtMs)`. Formatted with a port of Go's `formatDuration` (`45s`, `5m30s`, `1h12m`, `2d3h`) and only shown at one second or more.
- Sorting most-recent-first with running and waiting pinned to `now`, then capping at 3 when `width >= 120` else 2, then `perTool = (width - (n-1) * visibleWidth("  ·  ")) / n`, then `truncateMiddle(label, perTool - visibleWidth(glyph + " " + elapsedText))` with a floor of 1.
- Intents rather than colours: `waiting` is `dim`, `done` is `ok`, `running` is `warn`, the elapsed counter is always `dim`, agent names are `meta`, agent descriptions and models are `dim`, todo lines are `accent` (or `ok` when all complete). Every one of these goes through `paint`, so the recording theme sees them.

Copy the glyph constants (`doneGlyph`, `todoGlyph`, `waitingGlyph`, the `  ·  ` separator, `runningSpinnerFrames`) verbatim out of the Go source rather than retyping them.

- [ ] **Step 7: Run the two suites**

Run:
```bash
cd /home/joe/Development/agent-statusline/extension && bun test src/layout.test.ts src/activity.test.ts 2>&1 | tail -15
```

Expected: all cases pass. Iterate on `layout.ts` and `activity.ts` until they do; do not relax an assertion, and in particular do not relax the `piVisibleWidth(line) <= width` family — those are pi's contract, not ours.

- [ ] **Step 8: Add golden rows**

Create `extension/src/rows.test.ts`:

```ts
import { describe, expect, it } from "bun:test";
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

import { renderRows } from "./layout";
import { parseSnapshot, type Snapshot } from "./snapshot";
import { recordingTheme } from "./testing";

const snap = parseSnapshot(
  readFileSync(join(import.meta.dir, "..", "testdata", "snapshot-full.json"), "utf8"),
) as Snapshot;

const NOW = 1748260800000;
const UPDATE = process.env.UPDATE_GOLDEN === "1";

// Visualise escapes the way internal/e2e/golden_test.go does, so a diff in
// either language reads the same way.
const visualise = (s: string) => s.replaceAll("", "<ESC>");

describe("golden rows", () => {
  for (const width of [40, 120]) {
    it(`matches testdata/rows-${width}.golden`, () => {
      const { theme } = recordingTheme();
      const got = renderRows(snap, width, theme, NOW).map(visualise).join("\n") + "\n";
      const path = join(import.meta.dir, "..", "testdata", `rows-${width}.golden`);
      if (UPDATE) {
        writeFileSync(path, got);
        return;
      }
      expect(got).toBe(readFileSync(path, "utf8"));
    });
  }
});
```

Generate and review:

```bash
cd /home/joe/Development/agent-statusline/extension
UPDATE_GOLDEN=1 bun test src/rows.test.ts
cat testdata/rows-120.golden
bun test src/rows.test.ts 2>&1 | tail -6
```

Confirm by eye before committing: the 120-column golden shows the model, cwd and git segments separated by the box-drawing separator; the recording theme's `<success>...</success>` style markers appear (proving colour came from tokens, not escapes); and no line exceeds 120 visible cells. Then `0 fail` on the re-run.

- [ ] **Step 9: Commit**

```bash
cd /home/joe/Development/agent-statusline
git add -A
git commit -m "feat(extension): row layout and the activity stack

A port of internal/layout plus the render-time half of internal/widgets/activity,
against pi's real contract: render(width) returns lines that fit, measured with
pi-tui's own visibleWidth at six widths. The spinner and every elapsed counter
are computed from the render clock rather than the snapshot, and the grace
windows are applied at paint time, so a 1 Hz repaint keeps them live without
respawning the binary. The fixture is the binary's actual --emit json output,
so the suite breaks the moment the Go schema moves."
```

---

### Task 10: The pi component, the tick, and the teardown

Replace `setStatus` with `setWidget` plus a blanking `setFooter`, drive the repaint, and tear it all down. This task also carries the integration tests that would have caught the bug this whole plan exists to fix.

**Files:**
- Create: `extension/src/component.ts`, `extension/src/component.test.ts`
- Create: `extension/src/pi-contract.test.ts`
- Modify: `extension/statusline.ts`
- Modify: `extension/statusline.test.ts`

**Interfaces:**
- Consumes: `renderRows` (Task 9), `parseSnapshot` (Task 8), `runBinary` and `buildPayload` (phase 1, unchanged)
- Produces:
  - `export const WIDGET_KEY = "agent-statusline"`, `export const FOOTER_OWNER = "agent-statusline"`
  - `export interface StatuslineHandle { setSnapshot(s: Snapshot): void; dispose(): void; }`
  - `export function installStatusline(ctx: PiUIContext, deps: InstallDeps): StatuslineHandle`
  - `extension/statusline.ts` no longer calls `ctx.ui.setStatus` with anything but `undefined`

#### The layout decision

- `ctx.ui.setFooter(factory)` whose `render()` returns `[]`. It exists for two reasons only: to blank pi's built-in footer, and to capture the `tui`, `theme` and `ReadonlyFooterDataProvider` handles. `footerData.onBranchChange` is subscribed here — pi already watches HEAD and the reftable with a 500 ms debounce (`footer-data-provider.ts:307-390`), so a branch switch refreshes the snapshot for free. This is exactly what `pi-powerline-footer` (`index.ts:3215-3236`) and tomsej's `pi-ext` (`custom-footer.ts:113-123`) do.
- **One** `ctx.ui.setWidget(WIDGET_KEY, factory, { placement: "belowEditor" })` renders the dashboard rows *and* the activity rows. Not two widgets: the line budget couples them (`activityBudget = maxLines - dashboard.length`) and two independent components cannot see each other's line count. `belowEditor` puts us between the input box and the footer (`interactive-mode.ts:886-894`), which is where Claude Code's statusline sits.
- Because we own the footer, other extensions' `setStatus` lines would otherwise vanish. The widget appends them as trailing rows, splitting on `[\r\n]` as `pi-ext` does (`custom-footer.ts:35-42`), excluding our own key. We are a guest in the footer, not its owner.

#### The tick strategy

Two timers at different cadences, because repainting and recomputing are different costs:

- **Paint tick**, inside the widget component: `setInterval(() => tui.requestRender(), config.refreshIntervalMs)` (default 1000 ms). `requestRender` sets a flag, schedules on `process.nextTick` and throttles to `MIN_RENDER_INTERVAL_MS = 16` (`pi-tui/src/tui.ts:311,343,772`), so a 1 Hz call is free. This is what unfreezes the spinner and every elapsed clock. `.unref?.()` so the timer can never hold the process open. Cleared in the component's `dispose()`, which pi calls when the key is re-set or cleared.
- **Data poll**, at extension scope: `setInterval(refresh, 5000)` spawning `agent-statusline --mode pi --emit json`. It exists for the values events do not announce — git porcelain, rate-limit countdown drift, the compaction counter. Event-driven refreshes (`session_start`, `session_info_changed`, `message_end`, `turn_end`, `agent_settled`, `tool_execution_start`, `tool_execution_end`, `onBranchChange`) are still what makes it feel immediate; the poll is the backstop. Also `.unref?.()`.

Teardown, in three places, so no timer outlives its session:

1. the widget component's `dispose()` clears the paint tick;
2. the footer component's `dispose()` unsubscribes `onBranchChange`;
3. `pi.on("session_shutdown")` clears the data poll, then calls `ctx.ui.setWidget(WIDGET_KEY, undefined)` and `ctx.ui.setFooter(undefined)`, which triggers 1 and 2.

`session_start` re-installs. Re-`setWidget` on the same key disposes the old component first (`interactive-mode.ts:2134-2174`), so a restart cannot leak either.

- [ ] **Step 1: Write the failing component test**

Create `extension/src/component.test.ts`:

```ts
import { describe, expect, it, jest, mock } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

import { installStatusline, WIDGET_KEY } from "./component";
import { parseSnapshot, type Snapshot } from "./snapshot";
import { recordingTheme } from "./testing";

const snap = parseSnapshot(
  readFileSync(join(import.meta.dir, "..", "testdata", "snapshot-full.json"), "utf8"),
) as Snapshot;

/** A pi UI double capturing the factories, so tests can mount them by hand. */
function fakeUI(extensionStatuses = new Map<string, string>()) {
  const widgets = new Map<string, { factory: any; options: any; component?: any }>();
  let footerComponent: any;
  const requestRender = mock(() => {});
  const tui = { requestRender };
  const { theme, tokens, calls } = recordingTheme();
  const branchListeners: Array<() => void> = [];
  const footerData = {
    getGitBranch: () => "main",
    getExtensionStatuses: () => extensionStatuses,
    getAvailableProviderCount: () => 1,
    onBranchChange: (cb: () => void) => {
      branchListeners.push(cb);
      return () => {
        const i = branchListeners.indexOf(cb);
        if (i >= 0) branchListeners.splice(i, 1);
      };
    },
  };
  const setStatusCalls: Array<[string, string | undefined]> = [];
  const ui = {
    setStatus(key: string, text: string | undefined) {
      setStatusCalls.push([key, text]);
    },
    setWidget(key: string, factory: any, options: any) {
      const prev = widgets.get(key);
      prev?.component?.dispose?.();
      if (factory === undefined) {
        widgets.delete(key);
        return;
      }
      widgets.set(key, { factory, options, component: factory(tui, theme) });
    },
    setFooter(factory: any) {
      footerComponent?.dispose?.();
      footerComponent = factory === undefined ? undefined : factory(tui, theme, footerData);
    },
    theme,
  };
  return {
    ctx: { mode: "tui", hasUI: true, ui, cwd: "/home/joe/p" },
    widgets, requestRender, tokens, calls, setStatusCalls,
    footer: () => footerComponent,
    branchChange: () => branchListeners.forEach((cb) => cb()),
    branchListenerCount: () => branchListeners.length,
  };
}

describe("installStatusline", () => {
  it("registers one belowEditor widget and blanks the footer", () => {
    const f = fakeUI();
    installStatusline(f.ctx as any, {});
    expect(f.widgets.has(WIDGET_KEY)).toBe(true);
    expect(f.widgets.get(WIDGET_KEY)!.options.placement).toBe("belowEditor");
    expect(f.footer()!.render(120)).toEqual([]);
  });

  it("never routes rows through setStatus", () => {
    const f = fakeUI();
    const h = installStatusline(f.ctx as any, {});
    h.setSnapshot(snap);
    f.widgets.get(WIDGET_KEY)!.component.render(120);
    for (const [, text] of f.setStatusCalls) {
      expect(text).toBeUndefined();
    }
  });

  it("does nothing outside TUI mode", () => {
    const f = fakeUI();
    installStatusline({ ...f.ctx, mode: "print", hasUI: false } as any, {});
    expect(f.widgets.size).toBe(0);
    expect(f.footer()).toBeUndefined();
  });

  it("renders nothing until a snapshot arrives", () => {
    const f = fakeUI();
    installStatusline(f.ctx as any, {});
    expect(f.widgets.get(WIDGET_KEY)!.component.render(120)).toEqual([]);
  });

  it("renders rows once a snapshot is set", () => {
    const f = fakeUI();
    const h = installStatusline(f.ctx as any, {});
    h.setSnapshot(snap);
    expect(f.widgets.get(WIDGET_KEY)!.component.render(120).length).toBeGreaterThan(0);
  });

  it("appends other extensions' status lines, which we displaced", () => {
    const f = fakeUI(new Map([["zz-other", "other line one\nother line two"], [WIDGET_KEY, "stale"]]));
    const h = installStatusline(f.ctx as any, {});
    h.setSnapshot(snap);
    const rows = f.widgets.get(WIDGET_KEY)!.component.render(200).join("\n");
    expect(rows).toContain("other line one");
    expect(rows).toContain("other line two");
    expect(rows).not.toContain("stale");
  });

  it("ticks requestRender at the snapshot's refresh interval", () => {
    jest.useFakeTimers();
    const f = fakeUI();
    const h = installStatusline(f.ctx as any, {});
    h.setSnapshot(snap);
    f.requestRender.mockClear();
    jest.advanceTimersByTime(5000);
    expect(f.requestRender).toHaveBeenCalledTimes(5);
    h.dispose();
    jest.useRealTimers();
  });

  it("re-arms the tick when the config's interval changes", () => {
    jest.useFakeTimers();
    const f = fakeUI();
    const h = installStatusline(f.ctx as any, {});
    h.setSnapshot({ ...snap, config: { ...snap.config, refreshIntervalMs: 500 } });
    f.requestRender.mockClear();
    jest.advanceTimersByTime(2000);
    expect(f.requestRender).toHaveBeenCalledTimes(4);
    h.dispose();
    jest.useRealTimers();
  });

  it("stops ticking after dispose and leaves no timers behind", () => {
    jest.useFakeTimers();
    const before = jest.getTimerCount();
    const f = fakeUI();
    const h = installStatusline(f.ctx as any, {});
    h.setSnapshot(snap);
    expect(jest.getTimerCount()).toBeGreaterThan(before);
    h.dispose();
    f.requestRender.mockClear();
    jest.advanceTimersByTime(10_000);
    expect(f.requestRender).not.toHaveBeenCalled();
    expect(jest.getTimerCount()).toBe(before);
    jest.useRealTimers();
  });

  it("removes the widget and restores the footer on dispose", () => {
    const f = fakeUI();
    const h = installStatusline(f.ctx as any, {});
    h.dispose();
    expect(f.widgets.has(WIDGET_KEY)).toBe(false);
    expect(f.footer()).toBeUndefined();
  });

  it("unsubscribes from branch changes on dispose", () => {
    const f = fakeUI();
    const h = installStatusline(f.ctx as any, {});
    expect(f.branchListenerCount()).toBe(1);
    h.dispose();
    expect(f.branchListenerCount()).toBe(0);
  });

  it("asks for a data refresh when the branch changes", () => {
    const onDataStale = mock(() => {});
    const f = fakeUI();
    installStatusline(f.ctx as any, { onDataStale });
    f.branchChange();
    expect(onDataStale).toHaveBeenCalled();
  });

  it("re-installing on the same key disposes the previous component", () => {
    jest.useFakeTimers();
    const f = fakeUI();
    const first = installStatusline(f.ctx as any, {});
    first.setSnapshot(snap);
    const count = jest.getTimerCount();
    const second = installStatusline(f.ctx as any, {});
    second.setSnapshot(snap);
    expect(jest.getTimerCount()).toBe(count);
    second.dispose();
    jest.useRealTimers();
  });

  it("keeps the last good snapshot when a render throws", () => {
    const f = fakeUI();
    const h = installStatusline(f.ctx as any, {});
    h.setSnapshot(snap);
    const good = f.widgets.get(WIDGET_KEY)!.component.render(120);
    h.setSnapshot({ ...snap, widgets: null as any });
    expect(f.widgets.get(WIDGET_KEY)!.component.render(120)).toEqual(good);
  });
});
```

- [ ] **Step 2: Write the pi-contract test — the one that would have caught the bug**

Create `extension/src/pi-contract.test.ts`. This is the heart of the task; read the comments as part of the plan.

```ts
import { describe, expect, it } from "bun:test";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

import { truncateToWidth, visibleWidth as piVisibleWidth } from "@earendil-works/pi-tui";

import { installStatusline, WIDGET_KEY } from "./component";
import { renderRows } from "./layout";
import { parseSnapshot, type Snapshot } from "./snapshot";
import { recordingTheme } from "./testing";

const snap = parseSnapshot(
  readFileSync(join(import.meta.dir, "..", "testdata", "snapshot-full.json"), "utf8"),
) as Snapshot;
const NOW = 1748260800000;

/**
 * A verbatim copy of pi's sanitizeStatusText, from
 * src/modes/interactive/components/footer.ts:13-19. Every string handed to
 * ctx.ui.setStatus goes through this before it reaches the screen.
 *
 * It is copied rather than imported because it is module-private in pi. The
 * "stays in step with pi" test below reads pi's real source off disk and fails
 * if this body ever stops matching.
 */
function sanitizeStatusText(text: string): string {
  return text
    .replace(/[\r\n\t]/g, " ")
    .replace(/ +/g, " ")
    .trim();
}

/** Locate pi's shipped source, preferring the bun build the user actually runs. */
function piSourceFile(rel: string): string | undefined {
  const roots = [
    process.env.PI_CODING_AGENT_SRC,
    join(import.meta.dir, "..", "node_modules", "@earendil-works", "pi-coding-agent"),
  ].filter(Boolean) as string[];
  for (const root of roots) {
    const p = join(root, "src", rel);
    if (existsSync(p)) return p;
  }
  return undefined;
}

describe("pi footer sink contract", () => {
  it("stays in step with pi's real sanitizeStatusText", () => {
    const file = piSourceFile(join("modes", "interactive", "components", "footer.ts"));
    if (!file) {
      throw new Error(
        "pi source not found; install the pi-coding-agent devDependency or set " +
          "PI_CODING_AGENT_SRC to the bun-built pi's package root",
      );
    }
    const body = readFileSync(file, "utf8");
    // Normalise whitespace so tabs-vs-spaces cannot flap the assertion.
    const norm = (s: string) => s.replace(/\s+/g, " ").trim();
    const upstream = /function sanitizeStatusText\(text: string\): string \{([^]*?)\n\}/.exec(body);
    expect(upstream).not.toBeNull();
    expect(norm(upstream![1]!)).toBe(
      norm(`
        // Replace newlines, tabs, carriage returns with space, then collapse multiple spaces
        return text
          .replace(/[\\r\\n\\t]/g, " ")
          .replace(/ +/g, " ")
          .trim();
      `),
    );
  });

  it("proves our rows genuinely cannot survive that sink", () => {
    // Non-vacuity guard. If our rows happened to be sanitize-stable, the
    // assertion below would pass for the wrong reason and the regression it
    // guards could return unnoticed. They are not stable: multi-row output is
    // newline-joined, and flex spacers are runs of spaces.
    const { theme } = recordingTheme();
    const rows = renderRows(snap, 120, theme, NOW);
    expect(rows.length).toBeGreaterThan(1);
    const joined = rows.join("\n");
    expect(sanitizeStatusText(joined)).not.toBe(joined);
    expect(sanitizeStatusText(joined).includes("\n")).toBe(false);
  });

  it("never hands a row to setStatus", () => {
    // THE regression test. Phase 1 shipped `ctx.ui.setStatus(KEY, rows.join("\n"))`,
    // and this fails loudly on that code: the sink is instrumented with pi's own
    // sanitiser, and any non-undefined value that the sanitiser would alter is a
    // row being fed to a single-line, space-collapsing sink.
    const observed: Array<string | undefined> = [];
    const { theme } = recordingTheme();
    const ui = {
      setStatus: (_k: string, text: string | undefined) => {
        observed.push(text === undefined ? undefined : sanitizeStatusText(text));
        if (text !== undefined && sanitizeStatusText(text) !== text) {
          throw new Error(
            `setStatus was given text that pi would mangle:\n${JSON.stringify(text.slice(0, 200))}`,
          );
        }
      },
      setWidget: (_k: string, factory: any) => {
        if (factory) factory({ requestRender() {} }, theme);
      },
      setFooter: (factory: any) => {
        if (factory) {
          factory({ requestRender() {} }, theme, {
            getGitBranch: () => "main",
            getExtensionStatuses: () => new Map(),
            getAvailableProviderCount: () => 1,
            onBranchChange: () => () => {},
          });
        }
      },
      theme,
    };
    const handle = installStatusline({ mode: "tui", hasUI: true, ui, cwd: "/x" } as any, {});
    handle.setSnapshot(snap);
    handle.dispose();
    expect(observed.every((v) => v === undefined)).toBe(true);
  });
});

describe("pi widget render contract", () => {
  // The widget path applies no sanitisation and no truncation
  // (interactive-mode.ts:2134-2174 mounts a factory component verbatim), so the
  // contract shifts entirely onto us: every line must already fit. pi-tui's own
  // functions are the authority on both width and truncation.
  for (const width of [24, 40, 60, 80, 100, 120, 160, 200]) {
    it(`emits width-legal lines at ${width}`, () => {
      const { theme } = recordingTheme();
      for (const line of renderRows(snap, width, theme, NOW)) {
        expect([width, line, piVisibleWidth(line)]).toEqual([width, line, piVisibleWidth(line)]);
        expect(piVisibleWidth(line)).toBeLessThanOrEqual(width);
        // Already-legal lines must be fixed points of pi's own truncator.
        expect(truncateToWidth(line, width)).toBe(line);
      }
    });
  }

  it("keeps rows as separate array entries, never newline-joined", () => {
    const { theme } = recordingTheme();
    for (const line of renderRows(snap, 120, theme, NOW)) {
      expect(line.includes("\n")).toBe(false);
      expect(line.includes("\r")).toBe(false);
      expect(line.includes("\t")).toBe(false);
    }
  });

  it("preserves flex padding, which the setStatus path destroyed", () => {
    const { theme } = recordingTheme();
    const flexed: Snapshot = {
      ...snap,
      config: { ...snap.config, row1: ["model", snap.config.flexName, "cwd"] },
    };
    const [line] = renderRows(flexed, 120, theme, NOW);
    expect(piVisibleWidth(line!)).toBe(120);
    expect(/ {4,}/.test(line!)).toBe(true);
    // And the proof this is exactly what the old path lost:
    expect(sanitizeStatusText(line!)).not.toBe(line!);
  });
});
```

- [ ] **Step 3: Run both to verify they fail**

Run:
```bash
cd /home/joe/Development/agent-statusline/extension && bun test src/component.test.ts src/pi-contract.test.ts 2>&1 | tail -12
```

Expected: FAIL — `Cannot find module './component'`.

- [ ] **Step 4: Implement `extension/src/component.ts`**

```ts
import { renderRows } from "./layout";
import type { ThemeLike } from "./intents";
import type { Snapshot } from "./snapshot";

export const WIDGET_KEY = "agent-statusline";

/** The pi surfaces this module touches, declared structurally (no imports). */
export interface PiTUI { requestRender(force?: boolean): void }
export interface PiFooterData {
  getExtensionStatuses(): ReadonlyMap<string, string>;
  onBranchChange(cb: () => void): () => void;
}
export interface PiUIContext {
  mode: string;
  hasUI: boolean;
  ui: {
    setStatus(key: string, text: string | undefined): void;
    setWidget(key: string, content: any, options?: { placement?: "aboveEditor" | "belowEditor" }): void;
    setFooter(factory: any): void;
    theme: ThemeLike;
  };
}

export interface InstallDeps {
  /** Called when something happened that the snapshot cannot know about. */
  onDataStale?: () => void;
  now?: () => number;
}

export interface StatuslineHandle {
  setSnapshot(s: Snapshot): void;
  dispose(): void;
}

const DEFAULT_INTERVAL_MS = 1000;

/**
 * Install the native statusline.
 *
 * setFooter returns [] purely to blank pi's built-in footer and to capture the
 * tui/theme/footerData handles — footerData is the only route to the git branch
 * and to other extensions' setStatus text. The drawing all happens in ONE
 * belowEditor widget, because the dashboard and activity rows share a single
 * line budget (activityBudget = maxLines - dashboard.length) and two independent
 * components cannot see each other's line count.
 *
 * Nothing is ever passed to setStatus except undefined: that sink collapses
 * newlines and runs of spaces (footer.ts:13-19), which destroys both our row
 * structure and our flex padding. src/pi-contract.test.ts enforces this.
 */
export function installStatusline(ctx: PiUIContext, deps: InstallDeps): StatuslineHandle {
  const noop: StatuslineHandle = { setSnapshot() {}, dispose() {} };
  if (ctx?.mode !== "tui" || !ctx.hasUI || !ctx.ui) return noop;

  const now = deps.now ?? (() => Date.now());
  let snapshot: Snapshot | undefined;
  let statuses: () => ReadonlyMap<string, string> = () => new Map();
  let tickHandle: ReturnType<typeof setInterval> | undefined;
  let tickMs = 0;
  let tuiRef: PiTUI | undefined;
  let unsubBranch: (() => void) | undefined;
  let disposed = false;

  const armTick = () => {
    const want = snapshot?.config.refreshIntervalMs || DEFAULT_INTERVAL_MS;
    if (!tuiRef || disposed || want === tickMs) return;
    if (tickHandle) clearInterval(tickHandle);
    tickMs = want;
    // requestRender coalesces on process.nextTick and throttles to 16 ms
    // (pi-tui/src/tui.ts:343), so a 1 Hz call costs nothing. This is what
    // unfreezes the spinner and the elapsed clocks between events.
    tickHandle = setInterval(() => tuiRef?.requestRender(), tickMs);
    tickHandle.unref?.();
  };

  // Clear any line a previous version of this extension left in the footer's
  // status map; @narumitw/pi-statusline does the same when it takes the footer.
  ctx.ui.setStatus(WIDGET_KEY, undefined);

  ctx.ui.setFooter((tui: PiTUI, _theme: ThemeLike, footerData: PiFooterData) => {
    tuiRef = tui;
    statuses = () => footerData.getExtensionStatuses();
    unsubBranch = footerData.onBranchChange(() => {
      deps.onDataStale?.();
      tui.requestRender();
    });
    armTick();
    return {
      invalidate() {},
      dispose() {
        unsubBranch?.();
        unsubBranch = undefined;
      },
      render(): string[] {
        return [];
      },
    };
  });

  ctx.ui.setWidget(
    WIDGET_KEY,
    (tui: PiTUI, theme: ThemeLike) => {
      tuiRef = tui;
      armTick();
      let lastGood: string[] = [];
      return {
        // pi calls invalidate() on theme change; nothing is memoised, so there
        // is nothing to drop — but a repaint is still wanted.
        invalidate() {
          tui.requestRender();
        },
        dispose() {
          if (tickHandle) clearInterval(tickHandle);
          tickHandle = undefined;
          tickMs = 0;
        },
        render(width: number): string[] {
          if (!snapshot) return [];
          try {
            lastGood = renderRows(snapshot, width, theme, now());
          } catch {
            // A statusline must never break the session: keep the last frame.
          }
          return [...lastGood, ...foreignStatusRows(width, theme)];
        },
      };
    },
    { placement: "belowEditor" },
  );

  /**
   * Re-render other extensions' setStatus lines. We took the footer, so pi no
   * longer draws them; dropping them would make us a bad neighbour. pi-ext does
   * the same, splitting on [\r\n] to recover the multi-row capability setStatus
   * denies (custom-footer.ts:35-42).
   */
  function foreignStatusRows(width: number, theme: ThemeLike): string[] {
    const out: string[] = [];
    const entries = Array.from(statuses().entries()).sort(([a], [b]) => a.localeCompare(b));
    for (const [key, text] of entries) {
      if (key === WIDGET_KEY || !text) continue;
      for (const line of text.split(/[\r\n]+/)) {
        if (line.trim()) out.push(truncateForeign(line, width, theme));
      }
    }
    return out;
  }

  return {
    setSnapshot(s: Snapshot) {
      snapshot = s;
      armTick();
      tuiRef?.requestRender();
    },
    dispose() {
      disposed = true;
      if (tickHandle) clearInterval(tickHandle);
      tickHandle = undefined;
      tickMs = 0;
      // Both calls trigger the components' own dispose(), which is where the
      // branch subscription is released.
      ctx.ui.setWidget(WIDGET_KEY, undefined);
      ctx.ui.setFooter(undefined);
      ctx.ui.setStatus(WIDGET_KEY, undefined);
    },
  };
}
```

Implement `truncateForeign` with `truncateEnd` from `./width` (dim it via `theme.fg("dim", ...)` only when the line carries no escapes of its own).

- [ ] **Step 5: Rewire `extension/statusline.ts`**

Keep `buildPayload`, `rateLimitsFromHeaders`, `sessionTotalsFromEntries`, `runBinary`, `newSessionState` and every event handler unchanged — phase 1's 27 tests cover them and must keep passing. Change only the output path and the lifecycle:

```ts
import { installStatusline } from "./src/component";
import { parseSnapshot } from "./src/snapshot";

const DATA_POLL_MS = 5000;

export default function (pi: any) {
  const state = newSessionState();
  state.version = readPiVersion();
  const binary = process.env.AGENT_STATUSLINE_BIN ?? "agent-statusline";
  let providerStartedAt = 0;
  let handle: { setSnapshot(s: any): void; dispose(): void } | undefined;
  let poll: ReturnType<typeof setInterval> | undefined;
  let inFlight = false;

  // ... every existing pi.on(...) handler, unchanged, still calling refresh(ctx)

  function install(ctx: any) {
    handle?.dispose();
    // onDataStale fires on a branch change, which pi already watches and
    // debounces for us (footer-data-provider.ts:307-390) — cheaper and more
    // responsive than polling git ourselves.
    handle = installStatusline(ctx, { onDataStale: () => void refresh(ctx) });
    if (poll) clearInterval(poll);
    // The data poll is a backstop for values no event announces: git porcelain,
    // rate-limit countdown drift, the compaction counter. The 1 Hz repaint that
    // keeps the spinner and clocks alive is a separate, process-free timer
    // inside the widget component.
    poll = setInterval(() => void refresh(ctx), DATA_POLL_MS);
    poll.unref?.();
  }

  function teardown() {
    if (poll) clearInterval(poll);
    poll = undefined;
    handle?.dispose();
    handle = undefined;
  }

  pi.on("session_shutdown", () => teardown());

  async function refresh(ctx: any) {
    if (!handle || inFlight) return;
    inFlight = true;
    try {
      if (!state.sessionId) syncSession(ctx);
      const payload = buildPayload(ctx, state);
      const result = await runBinary(binary, ["--mode", "pi", "--emit", "json"], JSON.stringify(payload));
      const snapshot = parseSnapshot(String(result.stdout ?? ""));
      // A malformed or newer-schema snapshot leaves the last good frame on
      // screen: a wrong statusline is worse than a stale one.
      if (snapshot) handle.setSnapshot(snapshot);
    } catch {
      // A failed refresh leaves the previous frame in place.
    } finally {
      inFlight = false;
    }
  }
}
```

`install(ctx)` is called from the existing `session_start` handler, before its `refresh(ctx)`. Delete the `STATUS_KEY` constant and the `ctx?.ui?.setStatus?.(STATUS_KEY, line)` call outright — that line is the bug.

- [ ] **Step 6: Extend the entrypoint test**

Append to `extension/statusline.test.ts`:

```ts
describe("extension lifecycle", () => {
  function fakePi() {
    const handlers = new Map<string, Function>();
    return {
      pi: { on: (e: string, h: Function) => handlers.set(e, h), exec: async () => ({ stdout: "" }) },
      fire: (e: string, ev: any, ctx: any) => handlers.get(e)?.(ev, ctx),
      has: (e: string) => handlers.has(e),
    };
  }

  it("registers a session_shutdown handler so timers cannot leak", () => {
    const f = fakePi();
    (extension as any)(f.pi);
    expect(f.has("session_shutdown")).toBe(true);
  });

  it("spawns the binary with --emit json, never bare --mode pi", async () => {
    // Guards the wire format: an ANSI blob would render as literal escapes now
    // that the component parses JSON.
    const src = readFileSync(join(import.meta.dir, "statusline.ts"), "utf8");
    expect(src).toContain('"--emit", "json"');
    expect(src).not.toMatch(/setStatus\?\.\(\s*STATUS_KEY/);
  });
});
```

- [ ] **Step 7: Run everything**

Run:
```bash
cd /home/joe/Development/agent-statusline/extension && bun test 2>&1 | tail -10
```

Expected: `0 fail`, with the 27 phase-1 tests plus width, intents, bars, layout, activity, rows, component and pi-contract suites all green.

- [ ] **Step 8: Prove the contract test actually catches the phase-1 bug**

This is a one-off verification, not a committed change. Temporarily reintroduce the bug and confirm the suite goes red:

```bash
cd /home/joe/Development/agent-statusline/extension
cp src/component.ts /tmp/component.ts.bak
python3 - <<'PY'
import re, pathlib
p = pathlib.Path("src/component.ts")
s = p.read_text()
s = s.replace(
    "return [...lastGood, ...foreignStatusRows(width, theme)];",
    "ctx.ui.setStatus(WIDGET_KEY, lastGood.join('\\n'));\n            return [...lastGood, ...foreignStatusRows(width, theme)];",
)
p.write_text(s)
PY
bun test src/pi-contract.test.ts 2>&1 | tail -12
cp /tmp/component.ts.bak src/component.ts
bun test src/pi-contract.test.ts 2>&1 | tail -6
```

Expected: the first run FAILS on `never hands a row to setStatus`, with the error naming the mangled text; the second run passes again. If the first run passes, the test is vacuous and must be fixed before this task is done.

- [ ] **Step 9: Commit**

```bash
cd /home/joe/Development/agent-statusline
git add -A
git commit -m "feat(extension): render natively through setWidget, not setStatus

setFooter returns [] to blank pi's built-in footer and to capture tui, theme
and footerData; one belowEditor widget draws the dashboard and activity rows
together, because they share one line budget. Two timers: a process-free 1 Hz
tui.requestRender() inside the component that unfreezes the spinner and the
elapsed clocks, and a 5 s data poll for values no event announces. Both are
unref'd and cleared on session_shutdown, which also clears the widget and
restores the footer.

pi-contract.test.ts is the regression gate the phase-1 goldens could not be:
it instruments setStatus with a verbatim copy of pi's sanitizeStatusText,
asserts we never hand it a row, proves non-vacuously that our rows would not
survive it, pins the copy against pi's real source on disk, and checks every
emitted line against pi-tui's own visibleWidth at eight widths."
```

---

### Task 11: Package, wire and prove it on the bun-built pi

**Files:**
- Modify: `flake.nix`, `README.md`
- Create: `extension/bun.nix` (generated by bun2nix)

**Interfaces:**
- Consumes: `bun.lock` (Task 6); `packages.pi-extension` from phase 1
- Produces:
  - `packages.pi-extension` copying `statusline.ts`, `package.json` and `src/`, with `passthru.piEntrypoint = "statusline.ts"` unchanged
  - `checks.pi-extension-tests` running `bun test` in the sandbox via bun2nix
  - `inputs.bun2nix` on the flake

- [ ] **Step 1: Extend the extension derivation to carry `src/`**

In `flake.nix`, replace the `pi-extension` copy body:

```nix
          pi-extension =
            (pkgs.runCommand "agent-statusline-pi-extension" { } ''
              mkdir -p $out/src
              cp ${./extension/statusline.ts} $out/statusline.ts
              cp ${./extension/package.json} $out/package.json
              cp ${./extension/src}/*.ts $out/src/
              # Tests and the theme double never ship: they import
              # devDependencies that will not exist beside the installed file.
              rm -f $out/src/*.test.ts $out/src/testing.ts
              test ! -e $out/src/testing.ts
            '').overrideAttrs
              (old: {
                passthru = (old.passthru or { }) // {
                  piEntrypoint = "statusline.ts";
                };
              });
```

- [ ] **Step 2: Add bun2nix and generate the lock derivation**

Add to `flake.nix` inputs:

```nix
    bun2nix = {
      url = "github:nix-community/bun2nix?ref=2.1.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
```

pinned to the same 2.1.0 `pi-nix` already uses, so the two flakes share a store path. Thread it through `forAllSystems` by importing nixpkgs with its overlay:

```nix
      forAllSystems =
        f:
        nixpkgs.lib.genAttrs systems (
          system:
          f {
            pkgs = import nixpkgs { inherit system; };
            bunPkgs = import nixpkgs {
              inherit system;
              overlays = [ bun2nix.overlays.default ];
            };
          }
        );
```

and update every `forAllSystems ({ pkgs }: ...)` call site to `forAllSystems ({ pkgs, bunPkgs }: ...)`.

Generate the lock derivation:

```bash
cd /home/joe/Development/agent-statusline/extension
nix run github:nix-community/bun2nix?ref=2.1.0 -- -o bun.nix
head -5 bun.nix
```

Expected: a Nix expression listing the two devDependencies and their transitive closure.

- [ ] **Step 3: Add the test check**

Inside `checks`:

```nix
          pi-extension-tests = bunPkgs.stdenv.mkDerivation {
            name = "agent-statusline-pi-extension-tests";
            src = ./extension;

            nativeBuildInputs = [
              bunPkgs.bun2nix.hook
              bunPkgs.bun
            ];

            bunDeps = bunPkgs.bun2nix.fetchBunDeps {
              bunNix = import ./extension/bun.nix;
            };

            dontRunLifecycleScripts = true;

            # The Go binary's real --emit json output is the fixture, and it is
            # checked in; the tests never spawn it, so no Go toolchain is needed.
            checkPhase = ''
              runHook preCheck
              export HOME=$TMPDIR
              bun test
              runHook postCheck
            '';
            doCheck = true;

            installPhase = "touch $out";
          };
```

- [ ] **Step 4: Run the flake check**

Run:
```bash
cd /home/joe/Development/agent-statusline && nix flake check 2>&1 | tail -20
```

Expected: `options-tests`, `agent-statusline-tests` and `pi-extension-tests` all build. If bun2nix reports a lock mismatch, re-run Step 2's generator — `bun.nix` is derived from `bun.lock` and must be regenerated whenever a dependency moves.

- [ ] **Step 5: Smoke-test against the Bun-built pi**

The APIs are argued to be identical between pi's npm and bun builds (see Global Constraints); this step turns that argument into an observation.

```bash
cd /home/joe/Development/pi-nix && nix build .#coding-agent-bun -o /tmp/pi-bun
cd /home/joe/Development/agent-statusline && nix build .#pi-extension -o /tmp/agent-statusline-ext
nix build .#agent-statusline -o /tmp/agent-statusline-bin

zmx new -d statusline-smoke
zmx send statusline-smoke "AGENT_STATUSLINE_BIN=/tmp/agent-statusline-bin/bin/agent-statusline \
  /tmp/pi-bun/bin/pi --extension /tmp/agent-statusline-ext/statusline.ts"
sleep 8
zmx capture statusline-smoke | tail -12
```

Confirm all five by eye:
1. **two or more distinct dashboard rows** appear below the input box — the sanitize bug would show one mashed row;
2. **column padding survives** — the flex gap is a run of spaces, not a single space;
3. the rows sit **between the input box and the bottom of the screen**, i.e. `belowEditor` placement took effect;
4. run `zmx capture` again after 3 seconds and confirm any running-tool spinner has **changed frame** and the session clock has **advanced** — that is the paint tick working;
5. type `/theme` and switch themes; the statusline **recolours** without a restart.

Then verify teardown:

```bash
zmx send statusline-smoke "/exit"
sleep 2
pgrep -af 'agent-statusline' || echo "no orphaned statusline processes"
zmx kill statusline-smoke
```

Expected: `no orphaned statusline processes`.

- [ ] **Step 6: Update the README**

Replace the Modes section with:

```markdown
## Modes and encodings

The binary reads a JSON payload on stdin and writes a statusline to stdout.

`--mode` selects the **input** decoder:

- `--mode claude` — Claude Code's statusline stdin JSON
- `--mode pi` — the payload emitted by this repo's pi extension
- omitted, or `--mode auto` — detected from the payload's `harness` field

`--emit` selects the **output** encoding:

- `--emit ansi` (default) — a rendered, coloured statusline. What Claude Code
  consumes, and the quickest way to eyeball what the binary computed.
- `--emit json` — a structured snapshot: per-widget spans carrying text and a
  semantic colour *intent*, bars carrying a fill fraction, activity items
  carrying absolute timestamps, plus the effective config. What the pi
  extension consumes, so that pi can do layout and colour in its own theme, at
  its own width, on its own clock.

`--emit ansi` is deliberately retained for `--mode pi`. It is the only rendering
available in pi's non-TUI modes, where `setWidget` and `setFooter` are no-ops,
and it is how you tell a Go bug from a TypeScript one: run the binary by hand
with a captured payload and see whether the numbers are right before blaming
the renderer. `internal/e2e/testdata/pi-*.golden` keep it under test.

## Development

    nix build .#agent-statusline
    nix flake check
    cd extension && bun test

Golden tests live in `internal/e2e/testdata/` and `extension/testdata/`. The
Claude-mode goldens are a regression gate and must never be regenerated
casually — if that output changes, that is the bug.
```

- [ ] **Step 7: Final full verification**

Run:
```bash
cd /home/joe/Development/agent-statusline \
  && nix shell nixpkgs#go --command go test ./... 2>&1 | tail -14 \
  && (cd extension && bun test 2>&1 | tail -6) \
  && nix flake check 2>&1 | tail -5 \
  && git status --porcelain internal/e2e/testdata/{idle,full,narrow}.golden
```

Expected: every Go package `ok`; bun `0 fail`; `nix flake check` clean; and the last command silent, proving the three Claude goldens were never touched across all eleven tasks.

- [ ] **Step 8: Commit**

```bash
cd /home/joe/Development/agent-statusline
nix fmt
git add -A
git commit -m "build: package the native pi extension, test it with bun2nix

The extension derivation now carries src/, minus tests and the theme double,
which import devDependencies that will not exist beside the installed file.
checks.pi-extension-tests runs bun test in the sandbox through bun2nix 2.1.0,
the same pin pi-nix uses. Verified end to end against packages.coding-agent-bun:
multi-row output, surviving flex padding, belowEditor placement, a live spinner,
a live theme switch, and no orphaned processes after /exit."
```

---

## Self-Review

**Spec coverage.** Every requirement is discharged. The structured schema (Task 5) represents all fifteen registry widgets as spans and all four activity widgets as typed items. Colour is a semantic intent throughout, mapped to pi theme tokens in `intents.ts` and never to RGB — enforced mechanically by the "no literal SGR outside `bars.ts`" test in Task 8. The two-row plus activity layout maps onto one `belowEditor` `setWidget` plus a blanking `setFooter`, the idiom `pi-powerline-footer` (`index.ts:2864-2928`, `3215-3236`) and `pi-ext` (`custom-footer.ts:113-123`) both converged on, verified by reading the packed npm sources. The tick strategy is two timers at two cadences with three teardown paths. The Claude path is untouched: no widget's `Render` signature changed, the goldens are re-verified after every task, and Task 11 Step 7 checks them one final time.

**The bun change, absorbed.** `bun test` replaces vitest on measured evidence rather than preference: the migration is one import line and all 27 phase-1 tests pass unchanged (Task 6 Step 1 records the baseline, Step 4 performs the swap). `package-lock.json` is deleted, `bun.lock` and `bunfig.toml` replace it, `bun2nix` 2.1.0 — the exact pin `pi-nix` already carries — provides `checks.pi-extension-tests`, and Task 11 Step 5 smoke-tests against `packages.coding-agent-bun`. The claim that the npm and bun pi builds behave identically is argued from `package-bun.nix`'s actual `preBuild` (which touches `models*.ts`, `agent.ts`, a `@ts-nocheck` on `tui/src/utils.ts`, a CHANGELOG URL and npm-to-bun script rewrites, and nothing in `footer.ts`, `theme.ts`, `extensions/types.ts` or the widget plumbing) and then verified empirically rather than left as an assumption.

**Widgets that do not port, and why.** Under pi the transcript is synthesised by `transcript.FromToolTiming`, which populates only `Tools`, `RecentTools` and `ToolCounts` — `Requests`, `Agents` and `Todos` stay empty by construction. So `burnRate` (needs per-request token deltas), `agents` and `todos` are permanently hidden under pi. That is not a porting failure; it is the sidecar's honest limit, and the widgets already hide rather than invent numbers. `pr` is likewise never populated — `PiStatus.PR` exists but the extension does not fill it, a phase-1 gap carried forward. Two fidelity losses are genuine and deliberate: the `caution` intent (the orange fourth step of the five-step context ramp) has no theme slot and becomes a bolded `warning`; and the smooth per-cell gradient degrades to four discrete theme colours on 256-colour themes, because interpolating there would land on cube indices the theme never chose. Both are documented in `intents.ts` and `bars.ts` at the point of decision.

**Keep or delete the ANSI pi path: keep.** Three reasons, all load-bearing. It is the only rendering available in pi's non-TUI modes, where `setWidget` and `setFooter` are stubbed (`runner.ts:246`, `rpc-mode.ts:195-205`). It is the triage tool that separates a Go bug from a TypeScript one — pipe a captured payload in by hand and read the numbers. And deleting it would delete `pi-full.golden` and `pi-narrow.golden`, the only Go-side regression gate on `DecodePi`. Its cost is zero: `--emit ansi` is the default and shares every code path up to the encoder. What *is* deleted is the `ctx.ui.setStatus(STATUS_KEY, line)` call — that one line was the bug.

**Why the integration test would have caught it.** Phase 1's goldens tested the binary, so a correct binary feeding a destructive sink looked green. `src/pi-contract.test.ts` tests the *seam* instead, in four layers: it instruments a fake `setStatus` with a verbatim copy of pi's `sanitizeStatusText` and fails if we ever hand it text that copy would alter; it proves non-vacuously that our rows would in fact be altered, so the first assertion cannot pass for the wrong reason; it reads pi's real `footer.ts` off disk and fails if the copied body drifts from upstream; and it checks every emitted line against pi-tui's *own* `visibleWidth` and `truncateToWidth` at eight widths, making pi the authority on its own contract rather than us. Task 10 Step 8 closes the loop by temporarily reintroducing the phase-1 bug and requiring the suite to go red.

**Sequencing risk.** Tasks 1 through 5 are Go-only and gated by the untouched goldens at every step; if any golden moves, the conversion was lossy and the fix is in the code. Tasks 6 through 10 are TypeScript-only and cannot affect Claude Code at all. Task 5 is the hinge: `extension/testdata/snapshot-full.json` is generated from the real binary in Task 9 Step 1, so if the Go schema and the TypeScript types ever disagree, the TypeScript suite breaks rather than the running statusline. The one manual judgement in the plan is Task 5 Step 9's four-point review of the generated JSON golden; everything downstream depends on that file being right, which is why it is reviewed by a human before it is committed.

**Known gap carried forward.** `internal/gitcache`'s branch lookup is redundant on the pi path now that `footerData.onBranchChange` drives refreshes, but the porcelain half (dirty, ahead, behind) is not, so the package stays as it is. Removing the redundant half is a follow-up, not a prerequisite.
