# agent-statusline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development (recommended) or executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract `claude-nix/packages/claude-statusline` into a standalone `agent-statusline` repo that renders the same statusline for both Claude Code and pi, from one config schema.

**Architecture:** The existing code already has the right shape — `input.Status` is a canonical struct and every widget reads `ctx.Status`. So we add a second decoder rather than restructuring: `DecodeClaude` (today's behaviour, unchanged) and `DecodePi` (new), dispatched by a `--mode` flag that autodetects. All harness translation lives in tested Go; the pi extension only serialises what pi natively knows. The Nix statusline options move into this repo's `lib/` so `claude-nix` and `pi-nix` share one schema.

**Tech Stack:** Go 1.22 (stdlib only, vendored deps), Nix flake, TypeScript (pi extension), garnix CI.

This is phase 1 of the design in `docs/plans/2026-08-18-pi-nix-agent-stack-design.md`. It lands entirely inside the existing Claude setup with no behaviour change.

## Global Constraints

- **Claude-mode output must remain byte-identical.** The golden tests in `internal/e2e/testdata/*.golden` are the regression gate. They are copied verbatim from `claude-nix` and must never be regenerated with `-update` during this phase.
- Go module path: `github.com/joegoldin/agent-statusline`.
- Binary name and `mainProgram`: `agent-statusline`.
- Cache root: `~/.cache/agent-statusline/`.
- Env var prefix: `AGENT_STATUSLINE_*`, with `CLAUDE_STATUSLINE_*` honoured as a fallback so the migration is seamless.
- Go stdlib only. The existing tree vendors its deps and sets `vendorHash = null`; keep that.
- Nix formatting: `nixfmt`. Go formatting: `gofmt`.
- No new runtime dependency may be added to the Claude code path.

---

### Task 1: Scaffold the repo with the source moved verbatim

Move the Go tree unchanged except for the module path, and prove the golden tests still pass. Nothing else changes in this task — it is the safety net every later task leans on.

**Files:**
- Create: `/home/joe/Development/agent-statusline/` (new git repo)
- Create: `flake.nix`, `.gitignore`, `README.md`, `LICENSE`
- Create: `package.nix`
- Move: all of `claude-nix/packages/claude-statusline/**` → repo root
- Modify: `go.mod` (module path), every `.go` file's import block
- Test: `internal/e2e/golden_test.go` (moved, content unchanged)

**Interfaces:**
- Consumes: nothing (first task)
- Produces: `packages.agent-statusline` (a derivation with `mainProgram = "agent-statusline"`), and `checks.agent-statusline-tests`

- [ ] **Step 1: Create the repo and copy the source**

```bash
mkdir -p /home/joe/Development/agent-statusline
cd /home/joe/Development/agent-statusline
git init -b main
cp -r /home/joe/Development/claude-nix/packages/claude-statusline/. .
rm -rf result result-*
mv cmd/claude-statusline cmd/agent-statusline
```

- [ ] **Step 2: Rewrite the module path**

```bash
cd /home/joe/Development/agent-statusline
OLD='github.com/joegoldin/claude-nix/packages/claude-statusline'
NEW='github.com/joegoldin/agent-statusline'
sed -i "s|^module $OLD|module $NEW|" go.mod
grep -rl "$OLD" --include='*.go' . | xargs sed -i "s|$OLD|$NEW|g"
gofmt -l .
```

Expected: `gofmt -l .` prints nothing, and `grep -r "claude-nix/packages" --include='*.go' .` finds no matches outside `vendor/`.

- [ ] **Step 3: Run the tests to verify the move preserved behaviour**

Run:
```bash
cd /home/joe/Development/agent-statusline && go test ./...
```

Expected: PASS for every package, including `internal/e2e`. If `TestGolden` fails here, the move was lossy — fix the move, never the golden file.

- [ ] **Step 4: Write `package.nix`**

```nix
{
  lib,
  buildGoModule,
}:
buildGoModule {
  pname = "agent-statusline";
  version = "0.2.0";

  src = lib.cleanSource ./.;

  vendorHash = null; # using vendored deps

  subPackages = [ "cmd/agent-statusline" ];

  ldflags = [
    "-s"
    "-w"
  ];

  meta = with lib; {
    description = "Statusline for terminal coding agents (Claude Code and pi)";
    license = licenses.mit;
    mainProgram = "agent-statusline";
    platforms = platforms.unix;
  };
}
```

- [ ] **Step 5: Write `flake.nix`**

```nix
{
  description = "Statusline for terminal coding agents (Claude Code and pi)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f { pkgs = import nixpkgs { inherit system; }; });
    in
    {
      packages = forAllSystems (
        { pkgs }:
        rec {
          agent-statusline = pkgs.callPackage ./package.nix { };
          default = agent-statusline;
        }
      );

      checks = forAllSystems (
        { pkgs }:
        {
          agent-statusline-tests =
            pkgs.runCommand "agent-statusline-tests"
              {
                nativeBuildInputs = [ pkgs.go ];
                src = ./.;
              }
              ''
                cp -r $src work && chmod -R u+w work && cd work
                export HOME=$TMPDIR GOCACHE=$TMPDIR/go-cache GOFLAGS=-mod=vendor
                go test ./...
                touch $out
              '';
        }
      );

      formatter = forAllSystems ({ pkgs }: pkgs.nixfmt-rfc-style);
    };
}
```

- [ ] **Step 6: Build and check**

Run:
```bash
cd /home/joe/Development/agent-statusline && nix build .#agent-statusline && ./result/bin/agent-statusline --help 2>&1 | head -3; nix flake check
```

Expected: the build succeeds, the binary exists at `result/bin/agent-statusline`, and `nix flake check` passes.

- [ ] **Step 7: Commit**

```bash
cd /home/joe/Development/agent-statusline
cat > .gitignore <<'EOF'
result
result-*
EOF
git add -A
git commit -m "feat: extract claude-statusline into a standalone agent-statusline repo

Source moved verbatim from claude-nix/packages/claude-statusline; the only
changes are the Go module path and the cmd/ directory name. Golden tests
pass unmodified, which is the gate proving the move was lossless."
```

---

### Task 2: Add `--mode` with autodetect, Claude path unchanged

Introduce the mode concept without changing any behaviour. Claude mode is still the only decoder that exists; `pi` mode returns a clear error until Task 3.

**Files:**
- Create: `internal/input/mode.go`
- Create: `internal/input/mode_test.go`
- Modify: `internal/input/input.go` (rename `Decode` → `DecodeClaude`, keep `Decode` as the dispatcher)
- Modify: `cmd/agent-statusline/main.go` (parse `--mode`)

**Interfaces:**
- Consumes: `input.Status` from Task 1
- Produces:
  - `input.Mode` — a `string` type with constants `input.ModeClaude = "claude"`, `input.ModePi = "pi"`, `input.ModeAuto = "auto"`
  - `func input.ParseMode(s string) (Mode, error)`
  - `func input.Detect(raw []byte) Mode`
  - `func input.DecodeClaude(r io.Reader) (Status, error)`
  - `func input.Decode(r io.Reader, m Mode) (Status, error)`

- [ ] **Step 1: Write the failing test**

Create `internal/input/mode_test.go`:

```go
package input

import (
	"strings"
	"testing"
)

func TestParseMode(t *testing.T) {
	cases := []struct {
		in      string
		want    Mode
		wantErr bool
	}{
		{"claude", ModeClaude, false},
		{"pi", ModePi, false},
		{"auto", ModeAuto, false},
		{"", ModeAuto, false},
		{"bogus", "", true},
	}
	for _, c := range cases {
		got, err := ParseMode(c.in)
		if c.wantErr {
			if err == nil {
				t.Errorf("ParseMode(%q): want error, got nil", c.in)
			}
			continue
		}
		if err != nil {
			t.Errorf("ParseMode(%q): unexpected error %v", c.in, err)
			continue
		}
		if got != c.want {
			t.Errorf("ParseMode(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}

func TestDetect(t *testing.T) {
	// pi payloads carry a "harness":"pi" discriminator.
	if got := Detect([]byte(`{"harness":"pi","cwd":"/x"}`)); got != ModePi {
		t.Errorf("Detect(pi payload) = %q, want %q", got, ModePi)
	}
	// Anything else is Claude Code, which has no discriminator.
	if got := Detect([]byte(`{"cwd":"/x","session_id":"a"}`)); got != ModeClaude {
		t.Errorf("Detect(claude payload) = %q, want %q", got, ModeClaude)
	}
	// Malformed input must not panic; default to claude.
	if got := Detect([]byte(`not json`)); got != ModeClaude {
		t.Errorf("Detect(garbage) = %q, want %q", got, ModeClaude)
	}
}

func TestDecodeAutoSelectsClaude(t *testing.T) {
	s, err := Decode(strings.NewReader(sampleJSON), ModeAuto)
	if err != nil {
		t.Fatalf("Decode: %v", err)
	}
	if s.SessionID != "abc-123" {
		t.Errorf("SessionID = %q, want %q", s.SessionID, "abc-123")
	}
}
```

`sampleJSON` already exists in `internal/input/input_test.go`, so it is in scope for this package.

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd /home/joe/Development/agent-statusline && go test ./internal/input/ -run 'TestParseMode|TestDetect|TestDecodeAuto' -v`

Expected: FAIL to compile — `undefined: Mode`, `undefined: ParseMode`, `undefined: Detect`.

- [ ] **Step 3: Write `internal/input/mode.go`**

```go
package input

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
)

