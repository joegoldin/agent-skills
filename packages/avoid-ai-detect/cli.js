#!/usr/bin/env node
// avoid-ai-detect - CLI for the deterministic AI-writing detector.
//
// Thin wrapper original to joegoldin/agent-skills. The detection engine
// (patterns.js) is vendored from conorbronsdon/avoid-ai-writing (MIT); see
// ../../ATTRIBUTION.md. Reads a file (or stdin), runs AIDetector.analyzeText,
// and prints either a human report (default) or the raw result (--json).
'use strict';

const fs = require('fs');
const path = require('path');

const AIDetector = require(path.join(__dirname, 'patterns.js'));

function usage() {
  process.stderr.write(
    [
      'avoid-ai-detect - score text for AI-writing patterns (0-100).',
      '',
      'Usage:',
      '  avoid-ai-detect [options] [FILE]',
      '  cat draft.md | avoid-ai-detect',
      '',
      'Options:',
      '  --json                 Print the full result object as JSON.',
      '  --context MODE         Detection context: general (default) or technical.',
      '  --top N                Show only the top N issues in the report.',
      '  -h, --help             Show this help.',
      '',
      'Reads FILE when given, otherwise stdin. Exit code is 0 on a completed',
      'analysis regardless of score; the score is the signal.',
      '',
    ].join('\n'),
  );
}

function fail(msg, code) {
  process.stderr.write(`avoid-ai-detect: ${msg}\n`);
  process.exit(code);
}

const args = process.argv.slice(2);
let asJson = false;
let contextMode = 'general';
let top = Infinity;
let file = null;

for (let i = 0; i < args.length; i++) {
  const a = args[i];
  if (a === '--json') asJson = true;
  else if (a === '-h' || a === '--help') return usage();
  else if (a === '--context') {
    contextMode = args[++i];
    if (!contextMode) fail('--context needs a value (general|technical)', 2);
  } else if (a === '--top') {
    top = parseInt(args[++i], 10);
    if (!Number.isFinite(top) || top < 0) fail('--top needs a non-negative number', 2);
  } else if (a.startsWith('-') && a !== '-') {
    fail(`unknown option: ${a} (try --help)`, 2);
  } else {
    if (file !== null) fail('more than one input file given', 2);
    file = a;
  }
}

if (file === null && process.stdin.isTTY) {
  usage();
  process.exit(2);
}

let text;
try {
  text = fs.readFileSync(file === null ? 0 : file, 'utf8');
} catch (e) {
  fail(`cannot read ${file === null ? 'stdin' : file}: ${e.message}`, 1);
}

const result = AIDetector.analyzeText(text, { contextMode });

if (asJson) {
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  process.exit(0);
}

const TYPE = AIDetector.TYPE_LABELS || {};
const SEV = AIDetector.SEVERITY_LABELS || {};
const SEV_ORDER = { critical: 0, high: 1, medium: 2, low: 3 };

const out = [];
out.push(`Score:          ${result.score}/100  (${result.label})`);
if (result.document_classification) {
  out.push(
    `Classification: ${result.document_classification}  (confidence: ${result.confidence_category})`,
  );
}
const stats = result.stats || {};
if (stats.wordCount) {
  out.push(`Words:          ${stats.wordCount}   Context: ${stats.contextMode || contextMode}`);
}

const issues = Array.isArray(result.issues) ? result.issues : [];
// The engine returns raw (possibly repeated) hits; dedupe by (type, text) for
// the report the same way scoring dedupes, then sort worst-severity first.
const seen = new Set();
const uniq = [];
for (const it of issues) {
  const key = `${it.type}\u0000${it.text}`;
  if (seen.has(key)) continue;
  seen.add(key);
  uniq.push(it);
}
uniq.sort(
  (a, b) =>
    (SEV_ORDER[a.severity] ?? 9) - (SEV_ORDER[b.severity] ?? 9) ||
    String(a.type).localeCompare(String(b.type)),
);

out.push(`Issues:         ${uniq.length}`);

if (uniq.length) {
  out.push('');
  let shown = 0;
  for (const it of uniq) {
    if (shown >= top) {
      out.push(`  ... and ${uniq.length - shown} more (raise --top to see them)`);
      break;
    }
    const label = TYPE[it.type] || it.type;
    const sev = String(SEV[it.severity] || it.severity || '');
    const snippet = String(it.text).replace(/\s+/g, ' ').trim();
    const clipped = snippet.length > 60 ? `${snippet.slice(0, 57)}...` : snippet;
    out.push(`  [${sev}] ${label} - "${clipped}"`);
    shown++;
  }
}

process.stdout.write(`${out.join('\n')}\n`);
process.exit(0);
