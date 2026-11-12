# TestFlight readiness review — 2026-11-10

This review began on 2026-11-10. Update on 2026-11-12: the additive CloudKit schema has been deployed to Production after explicit approval. TestFlight internal build 1.1 (7) was uploaded on 2026-11-12 and bidirectional Production ledger transport was verified on the physical iPhone and iPad. No public App Store release has been performed. See ICLOUD_TESTING.md for the exact verified scope.

## Verified

- Existing bundle ID and CloudKit container retained.
- Signed development build installs on the paired iPhone and iPad.
- Basic row/registration two-way synchronization and offline reconnect were
  confirmed on those devices, with observed propagation delays.
- The actual exported backup was trial-restored in an isolated database. A legacy
  own-row typing mistake is preserved and reported instead of blocking recovery.
- Optional favorites and a prominent no-increase-in-winning-chances statement are
  implemented. Favorites appear in one generated row when enabled, and are included
  in full backups. Current tests: 86 passing tests on each simulator format plus a signed iOS build.

## Before TestFlight distribution

- Project currently declares version 1.1, build 8. This build is available in the existing Internal TestFlight group and installed on both physical devices. Automatic stakes/prizes and bidirectional Production delivery-mark propagation passed; see ICLOUD_TESTING.md. Verify App Store Connect before choosing the next unique build number.
- Production schema deployment completed on 2026-11-12, including the ledger type and framework support fields/indexes. TestFlight build 1.1 (7) subsequently verified ledger creation, reverse-direction edits and deletion through Production; see ICLOUD_TESTING.md for the exact scope.
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
  establish permission for a published product. The user has sent a clarification request to Norsk Tipping and is awaiting a reply.
- Review branding so the app is clearly independent of Norsk Tipping and Apple.
- Document the actual feature set in Review Notes: historical statistics,
  own-row management, suggestions and export; no ticket sale, stake acceptance
  or payout. Apple makes the classification decision under its gambling rules.
- Complete age-rating and metadata questionnaires based on actual features. No
  promised approval or claim of higher winning probability should be included.

Sources: [Apple review guidelines](https://developer.apple.com/app-store/review/guidelines/),
[App Review preparation](https://developer.apple.com/app-store/review/),
[CloudKit schema deployment](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema).

## Automatic ledger — source changes after TestFlight 1.1 (7)

Implemented 12 November 2026: derived stakes from synced delivery marks, ordinary
prizes from finalized Norsk Tipping payout tables, pending status for unavailable
payouts, local public-data cache, unmarking from the ledger, and combined monthly
budget/totals. Standard single-row prices are Lotto NOK 5, Vikinglotto NOK 8 and
Eurojackpot NOK 25; accounting uses draw date and dates from 2023. Each unique
game/date/numbers key counts once. Supplementary raffles, Joker and repeat purchases
of an identical row remain manual. Existing manual entries are retained and must
not duplicate the amounts now derived from delivery marks.

No SwiftData/CloudKit model changes. Full backups already contain the delivery log
needed to rebuild automatic stakes; public payout tables are refetched per device.
Saved-row deletion retains the delivered expense; clearing its delivery mark removes it.

Verification of final source:
- 95 tests in 15 suites pass on iPhone 17 and iPad Pro 13-inch (M5), iOS 27.2.
- Nine automatic-ledger tests cover delivery convergence/undo/deduplication, all
  ordinary tiers, correct extra pools, invalid keys, pending jackpots/missing amounts,
  large payouts, backup reconstruction and cache persistence/network failure.
- Release build for generic iOS succeeds with signing disabled.
- Built app installed/launched with explicit simulator UDIDs. Device Hub visual
  inspection and opening/closing Spilleoversikt succeed on both simulators. Existing
  simulator manual entries were not changed; no personal delivery mark was toggled.
- Initial Device Hub timeouts and stalled test startup recovered without resetting
  simulators or restarting Device Hub. Final runs use parallel testing disabled.
- Uploaded and distributed as actual TestFlight 1.1 (8), with Production iCloud;
  installed version/build verified on iPhone 15 Pro and Terje sin iPad 10. All three
  games produced the exact expected stakes and prizes on both devices. Delivery
  marks and their removal propagated in opposite directions. Authorized temporary
  rows were deleted and final snapshots confirmed all original data unchanged.
  Full evidence and retained archive are documented in ICLOUD_TESTING.md.


## Duplicate maintenance — build 9

Settings → Vedlikehold → Rydd dupliserte egne rekker provides preview counts and
keeps one unchanged existing own row per game/draw date/numbers (including extras).
A validated full JSON backup must succeed before individual SwiftData deletions
are saved. Run on one device, then wait for CloudKit propagation. No model/schema
change. This is explicit maintenance; it does not establish a database uniqueness
constraint against future imports or simultaneous offline writes.

99 tests pass on iPad simulator. TestFlight 1.1 (9) uploaded/distributed internally
with Production iCloud, installed on physical iPad. Authorized 897-copy cleanup
synchronized to physical iPhone build 8. Both stores retain all 929 unique own rows
and have zero duplicates; protected data and actual ledger totals are unchanged.
See ICLOUD_TESTING.md and the durable Desktop backup/audit for evidence.


## New duplicate prevention — source after build 9

A shared MainActor own-row insertion guard fetches current context contents just
before insertion, including pending inserts. Manual Lotto and international entry,
Lotto suggestions and international batch suggestions use it. Existing view-level
validation remains for immediate feedback. Keys use game, Europe/Oslo draw day,
sorted main numbers and sorted extra numbers. No CloudKit schema change.
Full backup restore now keeps the first unchanged complete own-row record per key,
leaving draw records, delivery state and the original backup file intact. The backup
check trial-restores the same normalized contents and reports skipped extra copies.

102 tests in 17 suites pass on iPad Pro 13-inch (M5) simulator, UDID
11D4D75C-A33C-49F1-AE17-EB2CBC53AA44. New tests exercise pending/double saves,
reordered numbers, different dates/years/extra pools, draw separation and an old
backup with duplicates and a delivered row. Existing cleanup backup test now
expects one restored row while asserting two originals remain in the backup file.
Test log: /private/tmp/lotto-prevent-tests.log. No personal device data changed.
This source was subsequently uploaded as TestFlight 1.1 (10), installed and tested
on both physical devices; see the verification below. Offline simultaneous creation on separate devices
cannot be made globally unique by a local guard; no uniqueness guarantee is claimed
for that conflict case and no automatic deletion on incoming sync is introduced.


## TestFlight 1.1 (10) physical verification — 12 November 2026

Uploaded successfully and distributed to the existing Internal group. ASC metadata
confirms CloudKit Production, no new model/schema. Actual installed version/build
1.1 (10) confirmed by devicectl on iPhone 15 Pro and Terje sin iPad 10.
All three games rejected attempted duplicate saves on each device: reversed Lotto
numbers produce a validation message and disabled Save; Vikinglotto and Eurojackpot
Save produce the correct already-saved error. Existing synced production rows were
used, with no new test rows or delivery marks. No live backup restore performed.
Final physical-device database snapshots match pre-update backups in every app
model field except Z_OPT: 886 Lotto, 29 own Vikinglotto, 14 own Eurojackpot, zero
duplicates, 52 active marks. Regnskap remains NOK 527 stake, NOK 0 prize and 17
pending rows. Full backup SHA256 hashes unchanged. See ICLOUD_TESTING.md.