// Mode selects which harness produced the stdin payload.
type Mode string

const (
	ModeClaude Mode = "claude"
	ModePi     Mode = "pi"
	// ModeAuto defers the choice to Detect.
	ModeAuto Mode = "auto"
)

// ParseMode converts a --mode flag value into a Mode. The empty string means
// auto, so an unset flag behaves like the documented default.
func ParseMode(s string) (Mode, error) {
	switch Mode(s) {
	case "", ModeAuto:
		return ModeAuto, nil
	case ModeClaude:
		return ModeClaude, nil
	case ModePi:
		return ModePi, nil
	}
	return "", fmt.Errorf("unknown mode %q (want claude, pi, or auto)", s)
}

// discriminator is the single field pi payloads set so Detect never has to
// guess from the shape of optional fields.
type discriminator struct {
	Harness string `json:"harness"`
}

// Detect infers the Mode from a raw payload. Claude Code's payload has no
// discriminator, so anything that is not explicitly pi is treated as Claude —
// including malformed input, which then fails in DecodeClaude with a useful
// error rather than here.
func Detect(raw []byte) Mode {
	var d discriminator
	if err := json.Unmarshal(raw, &d); err != nil {
		return ModeClaude
	}
	if Mode(d.Harness) == ModePi {
		return ModePi
	}
	return ModeClaude
}

// Decode reads r fully and decodes it according to m. ModeAuto detects first.
func Decode(r io.Reader, m Mode) (Status, error) {
	raw, err := io.ReadAll(r)
	if err != nil {
		return Status{}, err
	}
	if m == ModeAuto {
		m = Detect(raw)
	}
	switch m {
	case ModePi:
		return DecodePi(bytes.NewReader(raw))
	default:
		return DecodeClaude(bytes.NewReader(raw))
	}
}
```

- [ ] **Step 4: Rename the existing decoder in `internal/input/input.go`**

Replace the existing `Decode` function at the bottom of the file with:

```go
// DecodeClaude reads Claude Code's statusline stdin JSON into a Status.
func DecodeClaude(r io.Reader) (Status, error) {
	var s Status
	dec := json.NewDecoder(r)
	if err := dec.Decode(&s); err != nil {
		return s, err
	}
	return s, nil
}
```

- [ ] **Step 5: Add a temporary `DecodePi` stub so the package compiles**

Create `internal/input/pi.go`:

```go
package input

import (
	"errors"
	"io"
)

// DecodePi is implemented in Task 3.
func DecodePi(r io.Reader) (Status, error) {
	return Status{}, errors.New("pi mode not implemented")
}
```

- [ ] **Step 6: Fix the existing decode test**

In `internal/input/input_test.go`, change the call `Decode(strings.NewReader(sampleJSON))` to `DecodeClaude(strings.NewReader(sampleJSON))`.

- [ ] **Step 7: Wire `--mode` into main.go**

In `cmd/agent-statusline/main.go`, replace the `input.Decode(os.Stdin)` block with:

```go
	mode, err := input.ParseMode(flagValue("--mode"))
	if err != nil {
		debugLog("ParseMode: %v", err)
		os.Exit(0)
	}

	status, err := input.Decode(os.Stdin, mode)
	if err != nil {
		debugLog("input.Decode: %v", err)
		os.Exit(0)
	}
```

and add this helper near `debugLog`:

```go
// flagValue returns the value of a `--name value` or `--name=value` argument,
// or "" when absent. Hand-rolled rather than using the flag package so the
// `hook` subcommand keeps its own argument handling untouched.
func flagValue(name string) string {
	for i, a := range os.Args[1:] {
		if a == name && i+2 < len(os.Args) {
			return os.Args[i+2]
		}
		if strings.HasPrefix(a, name+"=") {
			return strings.TrimPrefix(a, name+"=")
		}
	}
	return ""
}
```

`strings` is already imported in main.go.

- [ ] **Step 8: Run all tests**

Run: `cd /home/joe/Development/agent-statusline && go test ./...`

Expected: PASS everywhere. `TestGolden` passing here proves `--mode` did not disturb the Claude path.

- [ ] **Step 9: Commit**

```bash
cd /home/joe/Development/agent-statusline
git add -A
git commit -m "feat: add --mode with autodetect, Claude path unchanged

Decode gains a Mode parameter; DecodeClaude is today's decoder under its
explicit name. pi payloads self-identify with harness:\"pi\" so detection
never has to infer from optional-field shape. Golden tests unchanged."
```

---

### Task 3: The pi input decoder

Translate what pi natively knows into the canonical `Status`. This is where the design's "Go owns translation" principle is realised.

**Files:**
- Modify: `internal/input/pi.go` (replace the Task 2 stub)
- Create: `internal/input/pi_test.go`

**Interfaces:**
- Consumes: `input.Status`, `input.ContextWindow`, `input.CurrentUsage`, `input.Cost`, `input.Model`, `input.Effort`, `input.Workspace` from Task 1; the `DecodePi` signature from Task 2
- Produces:
  - `type PiStatus struct` — the wire format the pi extension emits
  - `func input.DecodePi(r io.Reader) (Status, error)`
  - The pi extension in Task 8 must emit exactly the `PiStatus` JSON tags defined here

- [ ] **Step 1: Write the failing test**

Create `internal/input/pi_test.go`:

```go
package input

import (
	"strings"
	"testing"
)

const samplePiJSON = `{
  "harness": "pi",
  "cwd": "/home/joe/Development/pi-nix",
  "session_id": "pi-abc-123",
  "session_name": "fork-the-flake",
  "session_path": "/home/joe/.pi/agent/sessions/pi-abc-123.jsonl",
  "model": {"id": "gpt-5.6-sol", "display_name": "Sol"},
  "thinking_level": "xhigh",
  "context": {
    "window_size": 400000,
    "input_tokens": 120000,
    "output_tokens": 8000,
    "cache_read_tokens": 90000,
    "cache_creation_tokens": 4000
  },
  "cost_usd": 0.42,
  "duration_ms": 330000
}`

func TestDecodePi(t *testing.T) {
	s, err := DecodePi(strings.NewReader(samplePiJSON))
	if err != nil {
		t.Fatalf("DecodePi: %v", err)
	}
	if s.CWD != "/home/joe/Development/pi-nix" {
		t.Errorf("CWD = %q", s.CWD)
	}
	if s.SessionID != "pi-abc-123" || s.SessionName != "fork-the-flake" {
		t.Errorf("session = %q / %q", s.SessionID, s.SessionName)
	}
	if s.Model.ID != "gpt-5.6-sol" || s.Model.DisplayName != "Sol" {
		t.Errorf("model = %+v", s.Model)
	}
	if s.Workspace.CurrentDir != s.CWD {
		t.Errorf("Workspace.CurrentDir = %q, want %q", s.Workspace.CurrentDir, s.CWD)
	}
	if s.TranscriptPath != "/home/joe/.pi/agent/sessions/pi-abc-123.jsonl" {
		t.Errorf("TranscriptPath = %q", s.TranscriptPath)
	}
	if s.Effort == nil || s.Effort.Level != "xhigh" {
		t.Errorf("Effort = %+v", s.Effort)
	}
}

