# Release process

## One-time setup

Install `xcodegen`, `gh`, and `sentry-cli`. Authenticate `gh`. Keep the
Developer ID certificate and `yanmo-notary` profile in the release Mac's login
Keychain.

```bash
brew install getsentry/tools/sentry-cli
```

The Sentry `org:ci` token is stored in the login Keychain under service
`com.yanmo.app.sentry` and account `org-ci`. The release command reads it only
for release creation and dSYM upload. Store the raw `sntrys_…` value without a
label, `Bearer` prefix, or whitespace. The release command validates it before
archiving.

The Sparkle private key is stored in the login Keychain under account
`com.yanmo.app`. Back it up outside this repository:

```bash
bin=$(./scripts/sparkle-tools.sh)
"$bin/generate_keys" --account com.yanmo.app -x /protected/path/yanmo-eddsa.key
```

The committed public key is in `Yanmo/Info.plist`. Never rotate it without a
signed rotation release.

## Release

Start with a clean `main` branch. The notes must mention that 0.8 and older need
this final manual installation.

```bash
./scripts/release.sh 0.10.0 /path/to/release-notes.md
```

The command rejects reused versions, tags, and stale build numbers. It then:

1. Runs tests.
2. Archives and exports with Developer ID signing.
3. Verifies the app and dSYM UUIDs, then uploads symbols to Sentry.
4. Notarizes and staples the app and DMG.
5. Preserves the archive and its release metadata in Xcode Organizer.
6. Generates and verifies the signed appcast.
7. Pushes the version commit and tag.
8. Creates the GitHub release and verifies both public assets.
9. Commits the appcast and publishes GitHub Pages last.

GitHub Pages is created from `main:/docs` on the first release. Later releases
must keep that source.

## Sentry staging test

Build a non-publishing `0.10.0 (8.1)` DMG before the public release:

```bash
./scripts/build-sentry-test.sh
```

This uses the normal signing, notarization, and dSYM upload path. It identifies
events as release `com.yanmo.app@0.10.0+8.1` in Sentry's `staging` environment.
It does not commit, tag, update the appcast, or create a GitHub release. The
script restores `Yanmo/Info.plist` after success or failure.

If build `8.1` was already archived, pass another pre-release build below `9`:

```bash
./scripts/build-sentry-test.sh 8.3
```

Install `dist/Yanmo-0.10.0.dmg` outside Xcode. Accept crash diagnostics, open
and save a test document, then terminate Yanmo with a real crash signal:

```bash
kill -SEGV "$(pgrep -x Yanmo)"
```

Relaunch Yanmo so the prior crash can upload. In Sentry, confirm the release,
`staging` environment, readable Yanmo stack frames, and absence of document
contents, filenames, user identity, IP address, and unrelated breadcrumbs.
Sentry may derive coarse geography after discarding the IP; this accepted
server-side limitation is recorded in `specs/sentry-integration-plan.md`.
Delete the test document when finished. The public `0.10.0` release uses build
`9` and the `production` environment.

If publication fails before the appcast push, fix the cause and continue without
reusing the version or tag. If a bad appcast is already public, remove its item
immediately. Publish the fix with a higher build number.

## Routine checks

```bash
xcodegen generate
xcodebuild -scheme Yanmo -destination 'platform=macOS' test
```

Launch the built app. Confirm “Check for Updates…” follows About and invokes
Sparkle's standard window. Use a fresh macOS account to confirm no permission
prompt appears on launch one, the standard prompt appears on launch two, and
declining it leaves manual checking enabled.

## Packaged update test

Before every release, update from the preceding public DMG to a packaged test
build. Before the first Sparkle release, use two packaged test builds.

1. Choose a temporary GitHub prerelease tag, such as
   `update-test-20260828`.
2. Set `SUFeedURL` in the older test build to the future public asset URL:
   `https://github.com/lvterry/Yanmo/releases/download/<tag>/appcast.xml`.
3. Assign the older build a new build number. Run `./scripts/make-dmg.sh`.
4. Assign the newer build a greater build number and version. Build it the same
   way. Keep this build number reserved: the public release must be greater.
5. Put the newer DMG and a same-basename Markdown notes file in one directory.
   Generate the feed:

```bash
bin=$(./scripts/sparkle-tools.sh)
prefix="https://github.com/lvterry/Yanmo/releases/download/<tag>/"
"$bin/generate_appcast" \
  --account com.yanmo.app \
  --download-url-prefix "$prefix" \
  --release-notes-url-prefix "$prefix" \
  --maximum-versions 1 \
  --maximum-deltas 0 \
  -o /path/to/updates/appcast.xml \
  /path/to/updates
```

6. Create the prerelease with the newer DMG, matching notes, and appcast as
   assets. Wait until all three URLs return HTTP 200.
7. Install and launch the older DMG. Open and save a document; change a
   preference. Check manually. Confirm the newer version and notes, install,
   relaunch, final version/build, open document, and preference.
8. Corrupt a copy of the DMG, change the appcast to reference it without
   resigning, and confirm Sparkle rejects installation.
9. Point the older build at an unavailable HTTPS feed. Confirm automatic checks
   stay quiet and manual checking shows Sparkle's error.
10. Keep the highest test build number in `CFBundleVersion`, restore the
    production feed, and commit that reservation before running the release.
11. Delete the temporary prerelease, remote tag, and local tag.

Validate any generated production-style feed and package with:

```bash
YANMO_RELEASE_TAG=<tag> ./scripts/verify-release.sh \
  /path/to/appcast.xml \
  /path/to/Yanmo-<version>.dmg \
  /path/to/Yanmo-<version>.md \
  <version> \
  <build> \
  "$(./scripts/sparkle-tools.sh)"
```
