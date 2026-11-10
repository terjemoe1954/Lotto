# TestFlight readiness review — 2026-11-10

This is a local preparation review. No App Store Connect upload, production
CloudKit deployment or public release has been performed.

## Verified

- Existing bundle ID and CloudKit container retained.
- Signed development build installs on the paired iPhone and iPad.
- Basic row/registration two-way synchronization and offline reconnect were
  confirmed on those devices, with observed propagation delays.
- The actual exported backup was trial-restored in an isolated database. A legacy
  own-row typing mistake is preserved and reported instead of blocking recovery.
- Optional favorites and a prominent no-increase-in-winning-chances statement are
  implemented. Favorites are fixed in generated rows when enabled, and included
  in full backups. Current tests: 83 passing simulator tests plus a signed iOS build.

## Before TestFlight distribution

- Project currently declares version 1.1, build 5. Inspect the App Store Connect
  record and its latest build before choosing the next unique build/version.
- Deploy all additive CloudKit schema types to Production, including delivery
  changes and the new favorite-change type. Repeat transport checks in TestFlight;
  development-build success is not Production verification.
- Verify favorite propagation on the two physical devices separately; this has
  automated merge/backup coverage but no confirmed physical favorite test yet.
- Privacy manifest now declares the app-local UserDefaults reason CA92.1.
  Review App Privacy answers separately before submission.
- Publish docs/privacy.html on the publisher's GitHub Pages site, then add its
  verified public URL to App Store Connect. In-app privacy/contact text uses
  terjemoe54@hotmail.com. Review App Privacy answers against
  actual CloudKit and Norsk Tipping requests; do not infer them solely from the UI.
- Prepare screenshots. Suggestion modes now use Historikk/Blandet/Variasjon;
  historical interval dates explicitly do not predict the next draw.
- APP_STORE_REVIEW.md contains draft metadata and review notes. Confirm the
  final content against the submitted build.

## Before public App Store release

- Clarify authorization/terms and reliability for the Norsk Tipping result API
  and redistributed historical data. Working public endpoints alone do not
  establish permission for a published product. No correspondence has been sent.
- Review branding so the app is clearly independent of Norsk Tipping and Apple.
- Document the actual feature set in Review Notes: historical statistics,
  own-row management, suggestions and export; no ticket sale, stake acceptance
  or payout. Apple makes the classification decision under its gambling rules.
- Complete age-rating and metadata questionnaires based on actual features. No
  promised approval or claim of higher winning probability should be included.

Sources: [Apple review guidelines](https://developer.apple.com/app-store/review/guidelines/),
[App Review preparation](https://developer.apple.com/app-store/review/),
[CloudKit schema deployment](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema).