func TestDecodePiComputesContextPercentages(t *testing.T) {
	s, err := DecodePi(strings.NewReader(samplePiJSON))
	if err != nil {
		t.Fatalf("DecodePi: %v", err)
	}
	cw := s.ContextWindow
	if cw == nil {
		t.Fatal("ContextWindow is nil")
	}
	if cw.ContextWindowSize != 400000 {
		t.Errorf("ContextWindowSize = %d", cw.ContextWindowSize)
	}
	// Claude Code counts used context as input + cache_read + cache_creation,
	// excluding output. 120000+90000+4000 = 214000 of 400000 = 53.5%.
	if cw.UsedPercentage == nil || *cw.UsedPercentage < 53.4 || *cw.UsedPercentage > 53.6 {
		t.Errorf("UsedPercentage = %v, want ~53.5", cw.UsedPercentage)
	}
	if cw.RemainingPercentage == nil || *cw.RemainingPercentage < 46.4 || *cw.RemainingPercentage > 46.6 {
		t.Errorf("RemainingPercentage = %v, want ~46.5", cw.RemainingPercentage)
	}
	if cw.TotalInputTokens != 120000 || cw.TotalOutputTokens != 8000 {
		t.Errorf("totals = %d / %d", cw.TotalInputTokens, cw.TotalOutputTokens)
	}
	if cw.CurrentUsage == nil || cw.CurrentUsage.CacheReadInputTokens != 90000 {
		t.Errorf("CurrentUsage = %+v", cw.CurrentUsage)
	}
}

func TestDecodePiCost(t *testing.T) {
	s, err := DecodePi(strings.NewReader(samplePiJSON))
	if err != nil {
		t.Fatalf("DecodePi: %v", err)
	}
	if s.Cost == nil || s.Cost.TotalCostUSD != 0.42 {
		t.Errorf("Cost = %+v", s.Cost)
	}
	if s.Cost.TotalDurationMS != 330000 {
		t.Errorf("TotalDurationMS = %d", s.Cost.TotalDurationMS)
	}
}

func TestDecodePiZeroWindowDoesNotDivideByZero(t *testing.T) {
	raw := `{"harness":"pi","cwd":"/x","context":{"window_size":0,"input_tokens":5}}`
	s, err := DecodePi(strings.NewReader(raw))
	if err != nil {
		t.Fatalf("DecodePi: %v", err)
	}
	if s.ContextWindow == nil {
		t.Fatal("ContextWindow is nil")
	}
	if s.ContextWindow.UsedPercentage != nil {
		t.Errorf("UsedPercentage = %v, want nil when window size is 0", s.ContextWindow.UsedPercentage)
	}
}

func TestDecodePiOmitsRateLimitsWhenAbsent(t *testing.T) {
	s, err := DecodePi(strings.NewReader(samplePiJSON))
	if err != nil {
		t.Fatalf("DecodePi: %v", err)
	}
	if s.RateLimits != nil {
		t.Errorf("RateLimits = %+v, want nil on non-Anthropic auth", s.RateLimits)
	}
}

func TestDecodePiPassesThroughRateLimits(t *testing.T) {
	raw := `{"harness":"pi","cwd":"/x","rate_limits":{
	  "five_hour":{"used_percentage":12.5,"resets_at":1748260800}}}`
	s, err := DecodePi(strings.NewReader(raw))
	if err != nil {
		t.Fatalf("DecodePi: %v", err)
	}
	if s.RateLimits == nil || s.RateLimits.FiveHour == nil {
		t.Fatalf("RateLimits = %+v", s.RateLimits)
	}
	if s.RateLimits.FiveHour.UsedPercentage != 12.5 {
		t.Errorf("FiveHour.UsedPercentage = %v", s.RateLimits.FiveHour.UsedPercentage)
	}
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd /home/joe/Development/agent-statusline && go test ./internal/input/ -run TestDecodePi -v`

Expected: FAIL with `pi mode not implemented` on every subtest.

- [ ] **Step 3: Implement `internal/input/pi.go`**

```go
// PiStatus is the wire format the agent-statusline pi extension emits. It
// mirrors what pi natively exposes to an extension; every derived value
// (percentages, workspace fields) is computed here rather than in TypeScript,
// so translation stays under test.
package input

import (
	"encoding/json"
	"io"
)

type PiStatus struct {
	Harness       string      `json:"harness"`
	CWD           string      `json:"cwd"`
	SessionID     string      `json:"session_id"`
	SessionName   string      `json:"session_name"`
	SessionPath   string      `json:"session_path"`
	ProjectDir    string      `json:"project_dir"`
	Model         Model       `json:"model"`
	ThinkingLevel string      `json:"thinking_level"`
	Context       *PiContext  `json:"context"`
	CostUSD       *float64    `json:"cost_usd"`
	DurationMS    int64       `json:"duration_ms"`
	APIDurationMS int64       `json:"api_duration_ms"`
	RateLimits    *RateLimits `json:"rate_limits"`
	PR            *PR         `json:"pr"`
	Version       string      `json:"version"`
}

type PiContext struct {
	WindowSize          int `json:"window_size"`
	InputTokens         int `json:"input_tokens"`
	OutputTokens        int `json:"output_tokens"`
	CacheReadTokens     int `json:"cache_read_tokens"`
	CacheCreationTokens int `json:"cache_creation_tokens"`
}

// DecodePi reads the pi extension's JSON and projects it onto the canonical
// Status every widget already understands.
func DecodePi(r io.Reader) (Status, error) {
	var p PiStatus
	if err := json.NewDecoder(r).Decode(&p); err != nil {
		return Status{}, err
	}

	projectDir := p.ProjectDir
	if projectDir == "" {
		projectDir = p.CWD
	}

	s := Status{
		CWD:            p.CWD,
		SessionID:      p.SessionID,
		SessionName:    p.SessionName,
		TranscriptPath: p.SessionPath,
		Version:        p.Version,
		Model:          p.Model,
		Workspace: Workspace{
			CurrentDir: p.CWD,
			ProjectDir: projectDir,
		},
		RateLimits: p.RateLimits,
		PR:         p.PR,
	}

	if p.ThinkingLevel != "" {
		s.Effort = &Effort{Level: p.ThinkingLevel}
	}

	if p.CostUSD != nil || p.DurationMS != 0 {
		c := Cost{TotalDurationMS: p.DurationMS, TotalAPIDurationMS: p.APIDurationMS}
		if p.CostUSD != nil {
			c.TotalCostUSD = *p.CostUSD
		}
		s.Cost = &c
	}

	if p.Context != nil {
		s.ContextWindow = piContextWindow(*p.Context)
	}

	return s, nil
}

// piContextWindow mirrors Claude Code's accounting: used context is input plus
// both cache figures, and output tokens are excluded. Percentages stay nil when
// the window size is unknown so widgets hide rather than render a bogus 0%.
func piContextWindow(c PiContext) *ContextWindow {
	cw := &ContextWindow{
		ContextWindowSize: c.WindowSize,
		TotalInputTokens:  c.InputTokens,
		TotalOutputTokens: c.OutputTokens,
		CurrentUsage: &CurrentUsage{
			InputTokens:              c.InputTokens,
			OutputTokens:             c.OutputTokens,
			CacheReadInputTokens:     c.CacheReadTokens,
			CacheCreationInputTokens: c.CacheCreationTokens,
		},
	}
	if c.WindowSize > 0 {
		used := float64(c.InputTokens+c.CacheReadTokens+c.CacheCreationTokens) /
			float64(c.WindowSize) * 100
		remaining := 100 - used
		cw.UsedPercentage = &used
		cw.RemainingPercentage = &remaining
	}
	return cw
}
```

- [ ] **Step 4: Run the tests**

Run: `cd /home/joe/Development/agent-statusline && go test ./internal/input/ -v`

Expected: PASS, including all six `TestDecodePi*` cases.

- [ ] **Step 5: Run the full suite to confirm no Claude regression**

Run: `cd /home/joe/Development/agent-statusline && go test ./...`

Expected: PASS everywhere, `TestGolden` included.

- [ ] **Step 6: Commit**

```bash
cd /home/joe/Development/agent-statusline
git add -A
git commit -m "feat: decode pi statusline payloads into the canonical Status

Context percentages, workspace fields, and cost/duration are derived in Go
so the pi extension only has to serialise what pi natively exposes. Used
context follows Claude Code's accounting (input + both cache figures,
excluding output) so both harnesses report the same number."
```

---

### Task 4: Make the cost widget mode-aware

`cost` currently hides unless Anthropic rate limits show overage — correct for Claude Max, wrong for pi, where the auth is Codex/API-key/OpenRouter and cost is the primary meter.

**Files:**
- Modify: `internal/widgets/widget.go` (add `Mode` to `Context`)
- Modify: `internal/widgets/cost.go`
- Modify: `internal/widgets/cost_test.go`
- Modify: `cmd/agent-statusline/main.go` (populate `ctx.Mode`)

**Interfaces:**
- Consumes: `input.Mode` from Task 2
- Produces: `widgets.Context.Mode` — an `input.Mode` field, defaulting to `input.ModeClaude` when unset, so existing tests that build a bare `Context` keep Claude semantics

- [ ] **Step 1: Read the current cost widget and its test**

Run:
```bash
cd /home/joe/Development/agent-statusline && cat internal/widgets/cost.go internal/widgets/cost_test.go
```

You need the exact body of `inOverage` and the existing test names before editing. Do not skip this step — the following steps add to this file rather than replacing it wholesale.

- [ ] **Step 2: Write the failing test**

Append to `internal/widgets/cost_test.go`:

```go
func TestCostAlwaysVisibleInPiMode(t *testing.T) {
	cost := 1.23
	ctx := &Context{
		Mode: input.ModePi,
		Status: input.Status{
			Cost: &input.Cost{TotalCostUSD: cost},
			// No RateLimits: exactly the non-Anthropic case.
		},
	}
	text, visible := Cost{}.Render(ctx)
	if !visible {
		t.Fatal("cost widget hidden in pi mode; want visible")
	}
	if !strings.Contains(text, "1.23") {
		t.Errorf("cost text = %q, want it to contain 1.23", text)
	}
}

