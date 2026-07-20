# Continuous Integration

The CI workflow is `.github/workflows/ci.yml`.

It runs on GitHub-hosted macOS for pull requests, pushes to `main`, and manual
dispatch. Default permissions are read-only. The dependency review job is
limited to same-repository pull requests because forked pull requests must not
receive elevated repository or Apple signing context.

CI validates:

- repository policy files;
- Swift package build;
- Swift tests;
- Xcode build of `HermesBridgeApp`;
- zsh syntax for scripts;
- selected integration fixtures;
- privacy and action-surface markers;
- dependency review where GitHub supports it;
- failure log artifact retention.

CI does not publish releases and does not consume Apple credentials.

