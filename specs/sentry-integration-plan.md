# Sentry Integration Plan

## Resolved Setup

- Sentry account: provisioned; personal account details stay out of the repository.
- Data region: European Union.
- Region URL: `https://de.sentry.io`.
- Organization: provisioned; identifiers live only where release tooling requires them.
- Project platform: macOS.
- Project: provisioned; the public submission DSN lives in application configuration.
- Sentry Cocoa version selected during setup: `9.26.1`.
- Authentication: a release-only token is stored in the release Mac login Keychain. Never print, send, or commit its value.
- Alerts notify the maintainer for every new issue and every resolved issue that regresses. Repeated events alone do not trigger them.
- Consent: reporting starts only after explicit consent; declining is remembered; the choice remains available in Settings.
- Consent prompt: “Help improve Yanmo by sharing crash diagnostics. Reports include the Yanmo version, macOS version, hardware architecture, and crash stack. Yanmo does not include document contents or filenames.”
- Confirmed first release: Yanmo `0.10.0`, build `9`.

The free Sentry Developer plan is sufficient after the current trial ends. No additional user input is required before implementation.

## Problem Statement

Yanmo is distributed directly as a notarized Developer ID application. App Store and TestFlight crash collection therefore cannot be its primary crash channel. Users must currently notice a crash, find the macOS report, and contact the developer. Most crashes will remain unknown.

Yanmo edits potentially sensitive local documents. Automatic diagnostics must not expose document contents, filenames, paths, remote asset URLs, or user identity.

Release builds produce dSYMs, but each release overwrites the same Xcode archive. A crash from an older release may become impossible to symbolicate unless its archive is retained or its dSYMs are uploaded.

## Solution

Integrate the Sentry Cocoa SDK as an optional, crash-only diagnostic service. Ask once for consent, start reporting only after consent, and expose the choice in Settings.

Send fatal crash reports with an allowlisted context: Yanmo version, build, environment, macOS version, CPU architecture, exception details, stack trace, and coarse feature state. Disable analytics, tracing, profiling, replay, logs, attachments, automatic session tracking, and automatic network or UI breadcrumbs.

Upload matching dSYMs during release and retain every released Xcode archive privately. Validate the complete path with a packaged app outside Xcode.

```text
Packaged Yanmo -> local crash report -> next launch -> Sentry -> issue and alert
       |                                                  ^
       +------------ version/build + matching dSYM -------+
```

## User Stories

1. As a Yanmo user, I want crash reporting to require consent, so that diagnostics are not sent unexpectedly.
2. As a Yanmo user, I want a clear description of collected data, so that I can make an informed choice.
3. As a Yanmo user, I want Yanmo to remember my choice, so that it does not ask repeatedly.
4. As a Yanmo user, I want to change my choice in Settings, so that I remain in control.
5. As a Yanmo user, I want reporting disabled after I opt out, so that later crashes are not submitted.
6. As a Yanmo user, I want my documents excluded, so that private writing remains local.
7. As a Yanmo user, I want crash reporting to remain quiet, so that it does not interrupt document recovery after a crash.
8. As the maintainer, I want fatal crashes grouped by cause, so that repeated failures become one actionable issue.
9. As the maintainer, I want every crash tagged with version and build, so that regressions can be tied to a release.
10. As the maintainer, I want symbolicated Yanmo frames, so that reports identify functions and source lines.
11. As the maintainer, I want coarse feature breadcrumbs, so that I know whether a crash occurred during editing, preview, or export without seeing user data.
12. As the maintainer, I want new and regressed crash alerts, so that production failures are noticed promptly.
13. As the maintainer, I want development events separated from production, so that testing does not pollute release data.
14. As the maintainer, I want offline crashes retained until connectivity returns, so that temporary network loss does not discard reports.
15. As the maintainer, I want every release archive retained, so that old crash reports remain diagnosable.
16. As the maintainer, I want missing dSYM uploads detected before publication, so that a release does not silently produce unusable reports.
17. As the maintainer, I want the provider hidden behind a diagnostic abstraction, so that application features do not depend on Sentry APIs.
18. As the maintainer, I want Sparkle diagnostics kept separate, so that crash reporting does not become update telemetry.