func TestCostStillGatedInClaudeMode(t *testing.T) {
	ctx := &Context{
		Mode: input.ModeClaude,
		Status: input.Status{
			Cost: &input.Cost{TotalCostUSD: 1.23},
			RateLimits: &input.RateLimits{
				FiveHour: &input.Window{UsedPercentage: 10},
			},
		},
	}
	if _, visible := Cost{}.Render(ctx); visible {
		t.Error("cost widget visible in claude mode below overage; want hidden")
	}
}

func TestCostHiddenWhenZeroInPiMode(t *testing.T) {
	ctx := &Context{
		Mode:   input.ModePi,
		Status: input.Status{Cost: &input.Cost{TotalCostUSD: 0}},
	}
	if _, visible := Cost{}.Render(ctx); visible {
		t.Error("cost widget visible with zero cost; want hidden")
	}
}
```

Ensure `strings` and the `input` package are imported in that test file.

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd /home/joe/Development/agent-statusline && go test ./internal/widgets/ -run TestCost -v`

Expected: FAIL to compile — `unknown field Mode in struct literal`.

- [ ] **Step 4: Add `Mode` to the widget Context**

In `internal/widgets/widget.go`, add to the `Context` struct (the struct lives in this package; add the field alongside `Status` and `Cfg`):

```go
	// Mode is the harness that produced Status. The zero value is
	// input.ModeClaude, so widgets keep Claude semantics unless told otherwise.
	Mode input.Mode
```

and add the `input` import if it is not already present.

- [ ] **Step 5: Mode-gate the cost widget**

In `internal/widgets/cost.go`, replace the overage guard with:

```go
	// Claude Max subscribers don't pay for usage inside their plan limits, so
	// in Claude mode cost only surfaces in overage territory. Under pi the auth
	// is Codex / API key / OpenRouter, where every token is billed and cost is
	// the primary meter — so it always shows.
	if ctx.Mode != input.ModePi && !inOverage(ctx.Status.RateLimits) {
		return "", false
	}
```

- [ ] **Step 6: Populate `ctx.Mode` in main.go**

In `cmd/agent-statusline/main.go`, the mode resolved in Task 2 may still be `ModeAuto` after `ParseMode`. Resolve it to a concrete mode and pass it through. Change the decode block to:

```go
	raw, err := io.ReadAll(os.Stdin)
	if err != nil {
		debugLog("read stdin: %v", err)
		os.Exit(0)
	}
	if mode == input.ModeAuto {
		mode = input.Detect(raw)
	}
	status, err := input.Decode(bytes.NewReader(raw), mode)
	if err != nil {
		debugLog("input.Decode: %v", err)
		os.Exit(0)
	}
```

add `"bytes"` and `"io"` to the import block, and add `Mode: mode,` to the `widgets.Context` literal.

- [ ] **Step 7: Run the tests**

Run: `cd /home/joe/Development/agent-statusline && go test ./...`

Expected: PASS. `TestGolden` must still pass — the Claude fixtures have no rate limits in overage, so `cost` stays hidden exactly as before.

- [ ] **Step 8: Commit**

```bash
cd /home/joe/Development/agent-statusline
git add -A
git commit -m "feat: show cost unconditionally in pi mode

The overage gate encodes a Claude Max assumption: usage inside plan limits
is free, so cost is noise until you exceed them. Under pi every token is
billed, so the gate applies to claude mode only. Context.Mode zero value is
claude, keeping existing callers and golden output unchanged."
```

---

### Task 5: pi golden tests

Lock in pi-mode rendering the same way Claude mode is locked in.

**Files:**
- Create: `internal/e2e/testdata/pi-full.json`, `pi-narrow.json`
- Create: `internal/e2e/testdata/pi-full.golden`, `pi-narrow.golden` (generated, then reviewed)
- Modify: `internal/e2e/golden_test.go`

**Interfaces:**
- Consumes: `PiStatus` JSON tags from Task 3; `--mode` from Task 2
- Produces: no Go API; a regression gate for pi rendering

- [ ] **Step 1: Add pi fixtures to the golden test**

In `internal/e2e/golden_test.go`, extend the `fixture` struct and table:

```go
type fixture struct {
	name  string
	width string
	mode  string // "" means no --mode flag, exercising autodetect
}

func TestGolden(t *testing.T) {
	tests := []fixture{
		{"idle", "80", ""},
		{"full", "120", ""},
		{"narrow", "40", ""},
		{"pi-full", "120", ""},
		{"pi-narrow", "40", ""},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			runGolden(t, tc)
		})
	}
}
```

and in `runGolden`, pass the flag through:

```go
	args := []string{}
	if tc.mode != "" {
		args = append(args, "--mode", tc.mode)
	}
	cmd := exec.Command(binPath, args...)
```

Leaving `mode` empty for the pi fixtures is deliberate: it proves autodetect routes on the `harness` discriminator.

- [ ] **Step 2: Create `internal/e2e/testdata/pi-full.json`**

```json
{
  "harness": "pi",
  "cwd": "/tmp/agent-statusline-test-home/project",
  "session_id": "pi-golden-1",
  "session_name": "golden",
  "session_path": "",
  "model": {"id": "gpt-5.6-sol", "display_name": "Sol"},
  "thinking_level": "xhigh",
  "context": {
    "window_size": 400000,
    "input_tokens": 120000,
    "output_tokens": 8000,
    "cache_read_tokens": 90000,
    "cache_creation_tokens": 4000
  },
  "cost_usd": 0.42,
  "duration_ms": 330000
}
```

`session_path` is empty so the transcript provider short-circuits and `activity` stays out of the golden — tool timing gets its own coverage in Task 6.

- [ ] **Step 3: Create `internal/e2e/testdata/pi-narrow.json`**

Same content as `pi-full.json`. The width difference is supplied by the fixture table, and having a second file keeps the golden pairs symmetrical with the Claude fixtures.

