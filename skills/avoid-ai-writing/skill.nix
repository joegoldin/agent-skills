{
  name = "avoid-ai-writing";
  description = "Audit and rewrite content to remove AI writing patterns (\"AI-isms\"). Use when asked to \"remove AI-isms,\" \"clean up AI writing,\" \"edit writing for AI patterns,\" \"audit writing for AI tells,\" or \"make this sound less like AI.\" Supports a detect-only mode, an edit-in-place mode for files, an optional voice profile (casual / professional / technical / warm / blunt), and an iterate-to-convergence pass.";
  allowed-tools = [
    "Bash(avoid-ai-detect)"
    "Bash(avoid-ai-detect:*)"
  ];
}