## Implementation Decisions

### 1. Account and project

- Use the provisioned organization and macOS project in Sentry's EU region.
- Begin on the free Developer plan.
- Use one project with `development`, `staging`, and `production` environments.
- Send only production crashes in normal builds. Enable staging deliberately for packaged validation.
- Configure email alerts for new issues and regressions. Do not alert once per repeated event.
- Keep Error Monitoring enabled. Keep Tracing and Profiling disabled.
- Keep repository linking disabled.

### 2. Dependency and boundary

- Add the official Sentry Cocoa package through Swift Package Manager.
- Pin Sentry Cocoa `9.26.1` exactly, matching the existing dependency policy.
- Declare it in the XcodeGen project source, not only in the generated Xcode project.
- Encapsulate Sentry behind a private crash-reporting service. Views, documents, rendering, export, and update code communicate only with that service.
- Expose domain actions such as reporting a coarse feature transition. Do not expose Sentry event or scope types outside the diagnostic layer.

### 3. Consent lifecycle

- Model consent as `unknown`, `allowed`, or `denied`, not a Boolean.
- Persist the choice in application settings.
- Show the consent prompt once after the first document window is usable. Do not combine it with Sparkle’s update-check permission.
- On `allowed`, initialize Sentry for the current process and future launches.
- On `denied`, leave Sentry uninitialized.
- When an allowed user opts out, stop event delivery, remove queued diagnostic envelopes, and leave Sentry disabled on later launches.
- Do not prompt again after denial. Settings is the only route to opt in later.

### 4. Startup

- For users who already consented, initialize crash reporting before Yanmo performs feature startup work.
- Keep initialization synchronous and small. Network delivery remains asynchronous.
- A crash that occurs before first-run consent is not collected. This is the privacy cost of opt-in reporting.
- Sentry’s DSN may live in application configuration. It grants event submission, not dashboard access.

### 5. Data contract

Allowed data:

- Bundle identifier.
- Marketing version and build number.
- `development`, `staging`, or `production` environment.
- macOS version and CPU architecture.
- Exception, signal, stack, binary images, and dSYM identifiers.
- Coarse state: `editing`, `previewing`, `exportingHTML`, `exportingPDF`, or `updatingSettings`.
- Coarse document state: `saved` or `unsaved`.

Forbidden data:

- Document content, rendered HTML, selected text, or front matter.
- Filename, file path, file URL, window title, or template name.
- Remote asset URL, request URL, headers, body, or response.
- Clipboard contents, screenshots, view hierarchy, or attachments.
- User name, email, device name, IP address, or stable installation identifier.
- Location or geography derived from an IP address.
- Sparkle feed contents, update results, or update-check activity.

Enforcement:

- Keep default PII disabled.
- Disable network tracking, failed-request capture, automatic network breadcrumbs, tracing, profiling, replay, logs, attachments, and automatic session tracking.
- Use manual, enum-backed breadcrumbs only.
- Apply a final event scrubber before submission.
- Enable server-side IP scrubbing and default data scrubbing.
- Sentry may still derive coarse geography while discarding the source IP. The
  `org:ci` release token cannot change this server policy. Accept this limitation
  unless an owner later adds an advanced rule to remove anything from
  `user.geo`; that rule affects only new events.
- Keep Sentry Enhanced Privacy enabled.
- Keep shared issues, JavaScript source fetching, join requests, and minidump attachments disabled.
- Do not calculate crash-free users or sessions. That requires additional session or installation tracking.

### 6. Release identity and symbols

- Identify releases as the bundle identifier plus marketing version and build number.
- Use the same identity in the app, dSYM upload, and Sentry release record.
- Upload dSYMs from the exact archive used to create the published DMG.
- Verify the UUIDs of the app binary and uploaded dSYMs.
- Run symbol upload before the release is published. A failed upload blocks publication.
- Keep the authentication token outside the app and repository. Read it only on the release Mac.
- Read the token from the login Keychain through the release helper.
- Store released archives under `~/Library/Developer/Xcode/Archives/<date>/` so they remain visible in Xcode Organizer.
- Name each archive `Yanmo-<version>-build-<build>.xcarchive`.
- Protect the release Mac with FileVault and include the archive directory in Time Machine.
- Maintain one encrypted offsite backup using an encrypted cloud-backup service or a rotated encrypted external disk.
- Retain every publicly distributed archive indefinitely.
- Store the version, build, dSYM UUID, and DMG SHA-256 checksum with each archive.
- Keep archives private. Do not attach them to public GitHub releases or commit them.
- Treat Sentry’s uploaded dSYM as an additional copy, not a replacement for the full archive.
- Do not treat cloud synchronization alone as backup because deletion can synchronize.
- Never delete an older archive as part of a later release.

