# Auto-Update Functional Specification

## Problem Statement

Yanmo is distributed as a notarized DMG through GitHub Releases. Users must
discover, download, and install every release manually. This leaves installations
outdated and makes security or compatibility fixes slow to reach users.

## Solution

Integrate Sparkle 2 using its standard updater, interface, scheduler, permission
prompt, and installation flow. Yanmo will offer a standard “Check for Updates…”
command. Sparkle will ask about automatic checks on the second launch, check once
per day when allowed, and manage download, installation, and relaunch.

Updates will use a public appcast hosted by GitHub Pages. Each appcast item will
reference an immutable, notarized DMG in GitHub Releases and carry a Sparkle EdDSA
signature. The release process will publish the appcast only after every referenced
asset is available.

No custom updater interface, scheduler, downloader, installer, update settings,
channels, or update policy will be built.

## User Stories

1. As a Yanmo user, I want to learn when an update is available, so that I can run
   a current version.
2. As a Yanmo user, I want Yanmo to request permission before enabling automatic
   checks, so that the choice is mine.
3. As a Yanmo user, I want the permission request delayed until the second launch,
   so that first launch stays focused on editing.
4. As a Yanmo user, I want to decline automatic checks, so that Yanmo makes no
   scheduled update requests.
5. As a Yanmo user, I want to check manually at any time, so that automatic checks
   are optional.
6. As a Yanmo user, I want automatic checks to remain quiet when nothing is
   available, so that editing is uninterrupted.
7. As a Yanmo user, I want release notes in the standard update prompt, so that I
   can decide whether to install.
8. As a Yanmo user, I want update failures explained by the standard updater, so
   that I know whether to retry.
9. As a Yanmo user, I want downloaded updates verified, so that modified packages
   cannot be installed.
10. As a Yanmo user, I want updates accepted by Gatekeeper, so that installation
    does not weaken macOS security.
11. As a Yanmo user, I want installation to preserve open documents and settings,
    so that updating does not lose work.
12. As a Yanmo user, I want Yanmo relaunched through Sparkle’s standard flow, so
    that I can continue after installation.
13. As a release manager, I want one release command to build and publish every
    required artifact, so that the feed cannot drift from the release.
14. As a release manager, I want publication to stop on any failed test, signing,
    notarization, or feed step, so that incomplete updates remain undiscoverable.
15. As a release manager, I want update versions compared using monotonically
    increasing build numbers, so that every client selects the correct release.
16. As a release manager, I want the update signing key kept outside the repository,
    so that repository access cannot authorize an update.
17. As a maintainer, I want Sparkle updated through Swift Package Manager, so that
    dependency resolution remains reproducible.
18. As a maintainer, I want an end-to-end update test between packaged builds, so
    that the shipped installation path—not an imitation—is verified.

## Implementation Decisions

1. **Framework**

   Use the stable Sparkle 2 package from its official repository. Declare it in the
   XcodeGen project definition and commit the resolved package version. Release
   builds must not resolve an untested Sparkle version implicitly.

2. **App integration**

   Own one `SPUStandardUpdaterController` for the application lifetime. Start it
   with Sparkle’s standard user driver and no delegates. The updater targets the
   main application bundle.

3. **Manual command**

   Add “Check for Updates…” to the application menu after the About command. It
   invokes Sparkle’s manual check and reflects `canCheckForUpdates`. No Yanmo alert
   or progress interface will wrap it.

4. **Default behavior**

   Do not set defaults for automatic checks, automatic downloads, check interval,
   profile submission, or installation. Sparkle therefore requests permission on
   the second launch, uses its daily schedule, and retains the user’s choices in
   its own preferences. Yanmo must not duplicate those preferences.

5. **Required bundle configuration**

   Configure only the appcast URL and Sparkle EdDSA public key. The production feed
   URL is `https://lvterry.github.io/Yanmo/appcast.xml`. Do not enable sandbox XPC
   services because Yanmo is not sandboxed.

6. **Update feed**

   Host one production appcast on GitHub Pages. Generate it with Sparkle’s
   `generate_appcast`; do not construct XML in application or release code. The
   feed contains the current stable release. It need not retain historical items
   while delta updates are excluded.

7. **Release assets**

   Each item references an immutable GitHub Release asset under its version tag,
   never a mutable “latest” URL. The release contains the notarized DMG and a
   matching Markdown release-notes asset. Sparkle may present those notes using its
   standard renderer.

