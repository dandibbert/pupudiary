# Signing and installing Pupudiary

The CI artifact `Pupudiary-unsigned.ipa` is a **real arm64 iPhone build**, containing the app and its WidgetKit extension. It deliberately contains **no signing certificate, provisioning profile, or install authorization**. It cannot be installed as-is. A successful unsigned build does not establish that a particular certificate/sideloading service supports widgets.

## Required identifiers

| Component | Identifier | Required capability |
| --- | --- | --- |
| Main app | `com.dandibbert.pupudiary` | App Groups |
| Embedded widget | `com.dandibbert.pupudiary.widget` | App Groups |
| Shared container | `group.com.dandibbert.pupudiary` | Both targets belong to this exact group |

The main app and widget must be signed by the same Apple Developer team with matching authorized profiles. An app profile alone is insufficient: the extension has a separate bundle ID and needs its own profile. App Group membership must be present in **both provisioning profiles and both final code signatures**. Adding text to an entitlements file cannot create entitlement authorization.

If these identifiers are already registered to another team, register your own explicit app and widget identifiers and App Group, then change all of these before building:

- `PRODUCT_BUNDLE_IDENTIFIER` for both targets in `project.yml`
- The App Group string in both `Config/*.entitlements`
- The same group string in `Shared/StorageLocation.swift`
- Any bundle IDs passed to screenshot/validation scripts, where relevant

Do not let a signing tool silently rewrite only the main bundle ID or strip an extension/capability. A renamed App Group in the signature alone does not change the hard-coded shared-container identifier in the app.

## Recommended: build and sign locally in Xcode

1. On a Mac, install Xcode and XcodeGen (`brew install xcodegen`). Clone this repository, run `xcodegen generate`, and open `Pupudiary.xcodeproj`.
2. In Xcode, select your Apple Developer team for **Pupudiary** and **PupudiaryWidgetExtension**. Enable App Groups for both and select `group.com.dandibbert.pupudiary` (or your consistently renamed group).
3. Allow Xcode to create/update two appropriate profiles, or select your existing profiles. For a development/ad-hoc install, ensure the target iPhone is included in **both** profiles.
4. Choose the `Pupudiary` scheme and your connected iPhone. Build and run, or archive and use an appropriate authorized distribution method. Keep the extension inside `Pupudiary.app/PlugIns/`.
5. If iOS requests Developer Mode or trust approval, review and complete that on the iPhone yourself. Availability depends on the signing/distribution method.

Xcode signing is the most reliable route because it handles nested target signing and profile selection. A certificate is not enough by itself; its profiles must authorize both bundle IDs, device/distribution method, and App Group. Do not assume a free Personal Team or a third-party certificate plan can grant App Groups; verify the actual entitlements supplied by that account/provider.

## Using an existing certificate/sideload signer

Use a trusted local signing tool that explicitly supports **app extensions and App Groups**, with separate profiles for the app and widget. Keep `.p12` files, private keys, profile files, account credentials, and certificate passwords on your own device. They are not needed by this repository or its GitHub Actions workflow; do not upload them to issues, commits, Actions artifacts, or chat.

The tool must:

1. Preserve `Payload/Pupudiary.app/PlugIns/PupudiaryWidgetExtension.appex`.
2. Embed the correct profile into each target as `embedded.mobileprovision`.
3. Set each target's `application-identifier`, team, and App Group entitlement from authorized profile values, without inventing permissions.
4. Sign nested components first, then the main app, using matching team/certificate identity. Do not use `codesign --deep` as a substitute for correctly signing each target.
5. Produce an IPA containing the complete `Payload/Pupudiary.app` directory.

The repository does not endorse or require uploading your certificate to an online signing service. If your provider cannot supply the needed App Group and extension profile, ask it for those capabilities or use your own eligible Apple Developer account.

## Offline verification on a Mac

After signing, from the repository root:

```sh
python3 scripts/validate-signed-ipa.py /path/to/Pupudiary-signed.ipa
# Optional: verify both profiles allow the intended iPhone as well
python3 scripts/validate-signed-ipa.py /path/to/Pupudiary-signed.ipa --udid YOUR_DEVICE_UDID
```

For consistently renamed identifiers:

```sh
python3 scripts/validate-signed-ipa.py /path/to/Pupudiary-signed.ipa \
  --app-id com.yourteam.pupudiary \
  --widget-id com.yourteam.pupudiary.widget \
  --group group.com.yourteam.pupudiary
```

This is read-only/offline verification. It checks ZIP structure, iPhone arm64 platform, app icons, embedded extension, code signatures, profile expiry, bundle/team identity, signing certificate membership in each profile, certificate expiry, entitlement allowlists, and matching App Group capability. It does not request certificates or upload files. It cannot establish certificate revocation status, Apple's online trust decisions, install eligibility, or actual on-device widget behavior.

## If App Groups are unavailable

Pupudiary can keep app-only records in its private app container when the shared container cannot be opened. The app makes the sharing limitation visible. **The widget cannot read or write those private records.** Its interactive logging must not show false success when the group is unavailable.

An app-only fallback requires a genuinely valid signature/profile combination. If the profile does not authorize App Groups, the signer must omit that unsupported entitlement from **both** signatures; leaving an unauthorized entitlement may prevent installation. The validator rejects missing sharing capability by default. To acknowledge the limitation explicitly:

```sh
python3 scripts/validate-signed-ipa.py /path/to/Pupudiary-signed.ipa --allow-no-app-group
```

That flag only permits verification of the app-only signing fallback. It does not enable widget sharing, remove the extension, or claim widget integration works. Keep the extension intact so capability can be restored later.

## On-device acceptance checklist

- Open the signed app and confirm there is no shared-container warning
- Add a record and confirm the daily count changes
- Add Pupudiary's widget through the iPhone's normal Home Screen widget gallery
- Confirm the widget shows the same count/latest-record state as the app
- Tap the widget's one-tap logging control; reopen the app and confirm **one** new record
- Tap rapidly/repeatedly and verify the short duplicate-tap protection works
- Undo the recent record in the app, then verify the widget updates
- Background/force-close and reopen the app; confirm records persist
- Test around midnight/time-zone changes and with small/large widget sizes
- Test the discreet display setting if you use your phone where others can see it

Widget timeline refresh is controlled by iOS; a screenshot from an in-app widget preview does not prove timeline delivery, App Intent execution, or App Group signing on a physical iPhone.

## References

- [Apple: App Groups entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.application-groups)
- [Apple: Inside Code Signing — Provisioning Profiles](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles)
- [Apple: Configuring App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups)
