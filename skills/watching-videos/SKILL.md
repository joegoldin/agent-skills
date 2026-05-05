<!--
Pairs with the watchyt CLI in joegoldin/dotfiles, which is a customized port
of https://github.com/bradautomates/claude-video (MIT). This skill teaches the
agent the invocation contract for that CLI.
-->
# watching-videos — see + hear what's in a video

You don't have a native video input. This skill gives you one. The bundled `watchyt` CLI downloads the video, extracts frames as JPEGs, fetches a timestamped transcript (native captions first, `audiomemo transcribe` as fallback), and prints frame paths. You then `Read` each frame to see the images and combine them with the transcript to answer the user.

**Multi-target note:** On Claude, `Read` renders JPEGs directly as images in your context. On Gemini and Codex, image rendering may not be available in the same way — proceed transcript-only and tell the user that frame analysis is limited on this host.

## When to use

- User pastes a video URL (YouTube, Vimeo, X, TikTok, Twitch clip, Loom, most yt-dlp-supported sites) and asks about it.
- User points at a local video file (`.mp4`, `.mov`, `.mkv`, `.webm`, etc.) and asks about it.
- User says "/watch", "watch this video", "summarize this clip", or similar.

## Recommended limits

- **Best accuracy: videos under 10 minutes.** Frame coverage scales inversely with duration.
- **Hard caps: 100 frames total and 2 fps.** Token cost grows with frame count, so the script targets a frame budget by duration:
  - ≤30s → ~30 frames
  - 30s–1min → ~40 frames
  - 1–3min → ~60 frames
  - 3–10min → ~80 frames
  - \>10min → 100 frames sparsely spaced (warning printed)
- For long videos, consider asking whether the user wants a specific section before burning tokens on a sparse scan.

## How to invoke

**Step 1 — parse the user input.** Separate the video source (URL or path) from any question. Example: `/watch https://youtu.be/abc what language is this in?` → source = `https://youtu.be/abc`, question = `what language is this in?`.

**Step 2 — run watchyt.** Pass the source verbatim. Quote it normally:

```bash
watchyt "<source>"
```

Optional flags:
- `--start T` / `--end T` — focus on a section. Accepts `SS`, `MM:SS`, or `HH:MM:SS`. Triggers focused-mode budgets (denser).
- `--max-frames N` — lower the cap for tighter token budget (e.g. `--max-frames 40`).
- `--resolution W` — change frame width in px (default 512; bump to 1024 only if the user needs to read on-screen text like slides, terminals, or code).
- `--fps F` — override auto-fps (still capped at 2 fps).
- `--out-dir DIR` — keep working files somewhere specific (default: an auto-generated tmp dir).
- `--no-transcript` — skip the transcript pipeline entirely (frames only).
- `--backend B` — forwarded to `audiomemo transcribe -b`. Useful values: `whisper-cpp` (fully local, no network), `deepgram`, `openai`, `mistral`, `elevenlabs`. Omit to use audiomemo's configured default for this host.

### Focusing on a section (denser frame rate)

When the user names a moment — "what happens at the 2 minute mark?", "zoom into 0:45 to 1:00", "the first 10 seconds" — pass `--start` and/or `--end`. Focused-mode budgets (capped at 2 fps):

- ≤5s → 2 fps (up to 10 frames)
- 5–15s → 2 fps (up to 30 frames)
- 15–30s → ~2 fps (up to 60 frames)
- 30–60s → ~1.3 fps (up to 80 frames)
- 60–180s → ~0.6 fps (100 frames, capped)

Focused mode is the right call for:
- Any moment/range the user names explicitly ("around 2:30", "the intro", "the last 30 seconds").
- Any video longer than ~10 minutes where the user's question is about a specific part — focused on the relevant section is far more useful than a sparse full-video scan.
- Re-runs after a full scan didn't have enough detail in some region.

The transcript is auto-filtered to the same window. Frame timestamps are absolute (real video timeline), not offset-from-start.