### 7. Operations

- Triage production issues by crash cause, affected release, macOS version, and architecture.
- Mark an issue resolved in the release containing its fix.
- Keep the full Apple `.ips` report as the escalation path when Sentry lacks sufficient detail.
- Review quota monthly during the beta. Upgrade only when the event allowance, one-user limit, or retention period becomes restrictive.
- Review Sentry Cocoa release notes before dependency updates because crash handlers operate inside the application process.

## Testing Decisions

The primary seam is a real crash of the packaged, Developer ID-signed and notarized application outside Xcode. This exercises startup, consent, crash persistence, relaunch delivery, release identity, dSYM matching, symbolication, and privacy together.

Automated tests:

- Test transitions among `unknown`, `allowed`, and `denied` consent states.
- Test persistence and migration of consent settings using the existing settings-test style.
- Test that every allowed coarse context value maps to a fixed diagnostic value.
- Test that the event scrubber removes forbidden keys and values.
- Test that disabled reporting creates no diagnostic client.
- Test release verification rejects a missing archive, missing dSYM, or UUID mismatch.

Packaged validation:

1. Run `./scripts/build-sentry-test.sh` to produce a non-publishing
   `0.10.0 (8.3)` staging DMG with matching dSYMs. Use `8.4` or another
   `8.<positive integer>` if that archive already exists.
2. Install the packaged staging build on a clean macOS account.
3. Decline consent and confirm no Sentry request occurs.
4. Enable reporting in Settings.
5. Trigger a deliberate crash outside Xcode with
   `kill -SEGV "$(pgrep -x Yanmo)"`.
6. Relaunch and confirm one event arrives under release
   `com.yanmo.app@0.10.0+8.3` and environment `staging`.
7. Confirm the event has the exact version, build, OS, and architecture.
8. Confirm Yanmo frames contain function names and source lines.
9. Inspect the raw event for document text, filenames, paths, URLs, identity, and IP address.
10. Crash while offline, relaunch, restore connectivity, and confirm delayed delivery.
11. Disable reporting, repeat the crash, and confirm no later delivery.
12. Confirm normal reopening and document recovery remain unchanged.

Do not unit-test Sentry’s crash handler. Test Yanmo’s policy and the real packaged integration.

## Out of Scope

- Product analytics.
- Crash-free user or session rates.
- Performance tracing or profiling.
- Session replay, screenshots, view hierarchy, logs, or attachments.
- User feedback widgets.
- Handled-error collection.
- MetricKit hang, CPU, disk, or launch diagnostics.
- Sparkle update telemetry.
- Self-hosted Sentry.
- Slack, GitHub, Jira, or paging integrations.
- App Store or TestFlight distribution.

## Further Notes

- The Sentry account, organization, project, privacy configuration, DSN, and release token are provisioned. Private identifiers remain outside this plan. The accepted `user.geo` limitation is documented above.
- App users never need Sentry accounts.
- The DSN is public. The authentication token is secret.
- `0.10.0` is preferred over `0.9.1`: the integration adds a diagnostic subsystem and consent/settings behavior, making it a pre-1.0 minor release rather than a patch.
- Apple-generated `.ips` reports remain the authoritative fallback for complex crashes.
- Current references:
  - [Sentry Cocoa SDK](https://github.com/getsentry/sentry-cocoa)
  - [Sentry pricing](https://sentry.io/pricing/)
  - [Apple crash-report collection](https://developer.apple.com/documentation/xcode/acquiring-crash-reports-and-diagnostic-logs)
  - [Apple debugging symbols](https://developer.apple.com/documentation/xcode/building-your-app-to-include-debugging-information)
