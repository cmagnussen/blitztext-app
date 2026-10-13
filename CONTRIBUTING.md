# Contributing

Thanks for taking a look at Blitztext macOS Preview.

This repository is intentionally a preview. Contributions should make it easier to learn from, build, fork, or safely extend.

## Good First Contributions

- improve build instructions
- fix confusing UI text
- improve error messages
- add tests around parsing or quality filters
- document local model experiments
- simplify setup

## Before Opening A Pull Request

Please include:

- what changed
- why it changed
- how you tested it
- whether you used AI-assisted coding tools

Keep changes small when possible. Avoid unrelated cleanup in the same PR.

## Local Build

```bash
./build.sh --debug
```

## Security And Privacy

- Never commit API keys, tokens, private audio, or confidential transcripts.
- Avoid adding telemetry, hosted services, or external dependencies without a clear issue first.
- Call out privacy-impacting changes in the pull request description.
- Keep it honest: only describe something as local if it really runs on the device.

## Project Boundaries

This preview currently does not include:

- other platforms
- a hosted backend
- packaged releases
- bundled local model files
- local text rewriting

Those can be discussed in issues, but please keep PRs focused on the current macOS preview unless a maintainer agrees on a larger direction first.
