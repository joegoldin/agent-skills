---
name: changelog-and-versioning
description: Write user-facing changelogs with Keep a Changelog and choose release bumps with SemVer. Use when asked to update a changelog, draft release notes, or decide the next software version.
---

# Changelog and versioning

Check the project's changelog, version policy, release tooling, and last release
of the affected package. Use the actual release range and verify candidate
entries against diffs, PRs, or issues. Follow established project conventions;
use [Keep a Changelog 2.0.0](https://keepachangelog.com/en/2.0.0/) and
[SemVer 2.0.0](https://semver.org/spec/v2.0.0.html) where applicable. A changelog
request is not a request to cut a release.

## Write the changelog

- Keep `# Changelog` and a short preamble naming the format and the project's
  actual version scheme. Put `## Unreleased` above releases, newest first,
  headed `## 1.2.3 - YYYY-MM-DD` with the verified release date. Bracket a
  heading label only when its reference link is defined in the file: for
  example, `## [Unreleased]` needs a matching `[Unreleased]: URL`.
- Group notable changes under `Added`, `Changed`, `Deprecated`, `Removed`,
  `Fixed`, and `Security`, in that order. Omit empty groups. Write what changed
  for users, not a commit list. Combine duplicates and skip internal churn
  unless it affects consumers. Lead public security entries with an assigned
  CVE when available and link to the advisory.
- Mark breaking entries `**Breaking:**` in the appropriate group, say who is
  affected, and link to or state the upgrade step. For a yanked release, retain
  its entry and append `[YANKED]` to the version heading.
- Add new entries to `Unreleased`. When preparing a named release, move only
  what it ships into the dated section and retain `Unreleased` for future work.
  Update reference links using verified repository and tag conventions:
  previous tag to release tag, and latest release tag to the development branch
  for `Unreleased`. Don't invent tags, links, or past entries. Derive release
  notes from the same entries rather than maintaining a second history.

## Pick the version

For a stable SemVer project, compare the declared public contract with the
last stable release in the target line. That contract may include a library
API, CLI flags and output, or documented config and data formats. Use the
highest applicable bump:

| Change | Bump |
| --- | --- |
| Incompatible change to the public contract | Major; reset minor and patch |
| Backward-compatible public functionality or deprecation | Minor; reset patch |
| Backward-compatible correction only | Patch |

For `0.y.z`, follow the project's pre-1.0 policy and state your assumption if
none is documented; SemVer does not promise stability before `1.0.0`. For a
prerelease, classify the target release first (for example `2.0.0-rc.1`). A
prerelease sorts below its matching final version; `+build` metadata does not
change precedence. Never replace the contents of a published version.

State the proposed version and what drives it. If asked to prepare release
files, check that the changelog, package versions, and release configuration
agree. Don't tag, push, or publish unless the user specifically authorizes it.
