# Publishing looot to pub.dev

The package name is `looot` (checked free on pub.dev on 2026-11-06). pub.dev needs the package
to exist before it lets you turn on automated publishing, so the first version goes up by hand.
Every release after that publishes from GitHub Actions with OIDC and no secret.

## One-time steps for Walid

1. Sign in to https://pub.dev with the Google account that should own the package.
2. From a clone of this repo at the `v0.1.0` commit, run:

   ```bash
   dart pub publish --dry-run   # must end with "Package has 0 warnings"
   dart pub publish             # opens a Google sign-in link in the terminal, then confirm
   ```

3. Open https://pub.dev/packages/looot/admin, find "Automated publishing", tick "Enable
   publishing from GitHub Actions" and set repository `loootai/looot-dart` and tag pattern
   `v{{version}}`.
4. In the GitHub repo, Settings, Environments, create an environment named `pub.dev`
   (`release.yml` uses it). Optionally limit it to tags matching `v*`.
5. Optional: create a verified publisher for `looot.ai` at https://pub.dev/create-publisher
   (it asks for a DNS TXT record), then on the package Admin tab choose "Transfer to
   publisher". This puts a verified badge on the page.

## Next release

1. Set the same version in `pubspec.yaml` and `lib/src/version.dart`, and add a section to
   `CHANGELOG.md`.
2. Run `dart analyze --fatal-infos`, `dart test` and `bash scripts/leak-scan.sh .`.
3. Commit, then `git tag v0.1.1 && git push origin main v0.1.1`. The release workflow checks
   that the tag matches both files, runs the tests, publishes and creates the GitHub release.

A published version cannot be replaced. Ship a new patch version instead. `dart pub
retract` hides a bad one.
