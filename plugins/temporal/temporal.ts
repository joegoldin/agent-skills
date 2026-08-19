/**
 * Time-awareness extension for pi. Port of temporal.py, which serves the
 * three hook-based CLIs.
 *
 * Mapping:
 *   UserPromptSubmit  →  before_agent_start   (throttled by TEMPORAL_INTERVAL)
 *   SessionStart      →  session_start        (unthrottled, fires once)
 *   SessionStart:compact → session_compact    (post-compaction refresh)
 *
 * pi has no additionalContext, so the stamp is appended to the system
 * prompt, which pi rebuilds every turn. Between throttle windows the SAME
 * stamp string is re-appended rather than a fresh one: a per-turn timestamp
 * would invalidate the prompt cache on every request, which is precisely
 * what TEMPORAL_INTERVAL exists to prevent.
 *
 * Env:
 *   TEMPORAL_STATE_DIR  State directory. Default ~/.pi/.temporal, matching
 *                       the per-CLI convention in plugin.nix.
 *   TEMPORAL_INTERVAL   Min seconds between per-turn injects (default 300, 0=always).
 *   TEMPORAL_TTL_DAYS   Days before a stale session JSON is swept (default 7).
 */
import { mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

const INTERVAL_S = Number.parseInt(process.env.TEMPORAL_INTERVAL ?? "300", 10);
const TTL_S = Number.parseInt(process.env.TEMPORAL_TTL_DAYS ?? "7", 10) * 86400;
const DIR = process.env.TEMPORAL_STATE_DIR ?? join(homedir(), ".pi", ".temporal");

interface State {
  start_ms?: number;
  last_inject_ms?: number;
}

function pad(n: number): string {
  return String(n).padStart(2, "0");
}

function fmt(s: number): string {
  if (s < 60) return `${s}s`;
  if (s < 3600) return `${Math.floor(s / 60)}m${pad(s % 60)}s`;
  return `${Math.floor(s / 3600)}h${pad(Math.floor((s % 3600) / 60))}m`;
}

function sweep(): void {
  try {
    mkdirSync(DIR, { recursive: true });
    const now = Date.now();
    for (const f of readdirSync(DIR)) {
      if (!f.endsWith(".json")) continue;
      const p = join(DIR, f);
      try {
        if (now - statSync(p).mtimeMs > TTL_S * 1000) rmSync(p, { force: true });
      } catch {
        /* best effort, exactly as the Python */
      }
    }
  } catch {
    /* best effort */
  }
}

function statePath(sessionId: string): string {
  return join(DIR, `${sessionId || "nosession"}.json`);
}

function readState(p: string): State {
  try {
    return JSON.parse(readFileSync(p, "utf-8")) as State;
  } catch {
    return {};
  }
}

function writeState(p: string, s: State): void {
  try {
    mkdirSync(DIR, { recursive: true });
    writeFileSync(p, JSON.stringify(s));
  } catch {
    /* best effort */
  }
}

function stampFor(startMs: number, nowMs: number): string {
  const local = new Date(nowMs);
  const tz =
    new Intl.DateTimeFormat("en-US", { timeZoneName: "short" })
      .formatToParts(local)
      .find((p) => p.type === "timeZoneName")?.value ?? "";
  const utc = local.toISOString().replace(/\.\d{3}Z$/, "Z");
  const sessionS = Math.floor((nowMs - startMs) / 1000);
  return (
    `now=${pad(local.getHours())}:${pad(local.getMinutes())} ${tz} | ` +
    `utc=${utc} | unix_ms=${nowMs} | session=${fmt(sessionS)}`
  );
}

export default function temporal(pi: ExtensionAPI) {
  let sessionId = "";
  let pending: string | null = null;
  let lastEmitted = "";

  const load = (ctx: ExtensionContext): { path: string; state: State; nowMs: number } => {
    sessionId = ctx.sessionManager.getSessionId() ?? sessionId;
    const path = statePath(sessionId);
    const state = readState(path);
    const nowMs = Date.now();
    if (state.start_ms === undefined) state.start_ms = nowMs;
    return { path, state, nowMs };
  };

  pi.on("session_start", (_event, ctx) => {
    sweep();
    const { path, state, nowMs } = load(ctx);
    pending = `[⏱ ${stampFor(state.start_ms as number, nowMs)}]`;
    writeState(path, state);
  });

  pi.on("session_compact", (_event, ctx) => {
    const { path, state, nowMs } = load(ctx);
    pending = `[⏱ post-compaction time check — ${stampFor(state.start_ms as number, nowMs)}]`;
    writeState(path, state);
  });

  pi.on("before_agent_start", (event, ctx) => {
    const { path, state, nowMs } = load(ctx);

    if (pending !== null) {
      lastEmitted = pending;
      pending = null;
      state.last_inject_ms = nowMs;
      writeState(path, state);
    } else {
      const elapsed = Math.floor((nowMs - (state.last_inject_ms ?? 0)) / 1000);
      if (INTERVAL_S === 0 || elapsed >= INTERVAL_S) {
        lastEmitted = `[⏱ ${stampFor(state.start_ms as number, nowMs)}]`;
        state.last_inject_ms = nowMs;
        writeState(path, state);
      }
    }

    if (lastEmitted === "") return;
    return { systemPrompt: `${event.systemPrompt}\n\n${lastEmitted}` };
  });
}