```json
{
  "harness": "pi",
  "cwd": "/tmp/agent-statusline-test-home/project",
  "session_id": "pi-golden-1",
  "session_name": "golden",
  "session_path": "",
  "model": {"id": "gpt-5.6-sol", "display_name": "Sol"},
  "thinking_level": "xhigh",
  "context": {
    "window_size": 400000,
    "input_tokens": 120000,
    "output_tokens": 8000,
    "cache_read_tokens": 90000,
    "cache_creation_tokens": 4000
  },
  "cost_usd": 0.42,
  "duration_ms": 330000
}
```

- [ ] **Step 4: Verify the new fixtures fail before goldens exist**

Run: `cd /home/joe/Development/agent-statusline && go test ./internal/e2e/ -run 'TestGolden/pi' -v`

Expected: FAIL — the `.golden` files do not exist yet.

- [ ] **Step 5: Generate only the pi goldens, then read them**

```bash
cd /home/joe/Development/agent-statusline
go test ./internal/e2e/ -run 'TestGolden/pi' -update
cat -A internal/e2e/testdata/pi-full.golden | head -20
```

Then confirm by eye, before committing: the model shows `Sol`, effort shows `xhigh`, context reads ~53.5%, and **cost is present** — cost appearing with no rate limits is the whole point of Task 4. If cost is missing, Task 4 is wrong; fix it rather than accepting the golden.

- [ ] **Step 6: Confirm the Claude goldens were untouched**

Run:
```bash
cd /home/joe/Development/agent-statusline && git diff --stat internal/e2e/testdata/
```

Expected: only `pi-full.golden` and `pi-narrow.golden` appear as new files. If `idle.golden`, `full.golden`, or `narrow.golden` show modifications, `-update` was run too broadly — restore them with `git checkout -- internal/e2e/testdata/idle.golden internal/e2e/testdata/full.golden internal/e2e/testdata/narrow.golden` and redo Step 5 with the `-run` filter.

- [ ] **Step 7: Run the full suite**

Run: `cd /home/joe/Development/agent-statusline && go test ./... && nix flake check`

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
cd /home/joe/Development/agent-statusline
git add -A
git commit -m "test: golden coverage for pi-mode rendering

Fixtures omit --mode so autodetect is exercised via the harness
discriminator. Claude goldens verified unmodified."
```

---

### Task 6: pi tool-timing via the `hook` subcommand

`activity` reads a per-session sidecar written by `agent-statusline hook`. Claude Code invokes it as a tool hook; pi has no hook system, so the extension calls the same subcommand from `tool_execution_*` events. This task makes the subcommand accept pi's argument shape.

**Files:**
- Modify: `cmd/agent-statusline/main.go` (`runToolHook`)
- Create: `cmd/agent-statusline/hook_pi_test.go`

**Interfaces:**
- Consumes: `toolclock.Entry` and `toolclock.Load` from Task 1
- Produces: CLI contract `agent-statusline hook --mode pi --session <id> --tool <name> --call-id <id> --event start|end|fail`, which the Task 8 extension shells out to

- [ ] **Step 1: Read the existing hook implementation**

Run:
```bash
cd /home/joe/Development/agent-statusline && sed -n '/func runToolHook/,/^}/p' cmd/agent-statusline/main.go && cat internal/toolclock/toolclock.go
```

You must know the exact `toolclock.Entry` fields and the existing sidecar write path before writing the pi branch. The pi branch writes the *same* sidecar format — only the input parsing differs.

- [ ] **Step 2: Write the failing test**

Create `cmd/agent-statusline/hook_pi_test.go`:

```go
package main

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/joegoldin/agent-statusline/internal/toolclock"
)

func TestPiHookRecordsStartAndEnd(t *testing.T) {
	cacheRoot := t.TempDir()
	t.Setenv("AGENT_STATUSLINE_CACHE_DIR", cacheRoot)

	sessionID := "pi-hook-1"

	if err := recordPiToolEvent(cacheRoot, piHookArgs{
		SessionID: sessionID,
		ToolName:  "bash",
		CallID:    "call-1",
		Event:     "start",
	}); err != nil {
		t.Fatalf("start: %v", err)
	}

	entries := toolclock.Load(cacheRoot, sessionID)
	e, ok := entries["call-1"]
	if !ok {
		t.Fatalf("no entry for call-1; got %v", entries)
	}
	if e.Name != "bash" {
		t.Errorf("Name = %q, want bash", e.Name)
	}
	if e.StartedAt == 0 {
		t.Error("StartedAt not recorded")
	}
	if e.EndedAt != 0 {
		t.Error("EndedAt set before the end event")
	}

	if err := recordPiToolEvent(cacheRoot, piHookArgs{
		SessionID: sessionID,
		ToolName:  "bash",
		CallID:    "call-1",
		Event:     "end",
	}); err != nil {
		t.Fatalf("end: %v", err)
	}

	entries = toolclock.Load(cacheRoot, sessionID)
	if entries["call-1"].EndedAt == 0 {
		t.Error("EndedAt not recorded after the end event")
	}
}

func TestPiHookRejectsMissingSession(t *testing.T) {
	err := recordPiToolEvent(t.TempDir(), piHookArgs{ToolName: "bash", Event: "start"})
	if err == nil {
		t.Fatal("want error when session id is empty")
	}
}

func TestPiHookIsWriteOnlyUnderCacheRoot(t *testing.T) {
	cacheRoot := t.TempDir()
	if err := recordPiToolEvent(cacheRoot, piHookArgs{
		SessionID: "s", ToolName: "bash", CallID: "c", Event: "start",
	}); err != nil {
		t.Fatalf("record: %v", err)
	}
	// Everything the hook writes must live under cacheRoot.
	found := false
	_ = filepath.Walk(cacheRoot, func(p string, info os.FileInfo, err error) error {
		if err == nil && info != nil && !info.IsDir() {
			found = true
		}
		return nil
	})
	if !found {
		t.Error("hook wrote nothing under the cache root")
	}
}
```

If the fields on `toolclock.Entry` read in Step 1 are named differently from `Name`, `StartedAt`, and `EndedAt`, use the real names in this test and throughout Step 4 — do not rename the existing struct.

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd /home/joe/Development/agent-statusline && go test ./cmd/agent-statusline/ -run TestPiHook -v`

Expected: FAIL to compile — `undefined: recordPiToolEvent`, `undefined: piHookArgs`.

- [ ] **Step 4: Implement the pi hook branch**

Add to `cmd/agent-statusline/main.go`:

```go
// piHookArgs is the pi extension's tool-timing event. pi has no hook system,
// so the extension shells out to `agent-statusline hook --mode pi ...` from its
// tool_execution_* handlers, writing the same sidecar Claude Code's hooks feed.
type piHookArgs struct {
	SessionID string
	ToolName  string
	CallID    string
	Event     string // start | end | fail
}

func parsePiHookArgs() piHookArgs {
	return piHookArgs{
		SessionID: flagValue("--session"),
		ToolName:  flagValue("--tool"),
		CallID:    flagValue("--call-id"),
		Event:     flagValue("--event"),
	}
}

func recordPiToolEvent(cacheRoot string, a piHookArgs) error {
	if a.SessionID == "" {
		return fmt.Errorf("hook: --session is required")
	}
	if a.CallID == "" {
		return fmt.Errorf("hook: --call-id is required")
	}
	switch a.Event {
	case "start":
		return toolclock.RecordStart(cacheRoot, a.SessionID, a.CallID, a.ToolName, time.Now())
	case "end", "fail":
		return toolclock.RecordEnd(cacheRoot, a.SessionID, a.CallID, time.Now())
	}
	return fmt.Errorf("hook: unknown --event %q (want start, end, or fail)", a.Event)
}
```

If `toolclock` does not already export `RecordStart` and `RecordEnd`, extract them from the existing Claude hook path in `runToolHook` into `internal/toolclock/toolclock.go` with these signatures, and have the Claude path call them too. Both harnesses must write through one function so the sidecar format cannot diverge.

Then, at the top of `runToolHook`, add the pi branch:

```go
	if flagValue("--mode") == string(input.ModePi) {
		if err := recordPiToolEvent(userCacheDir(), parsePiHookArgs()); err != nil {
			debugLog("pi hook: %v", err)
		}
		return
	}
```

