# Open Source Preflight

Use this checklist before making the repository public.

## P0 Before Public

- Run a local build with `./build.sh --debug`.
- Run a secret scan across the working tree and commit history.
- Confirm there are no private URLs, hosted backend credentials, internal docs, or old project references.
- Keep the repository private until another maintainer has reviewed the first public commit.
- Confirm the root `LICENSE`, `README.md`, `SECURITY.md`, `CONTRIBUTING.md`, and `SUPPORT.md` are present.
- Make the status explicit: free and open source, local first, no hosted backend, no warranty, no guaranteed support.
- Enable GitHub private vulnerability reporting, secret scanning, and push protection before switching the repo public.
- Enable Dependabot alerts.
- Protect `main` with pull requests, at least one review, and required CI checks.
- Keep GitHub Actions permissions read-only by default.

## P1 Soon After Public

- Enable private vulnerability reporting.
- Decide whether Issues alone are enough or whether Discussions should be enabled for questions.
- Add repository topics such as `macos`, `swift`, `menubar`, `speech-to-text`, and `openai`.
- Add a lightweight release process only after the build is signed and notarized.
- Add basic tests once provider boundaries are extracted.

## P2 Later

- Add CODEOWNERS if multiple maintainers become active.
- Add local model cleanup after the in-app download/install flow.
- Consider CodeQL once the repo has enough surface area to justify scheduled scans.
- Add signed and notarized release artifacts for non-developer testers.