Examples:
```bash
# Last 10 seconds of a 60-second video
watchyt video.mp4 --start 50 --end 60

# Window 2:15–2:45 with high-res frames for on-screen text
watchyt "$URL" --start 2:15 --end 2:45 --resolution 1024

# From 1h12m to the end of the video
watchyt "$URL" --start 1:12:00
```

**Step 3 — Read every frame path.** The script's report includes a `## frames` block listing each frame as `<path>  # t=MM:SS`. Use the `Read` tool on every path **in a single message (parallel tool calls)** so you see them together. The frames are in chronological order and the timestamp is in both the filename and the comment so you can align them to the transcript.

**Step 4 — answer the user.** You now have two streams of evidence:
- **Frames** — what's on screen at each timestamp.
- **Transcript** — what's said at each timestamp. The report's header line `transcript: <source>` indicates origin: `captions` (yt-dlp pulled native subs), `audiomemo:<backend>` (transcribed locally / via API), or `none` (no transcript was available).

If the user asked a specific question, answer it directly citing timestamps. If they didn't ask anything, summarize what happens — structure, key moments, notable visuals, spoken content.

**Step 5 — clean up.** The report includes a `working_dir` line. If the user isn't going to ask follow-ups about this video, delete it with `rm -rf <dir>`. If they might, leave it in place — re-running on the same video would re-download and re-extract frames.

## Transcripts

`watchyt` gets a timestamped transcript in one of two ways:

1. **Native captions (free, preferred).** For URLs, yt-dlp pulls manual or auto-generated VTT subtitles from the source platform if available.
2. **`audiomemo transcribe` fallback.** If captions are missing (or the source is a local file), `watchyt` extracts mono 16 kHz audio with ffmpeg and pipes it into `audiomemo transcribe -f vtt -`. The default backend is whatever the user configured for `audiomemo` on this host (typically ElevenLabs, with the API key managed via agenix). Pass `--backend whisper-cpp` to force fully-local transcription with no network calls.

If both paths fail, the report shows `transcript: none` and (when applicable) a `transcript_error:` line. Proceed frames-only and tell the user no transcript was available.

## Failure modes

- **Download fails** → yt-dlp's error goes to stderr. If it's a login-required, age-gated, or region-locked video, tell the user plainly; don't keep retrying.
- **No transcript** → captions missing AND `audiomemo` failed (e.g., backend's API key not set on this host). Proceed frames-only.
- **Long-video warning** → printed when an unfocused scan covers > 10 min. Acknowledge it; offer to re-run focused on a specific section.
- **Empty window** → `--start`/`--end` cover zero or negative duration. The script exits non-zero with a clear error.

## Token efficiency

Frames dominate token cost.
- 80 frames at 512px wide is roughly 50–80k image tokens depending on aspect ratio.
- Bumping `--resolution 1024` roughly quadruples the image tokens per frame. Only do it when on-screen text matters.
- The transcript is cheap (a few thousand tokens at most for a 10-minute video).

If you already watched a video this session and the user asks a follow-up, **do not** re-run the script — the frames and transcript are already in your context. Just answer.

## Security & permissions

**What this skill does:**
- Runs `yt-dlp` locally to download the video and pull native captions from whatever host the URL points at (public data).
- Runs `ffmpeg` / `ffprobe` locally to extract frames and, when needed, mono 16 kHz audio.
- When captions are missing, pipes that audio into `audiomemo transcribe`. Whether that goes to a network API depends on the user's `audiomemo` configuration — they own that choice. Pass `--backend whisper-cpp` to keep transcription fully local.
- Writes frames, audio, and transcripts to a working directory under the system temp dir (or `--out-dir` if specified) so you can `Read` them.

**What this skill does NOT do:**
- Does not handle API keys directly — `audiomemo` owns those, configured via the user's home-manager + agenix setup.
- Does not access any platform account (no login, no session cookies, no posting).
- Does not persist anything outside the working directory. Clean it up in Step 5 when the user is done.