- [ ] **Step 5: Run the tests**

Run: `cd /home/joe/Development/agent-statusline && go test ./...`

Expected: PASS, including the existing Claude hook tests — the refactor into `RecordStart`/`RecordEnd` must not change their behaviour.

- [ ] **Step 6: Commit**

```bash
cd /home/joe/Development/agent-statusline
git add -A
git commit -m "feat: accept pi tool-timing events on the hook subcommand

pi has no hook system, so its extension shells out to the same subcommand
Claude Code's tool hooks call. Both paths now write the sidecar through
toolclock.RecordStart/RecordEnd so the format cannot diverge."
```

---

### Task 7: Shared Nix options in `lib/`

Move the statusline option schema out of `claude-nix` so `claude-nix` and `pi-nix` consume one definition.

**Files:**
- Create: `lib/default.nix`
- Create: `lib/options.nix`
- Create: `lib/render-config.nix`
- Modify: `flake.nix` (expose `lib`)
- Create: `tests/options-test.nix`
- Modify: `flake.nix` (add `checks.options-tests`)

**Interfaces:**
- Consumes: the `config.Config` JSON keys from Task 1 (`padding`, `refreshInterval`, `activityRows`, `hideWhenIdle`, `widgets.{row1,row2,hide}`, `gitCacheTtlSeconds`, `transcriptWindowSeconds`, `barWidth`, `sevenDayThreshold`, `tokenFormat`)
- Produces:
  - `lib.statuslineOptions` — an attrset of `mkOption`s, mountable under any namespace
  - `lib.renderConfig cfg` — takes the evaluated option values, returns a `pkgs.writeText` derivation holding the config JSON
  - Both consumed by `claude-nix` in Task 8 and by `pi-nix` in phase 2

- [ ] **Step 1: Read the current option definitions to copy verbatim**

Run:
```bash
cd /home/joe/Development/claude-nix && grep -n 'statusLine' -A 200 modules/home-manager.nix | sed -n '/statusLine = mkOption/,/^[0-9]*-    };/p' | head -200
```

Copy the descriptions, types, and defaults exactly. Divergence between the old and new schema is the main risk in this task.

- [ ] **Step 2: Write the failing test**

Create `tests/options-test.nix`:

```nix
# Evaluates the shared options with defaults and asserts the rendered config
# JSON matches the Go side's compiled-in defaults (internal/config/config.go
# Defaults()). If these drift, the Nix defaults silently stop matching Go's.
{ pkgs ? import <nixpkgs> { } }:
let
  lib = pkgs.lib;
  statuslineLib = import ../lib { inherit pkgs lib; };

  evaluated =
    (lib.evalModules {
      modules = [
        { options.statusLine = lib.mkOption { type = lib.types.submodule { options = statuslineLib.statuslineOptions; }; default = { }; }; }
      ];
    }).config.statusLine;

  rendered = builtins.fromJSON (builtins.readFile statuslineLib.renderConfig evaluated);

  expected = {
    padding = 0;
    refreshInterval = 1;
    activityRows = 4;
    hideWhenIdle = true;
    widgets = {
      row1 = [ "model" "cwd" "git" "duration" "usage5h" "usage7d" ];
      row2 = [ "context" "tokens" "burnRate" "voice" "compaction" "pr" "cost" ];
      hide = [ ];
    };
    gitCacheTtlSeconds = 5;
    transcriptWindowSeconds = 300;
    barWidth = 10;
    sevenDayThreshold = 50;
    tokenFormat = "compact";
  };
in
assert rendered == expected;
pkgs.runCommand "options-tests" { } "touch $out"
```

- [ ] **Step 3: Run it to verify it fails**

Run: `cd /home/joe/Development/agent-statusline && nix-instantiate --eval tests/options-test.nix 2>&1 | head -5`

Expected: an error that `../lib` does not exist.

- [ ] **Step 4: Write `lib/options.nix`**

Transcribe every option read in Step 1. The structure:

```nix
{ lib }:
let
  inherit (lib) mkOption types;
  widgetNames = [
    "model" "cwd" "git" "duration" "usage5h" "usage7d"
    "context" "contextBar" "tokens" "burnRate" "voice"
    "compaction" "pr" "cost" "effort" "sessionName" "activity"
  ];
in
{
  enable = lib.mkEnableOption "the agent statusline";

  package = mkOption {
    type = types.package;
    description = "The agent-statusline package to use.";
  };

  padding = mkOption {
    type = types.int;
    default = 0;
    description = "Left padding, in columns, applied to every rendered row.";
  };

  refreshInterval = mkOption {
    type = types.int;
    default = 1;
    description = "Seconds between statusline refreshes.";
  };

  activityRows = mkOption {
    type = types.int;
    default = 4;
    description = "Maximum number of tool-activity rows to render.";
  };

  hideWhenIdle = mkOption {
    type = types.bool;
    default = true;
    description = "Hide the activity rows entirely when no tool is running.";
  };

  widgets = {
    row1 = mkOption {
      type = types.listOf (types.enum widgetNames);
      default = [ "model" "cwd" "git" "duration" "usage5h" "usage7d" ];
      description = "Widgets on the first row, left to right.";
    };
    row2 = mkOption {
      type = types.listOf (types.enum widgetNames);
      default = [ "context" "tokens" "burnRate" "voice" "compaction" "pr" "cost" ];
      description = "Widgets on the second row, left to right.";
    };
    hide = mkOption {
      type = types.listOf (types.enum widgetNames);
      default = [ ];
      description = "Widgets to suppress regardless of row membership.";
    };
  };

  gitCacheTtlSeconds = mkOption {
    type = types.int;
    default = 5;
    description = "How long a git status result stays cached.";
  };

  transcriptWindowSeconds = mkOption {
    type = types.int;
    default = 300;
    description = "How far back the transcript parser looks for tool activity.";
  };

  barWidth = mkOption {
    type = types.int;
    default = 10;
    description = "Width, in columns, of the context and usage bars.";
  };

  sevenDayThreshold = mkOption {
    type = types.int;
    default = 50;
    description = "Percentage above which the seven-day usage widget appears.";
  };

  tokenFormat = mkOption {
    type = types.enum [ "compact" "full" ];
    default = "compact";
    description = "Token count rendering: compact (12.3k) or full (12345).";
  };
}
```

Reconcile against Step 1: if `claude-nix` has an option not listed here, add it; if a default differs, `claude-nix`'s value wins, and update `expected` in the test to match.

- [ ] **Step 5: Write `lib/render-config.nix`**

```nix
{ pkgs, lib }:
# Renders evaluated statusline options into the JSON the Go binary reads.
# Only the keys config.Config declares are emitted; `enable` and `package` are
# module-level concerns and deliberately excluded.
cfg:
pkgs.writeText "agent-statusline-config.json" (builtins.toJSON {
  inherit (cfg)
    padding
    refreshInterval
    activityRows
    hideWhenIdle
    gitCacheTtlSeconds
    transcriptWindowSeconds
    barWidth
    sevenDayThreshold
    tokenFormat
    ;
  widgets = {
    inherit (cfg.widgets) row1 row2 hide;
  };
})
```

- [ ] **Step 6: Write `lib/default.nix`**

```nix
{ pkgs, lib ? pkgs.lib }:
{
  statuslineOptions = import ./options.nix { inherit lib; };
  renderConfig = import ./render-config.nix { inherit pkgs lib; };
}
```

- [ ] **Step 7: Expose `lib` and the check from `flake.nix`**

Add to the flake outputs:

```nix
      lib = forAllSystems ({ pkgs }: import ./lib { inherit pkgs; });
```

and inside the `checks` attrset add:

```nix
          options-tests = import ./tests/options-test.nix { inherit pkgs; };
```

- [ ] **Step 8: Run the test**

Run: `cd /home/joe/Development/agent-statusline && nix flake check`

Expected: PASS. An assertion failure here means the Nix defaults and Go's `Defaults()` disagree — fix whichever is wrong, and remember Go is the reference for rendering behaviour.

- [ ] **Step 9: Commit**

