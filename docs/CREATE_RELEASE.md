- To create a new release, run `/scripts/release.sh <version> <notes-file>` with a clean working tree and the notes in `<notes-file>`. It bumps CFBundleVersion, runs tests, builds, signs, notarizes, staples, tags, pushes, and creates the GitHub release with the DMG attached.

- Release prerequisites: notarytool profile `yanmo-notary` in the keychain (one-time: `xcrun notarytool store-credentials yanmo-notary`, using the Wisemind App Store Connect API key). Signing config lives in `project.yml` (Developer ID Application, manual, team S3J499CH5F) — never set team or identity in Xcode only; `xcodegen generate` regenerates the pbxproj and drops it.

- After a release, verify the DMG: mount it and run `spctl -a -t exec` and `stapler validate` on the app; both must pass.