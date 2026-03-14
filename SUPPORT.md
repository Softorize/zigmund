# Support Policy

## Release Channels

- `stable`: production-ready releases with the highest compatibility expectations
- `rc`: release candidates intended for pre-production validation
- `beta`, `alpha`, `nightly`: preview channels with no compatibility guarantee

## Compatibility Commitments

- Public API changes require an intentional API surface update
- Security and governance gates apply to release branches and tags
- Breaking changes should ship with migration notes before promotion to `stable`

## Support Scope

Maintainers prioritize:

- current stable releases
- the latest release candidate
- regressions on `main` that block the next release train

Best-effort support is provided for preview channels. Older stable lines are not maintained unless explicitly announced.

## How To Get Help

- Open a GitHub issue for bugs, regressions, or documentation gaps
- Use a discussion or issue for design questions and upgrade planning
- Report vulnerabilities through the security policy instead of public issues