```bash
cd /home/joe/Development/agent-statusline
git add -A
git commit -m "feat: expose the statusline option schema as flake lib

claude-nix and pi-nix mount statuslineOptions under their own namespace and
render through renderConfig, so there is one schema and one place to add a
widget. A check asserts the Nix defaults match Go's compiled-in Defaults()."
```

---

### Task 8: The pi extension

TypeScript that collects what pi knows, shells out to the binary, and renders into the footer. Kept deliberately thin — every derived value was computed in Go in Task 3.

**Files:**
- Create: `extension/package.json`
- Create: `extension/statusline.ts`
- Create: `extension/statusline.test.ts`
- Modify: `flake.nix` (add `packages.pi-extension`)

**Interfaces:**
- Consumes: the `PiStatus` JSON tags from Task 3; the hook CLI contract from Task 6
- Produces: `packages.pi-extension` — a derivation whose `passthru.piEntrypoint` points at the `.ts` file that pi-nix passes to `--extension`

- [ ] **Step 1: Verify the pi extension API before writing against it**

Run:
```bash
cd /home/joe/Development/pi-nix && grep -rn 'getContextUsage\|setStatus\|thinkingLevel\|tool_execution' --include='*.d.ts' --include='*.ts' . 2>/dev/null | head -20
```

If the fork has no bundled type definitions, fetch them from the installed package instead:
```bash
nix build /home/joe/Development/pi-nix#coding-agent && find ./result -name '*.d.ts' | head
```

Confirm the exact names of `ctx.getContextUsage()`, `ctx.ui.setStatus`, `ctx.model`, `ctx.thinkingLevel`, and the `tool_execution_start`/`tool_execution_end` payload fields. This is design assumption A5's neighbourhood — the plan's field names below are from the published docs and must be reconciled with the real types before proceeding.

- [ ] **Step 2: Write the failing test**

Create `extension/statusline.test.ts`:

```typescript
import { describe, it, expect } from "vitest";
import { buildPayload } from "./statusline";

describe("buildPayload", () => {
  const ctx = {
    cwd: "/home/joe/p",
    model: { id: "gpt-5.6-sol", displayName: "Sol" },
    thinkingLevel: "xhigh",
    getContextUsage: () => ({
      windowSize: 400000,
      inputTokens: 120000,
      outputTokens: 8000,
      cacheReadTokens: 90000,
      cacheCreationTokens: 4000,
    }),
  };

  it("stamps the harness discriminator so autodetect works", () => {
    expect(buildPayload(ctx, { sessionId: "s1", startedAt: 0, costUsd: 0 }).harness).toBe("pi");
  });

  it("maps model and thinking level onto the wire format", () => {
    const p = buildPayload(ctx, { sessionId: "s1", startedAt: 0, costUsd: 0 });
    expect(p.model).toEqual({ id: "gpt-5.6-sol", display_name: "Sol" });
    expect(p.thinking_level).toBe("xhigh");
  });

  it("passes context tokens through without deriving percentages", () => {
    const p = buildPayload(ctx, { sessionId: "s1", startedAt: 0, costUsd: 0 });
    expect(p.context).toEqual({
      window_size: 400000,
      input_tokens: 120000,
      output_tokens: 8000,
      cache_read_tokens: 90000,
      cache_creation_tokens: 4000,
    });
    expect(p).not.toHaveProperty("used_percentage");
  });

  it("computes elapsed duration from the session start", () => {
    const p = buildPayload(ctx, { sessionId: "s1", startedAt: 1000, costUsd: 0 }, 4000);
    expect(p.duration_ms).toBe(3000);
  });

  it("omits rate_limits when no Anthropic headers were seen", () => {
    const p = buildPayload(ctx, { sessionId: "s1", startedAt: 0, costUsd: 0 });
    expect(p.rate_limits).toBeUndefined();
  });

  it("tolerates a context usage call that throws", () => {
    const broken = { ...ctx, getContextUsage: () => { throw new Error("nope"); } };
    const p = buildPayload(broken, { sessionId: "s1", startedAt: 0, costUsd: 0 });
    expect(p.context).toBeUndefined();
    expect(p.harness).toBe("pi");
  });
});
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd /home/joe/Development/agent-statusline/extension && npx vitest run`

Expected: FAIL — `statusline.ts` does not exist.

- [ ] **Step 4: Implement `extension/statusline.ts`**

```typescript
// agent-statusline pi extension.
//
// Deliberately thin: it serialises only what pi natively exposes and lets the
// Go binary derive everything else (percentages, workspace fields, cost
// gating). Translation logic lives in Go because that is where the golden
// tests are.

export interface SessionState {
  sessionId: string;
  sessionName?: string;
  sessionPath?: string;
  startedAt: number;
  costUsd: number;
  apiDurationMs?: number;
  rateLimits?: unknown;
}

export interface PiPayload {
  harness: "pi";
  cwd: string;
  session_id: string;
  session_name?: string;
  session_path?: string;
  model?: { id: string; display_name: string };
  thinking_level?: string;
  context?: {
    window_size: number;
    input_tokens: number;
    output_tokens: number;
    cache_read_tokens: number;
    cache_creation_tokens: number;
  };
  cost_usd?: number;
  duration_ms: number;
  api_duration_ms?: number;
  rate_limits?: unknown;
}

export function buildPayload(ctx: any, state: SessionState, now = Date.now()): PiPayload {
  const payload: PiPayload = {
    harness: "pi",
    cwd: ctx.cwd,
    session_id: state.sessionId,
    session_name: state.sessionName,
    session_path: state.sessionPath,
    duration_ms: Math.max(0, now - state.startedAt),
    api_duration_ms: state.apiDurationMs,
    cost_usd: state.costUsd,
    rate_limits: state.rateLimits,
  };

  if (ctx.model) {
    payload.model = { id: ctx.model.id, display_name: ctx.model.displayName ?? ctx.model.id };
  }
  if (ctx.thinkingLevel) {
    payload.thinking_level = ctx.thinkingLevel;
  }

  // A statusline must never break the session, so every optional read is
  // best-effort: a throwing provider drops one widget, not the whole line.
  try {
    const u = ctx.getContextUsage?.();
    if (u) {
      payload.context = {
        window_size: u.windowSize ?? 0,
        input_tokens: u.inputTokens ?? 0,
        output_tokens: u.outputTokens ?? 0,
        cache_read_tokens: u.cacheReadTokens ?? 0,
        cache_creation_tokens: u.cacheCreationTokens ?? 0,
      };
    }
  } catch {
    // leave context undefined; the Go side hides those widgets
  }

  return payload;
}

export default function (pi: any) {
  const state: SessionState = { sessionId: "", startedAt: Date.now(), costUsd: 0 };
  const binary = process.env.AGENT_STATUSLINE_BIN ?? "agent-statusline";

  pi.on("session_start", (event: any, ctx: any) => {
    state.sessionId = event.sessionId ?? event.session_id ?? "";
    state.sessionPath = event.sessionPath ?? event.session_path;
    state.startedAt = Date.now();
    state.costUsd = 0;
    void refresh(ctx);
  });

  pi.on("turn_end", (_event: any, ctx: any) => void refresh(ctx));
  pi.on("agent_settled", (_event: any, ctx: any) => void refresh(ctx));

  // Anthropic surfaces rate limits in response headers. Absent on Codex,
  // OpenRouter, and API-key auth, in which case the widgets stay hidden.
  pi.on("after_provider_response", (event: any) => {
    const h = event.headers ?? {};
    const used = h["anthropic-ratelimit-unified-5h-used-percentage"];
    const reset = h["anthropic-ratelimit-unified-5h-reset"];
    if (used !== undefined) {
      state.rateLimits = {
        five_hour: { used_percentage: Number(used), resets_at: Number(reset ?? 0) },
      };
    }
  });

  // Tool timing goes through the same sidecar Claude Code's hooks write.
  const toolEvent = (event: any, phase: "start" | "end" | "fail") => {
    if (!state.sessionId) return;
    void pi.exec(binary, [
      "hook", "--mode", "pi",
      "--session", state.sessionId,
      "--tool", event.toolName ?? "",
      "--call-id", event.toolCallId ?? "",
      "--event", phase,
    ]);
  };
  pi.on("tool_execution_start", (e: any) => toolEvent(e, "start"));
  pi.on("tool_execution_end", (e: any) => toolEvent(e, "end"));

  async function refresh(ctx: any) {
    try {
      const payload = buildPayload(ctx, state);
      const result = await pi.exec(binary, ["--mode", "pi"], {
        stdin: JSON.stringify(payload),
      });
      const lines = String(result.stdout ?? "").replace(/\n$/, "");
      if (lines) ctx.ui.setStatus("agent-statusline", lines);
    } catch {
      // A failed refresh leaves the previous line in place.
    }
  }
}
```

