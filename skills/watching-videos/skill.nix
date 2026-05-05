{
  name = "watching-videos";
  description = "Use when the user asks about a video — pasted URL (YouTube, Vimeo, TikTok, X, Loom, etc.) or local file path (.mp4/.mov/.mkv/.webm). Downloads the video, extracts frames, pulls a timestamped transcript so you can answer about visual + spoken content.";
  allowed-tools = [
    "Bash(watchyt)"
    "Bash(watchyt:*)"
    "Bash(rm:*)"
  ];
}
