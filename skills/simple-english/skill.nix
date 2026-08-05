{
  name = "simple-english";
  description = "Write or rewrite technical text under ASD-STE100 Simplified Technical English so it is clear, unambiguous, and free of AI slop. Use for documentation, READMEs, runbooks, procedures, error messages, release notes, incident reports, agent instructions, and API guides. Also use when the user says \"STE\", \"Simplified Technical English\", \"ASD-STE100\", \"de-slop\", \"make this readable\", \"write for non-native readers\", or asks for docs that translate well. Enforces the standard's 53 rules — 20/25-word sentence limits, one word one meaning, simple tenses, active voice, condition before command — with a Vale style for the mechanical half.";
  allowed-tools = [
    "Bash(vale-skill)"
    "Bash(vale-skill:*)"
    "Bash(vale)"
    "Bash(vale:*)"
  ];
}