Reconcile every `ctx.*` and `event.*` field name against the types confirmed in Step 1 before moving on.

- [ ] **Step 5: Write `extension/package.json`**

```json
{
  "name": "@joegoldin/agent-statusline-pi",
  "version": "0.2.0",
  "type": "module",
  "keywords": ["pi-package"],
  "pi": {
    "extensions": ["./statusline.ts"]
  },
  "devDependencies": {
    "vitest": "^2.0.0"
  },
  "scripts": {
    "test": "vitest run"
  }
}
```

- [ ] **Step 6: Run the tests**

Run: `cd /home/joe/Development/agent-statusline/extension && npm install && npx vitest run`

Expected: PASS — all six `buildPayload` cases.

- [ ] **Step 7: Package the extension in the flake**

Add to `packages` in `flake.nix`:

```nix
          pi-extension = pkgs.runCommand "agent-statusline-pi-extension" { } ''
            mkdir -p $out
            cp ${./extension/statusline.ts} $out/statusline.ts
            cp ${./extension/package.json} $out/package.json
          '';
```

then attach the entrypoint that `pi-nix` consumes:

```nix
          pi-extension = (pkgs.runCommand "agent-statusline-pi-extension" { } ''
            mkdir -p $out
            cp ${./extension/statusline.ts} $out/statusline.ts
            cp ${./extension/package.json} $out/package.json
          '').overrideAttrs (old: {
            passthru = (old.passthru or { }) // {
              piEntrypoint = "statusline.ts";
            };
          });
```

Use only the second form; the first is shown to make the diff legible.

- [ ] **Step 8: Build and verify**

Run:
```bash
cd /home/joe/Development/agent-statusline && nix build .#pi-extension && ls result/ && nix flake check
```

Expected: `statusline.ts` and `package.json` in `result/`, and `nix flake check` passes.

- [ ] **Step 9: Commit and push**

```bash
cd /home/joe/Development/agent-statusline
git add -A
git commit -m "feat: pi extension driving the statusline

Serialises only what pi natively exposes and shells out to the binary,
which derives everything else. Tool timing reuses the hook subcommand so
both harnesses feed one sidecar format. Every optional read is best-effort:
a statusline must never break the session."
gh repo create joegoldin/agent-statusline --private --source=. --remote=origin --push
```

---

### Task 9: Point `claude-nix` at the new repo

Remove the vendored copy and consume the flake, proving the extraction round-trips.

**Files:**
- Modify: `claude-nix/flake.nix` (add input, drop the local package and check)
- Modify: `claude-nix/modules/home-manager.nix` (mount shared options, use `renderConfig`)
- Modify: `claude-nix/lib/mkClaudeConfig.nix` (statusline config path)
- Delete: `claude-nix/packages/claude-statusline/`

**Interfaces:**
- Consumes: `lib.statuslineOptions`, `lib.renderConfig`, and `packages.agent-statusline` from Tasks 1 and 7
- Produces: `programs.claude-nix.statusLine` keeps its existing user-facing shape, so no dotfiles change is required

- [ ] **Step 1: Capture the current rendered statusline as the reference**

```bash
cd /home/joe/dotfiles
nix build .#homeConfigurations.$(whoami)@$(hostname).activationPackage 2>/dev/null || true
cat ~/.claude/statusline-config.json > /tmp/statusline-config-before.json
cat /tmp/statusline-config-before.json
```

This file is the contract. After this task it must be byte-identical.

- [ ] **Step 2: Add the input to `claude-nix/flake.nix`**

```nix
    agent-statusline = {
      url = "github:joegoldin/agent-statusline";
      inputs.nixpkgs.follows = "nixpkgs";
    };
```

- [ ] **Step 3: Replace the local package and check**

In `claude-nix/flake.nix`, delete the line `packages.claude-statusline = pkgs.callPackage ./packages/claude-statusline { };` and the `checks.claude-statusline-tests` block, then add:

```nix
        packages.agent-statusline = agent-statusline.packages.${pkgs.system}.agent-statusline;
```

- [ ] **Step 4: Mount the shared options**

In `claude-nix/modules/home-manager.nix`, replace the inline `statusLine` option definitions with:

```nix
    statusLine = mkOption {
      default = { };
      description = "Statusline rendered under Claude Code, via agent-statusline.";
      type = types.submodule {
        options = inputs.agent-statusline.lib.${pkgs.system}.statuslineOptions;
      };
    };
```

and replace the hand-built `statusLineConfigJSON` with:

```nix
  statusLineConfigJSON = inputs.agent-statusline.lib.${pkgs.system}.renderConfig cfg.statusLine;
```

Then update the command reference from `${statusLine.package}/bin/claude-statusline` to `${statusLine.package}/bin/agent-statusline`, and the `hook` invocations likewise.

- [ ] **Step 5: Delete the vendored copy**

```bash
cd /home/joe/Development/claude-nix && git rm -r --quiet packages/claude-statusline
```

- [ ] **Step 6: Build and diff the rendered config**

```bash
cd /home/joe/Development/claude-nix && nix flake check
cd /home/joe/dotfiles && nix build .#homeConfigurations.$(whoami)@$(hostname).activationPackage
diff <(cat /tmp/statusline-config-before.json) <(cat ./result/home-files/.claude/statusline-config.json)
```

Expected: `nix flake check` passes and `diff` prints nothing. Any difference means the option schema drifted during Task 7 — fix `lib/options.nix` in `agent-statusline`, not the diff.

- [ ] **Step 7: Verify the rendered line end-to-end**

```bash
cd /home/joe/Development/agent-statusline
nix build .#agent-statusline
./result/bin/agent-statusline < internal/e2e/testdata/full.json
./result/bin/agent-statusline < internal/e2e/testdata/pi-full.json
```

Expected: the first renders your familiar Claude line; the second renders a pi line showing `Sol`, `xhigh`, and a visible cost.

- [ ] **Step 8: Commit**

```bash
cd /home/joe/Development/claude-nix
git add -A
git commit -m "refactor: consume agent-statusline instead of vendoring it

The statusline now serves pi as well as Claude Code, so it lives in its own
repo; agent-skills already depends on claude-nix, which ruled out moving it
there. The option schema comes from agent-statusline's lib so claude-nix and
pi-nix cannot drift. Rendered statusline-config.json verified byte-identical."
```

---

## Self-Review

**Spec coverage.** This plan covers design §6 (agent-statusline) in full: the dual-mode decoder (Tasks 2–3), mode-gated cost (Task 4), the `hook` seam for activity (Task 6), the shared config schema (Task 7), and the pi extension (Task 8). Design §5's topology claim — that `agent-statusline` depends on nothing but nixpkgs — is satisfied by the Task 1 flake. Sections §7–§14 are phases 2–6 and are explicitly out of scope here.

**Deferred to phase 2, by design.** `pi-nix` consuming `lib.statuslineOptions` (§7's `statusline` option) cannot be written until `pi-nix` has its option module; Task 7 produces the interface it will consume.

**Known gaps carried forward.** Assumption A5 (`pr` via `gh`) is not implemented: `PiStatus` carries a `pr` field that the extension never populates, so the widget stays hidden under pi. That is the documented fallback, not an oversight. Task 8 Step 1 is the gate for reconciling the extension against pi's real type definitions.

**Type consistency.** `input.Mode` is used identically in Tasks 2, 4, and 6. `PiStatus` JSON tags in Task 3 match the `PiPayload` TypeScript interface in Task 8 field for field. `toolclock.RecordStart`/`RecordEnd` are introduced in Task 6 Step 4 with the signatures used in its test. `lib.statuslineOptions` and `lib.renderConfig` are produced in Task 7 and consumed in Task 9 under those exact names.