8. **Versioning**

   Use the marketing version for display and the bundle build number for update
   ordering. Every public build number must be greater than all earlier public and
   test builds that used the production bundle identifier. The release process
   rejects reused tags, versions, and non-increasing build numbers.

9. **Update signing**

   Generate one EdDSA key with Sparkle’s tool. Store the private key in the release
   Mac’s login Keychain and keep a separate protected backup. Commit only the public
   key. Every update archive must have a valid EdDSA signature in the appcast.

10. **Apple signing**

    Replace target-build-plus-deep-signing with Xcode Archive and Developer ID
    export. This lets Xcode sign Sparkle’s nested helpers correctly. Notarize and
    staple the exported application and final DMG. Reject the release if strict
    code-signing, Gatekeeper, or stapler validation fails.

11. **Release order**

    The release workflow runs tests, archives and exports the app, creates the DMG,
    notarizes it, generates the signed appcast, creates the GitHub Release, uploads
    all assets, verifies their public URLs, and publishes the appcast last. Git tags
    and version commits remain part of the existing release workflow.

12. **Failure handling**

    Before appcast publication, any failure aborts discovery of the new release.
    After publication, a bad release is removed from the appcast immediately. A
    corrective release must use a higher build number; clients are never downgraded.

13. **Existing installations**

    Versions through 0.8 cannot discover updates. The first Sparkle-enabled release
    requires one final manual installation. Its release notes and download page must
    state that later releases can update in place.

14. **Application data**

    The updater replaces only the application bundle. Documents, templates,
    preferences, and the installed command-line launcher are outside the update
    payload. Existing behavior for restoring documents remains owned by macOS and
    Yanmo.

15. **Diagnostics**

    Rely on Sparkle’s standard errors and unified logging. Do not add analytics,
    custom update telemetry, retry loops, or a second network layer.

## Testing Decisions

The primary seam is a real update between packaged, Developer ID–signed and
notarized builds. Tests assert observable results: discovery, displayed release
information, installation, relaunch, final version, preserved documents, and valid
signatures. They do not mock Sparkle internals.

1. Build an older Yanmo version against a temporary HTTPS appcast.
2. Publish a newer build with a greater bundle build number to that feed.
3. Confirm manual checking finds the newer build and displays its version and notes.
4. Complete the standard install and relaunch flow.
5. Confirm the application bundle reports the newer marketing and build versions.
6. Confirm an open saved document and application preferences remain intact.
7. Confirm strict code-signing, Gatekeeper assessment, and stapler validation pass
   before and after installation.
8. Confirm a modified DMG or invalid EdDSA signature is rejected.
9. Confirm an unavailable feed does not interrupt an automatic background check and
   produces Sparkle’s standard error during a manual check.
10. Confirm declining automatic checks prevents scheduled checks while leaving the
    manual command available.
11. Confirm the release workflow cannot publish the appcast before its referenced
    DMG and release notes return successful HTTPS responses.
12. Confirm the appcast’s version, build number, file length, signature, minimum
    system version, and immutable asset URL match the packaged application.

Existing unit-test conventions remain appropriate for Yanmo-owned logic. No updater
unit tests are required unless Yanmo later adds behavior beyond the thin menu bridge.
Release verification extends the existing packaged-DMG checks.

## Out of Scope

- A custom update window, notification, progress view, or settings tab.
- Custom scheduling, launch-time checks, retry policy, or background service.
- Delta updates.
- Beta, nightly, staged, phased, critical, or major-update channels.
- Silent forced updates or forced relaunches.
- Signed appcasts and signed release-note files beyond the required signed update
  archive.
- Migration to the Mac App Store.
- Application sandboxing.
- Updating the command-line launcher separately from the application bundle.
- Automatic migration for Yanmo 0.8 or earlier.
- CI-based release signing. The existing trusted release Mac remains authoritative.

## Further Notes

Sparkle is executable-code infrastructure. Its private key and Developer ID identity
must be treated as release credentials. Losing both the active EdDSA private key and
the ability to issue a valid Developer ID–signed rotation build can strand existing
installations.

Before publishing the first Sparkle-enabled release, install its release candidate
and update it to a second packaged test build through the temporary feed. Future
releases must be smoke-tested from the immediately preceding public version.
