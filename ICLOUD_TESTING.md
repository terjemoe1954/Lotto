# iCloud verification before release

The app keeps the existing `iCloud.iCloude.com.terjemoe.Lottery` container and
existing store. SwiftData retains automatic CloudKit configuration, which uses the private database
from the existing single-container entitlement in signed builds. The added
`LotteryDeliveryChange` model records mark and unmark actions without changing
existing Lotto or international row fields.

The iCloud account panel reports account availability only. It does not report a
successful upload/download or a completed synchronization. Data remains local
when offline; the framework handles later synchronization.

## Automated coverage

Tests cover additive migration of an existing disk store, reopening persisted
marks, legacy UserDefaults import, idempotency, stable resolution of duplicate and
out-of-order changes, preservation of unmark actions, local monotonic timestamps,
and current/legacy backup formats. These tests simulate record merging; they do
not prove transport through Apple's servers.

Delivery changes resolve by timestamp, with a stable change-ID tie break. Legacy
positive marks receive a baseline timestamp so a late import from another device
cannot override a newer explicit unmark. False changes are retained. The event
history must not be deleted simply because a row is currently unmarked.

## Two-device check

1. Export a full backup before installing the update on an existing-data device.
2. Use signed builds of the same app on two devices signed into the same iCloud
   account. Confirm both builds use the same CloudKit environment and container.
   Open Settings and check account access. A status of Available is only a prerequisite.
   Unsigned simulator builds skip CKContainer account checks and show a device-check
   message instead; they can still run local tests without CloudKit entitlements.
3. Create a Lotto row on device A. Confirm the row appears on B. Mark it registered
   in the Weekly report on A, then confirm the gray mark appears on B and in the
   older Mine rekker screen.
4. Unmark the row on B. Confirm A removes the mark. Reopen both apps and confirm
   the old local legacy mark does not reappear.
5. Repeat with Vikinglotto and Eurojackpot, including two different draw dates in
   the same week. Verify marks and exported reports refer to the correct date/game.
6. While one device is offline, change a mark. Reconnect, allow synchronization and
   verify both devices converge. Also change different rows independently on each
   device. Do not assume immediate delivery, or use old app versions in this check.
7. Export and restore a full backup. Confirm both positive and removed marks are
   reflected on the other device after synchronization. A draws-only import must
   not change delivery status. A backup predating delivery marks leaves them intact.
8. On a separate test environment without an iCloud account, verify local rows,
   marks, report export and backup still work. Do not sign out a personal device
   merely to perform this check.

## TestFlight / App Store

- Develop and verify the new model using signed development builds first.
- Inspect the existing container in CloudKit Console. Deploy the additive schema,
  including the new delivery-change record type and international model types, to
  Production before testing TestFlight/App Store builds.
- Do not reset the container, rename the existing container or delete old types.
- Repeat the two-device check using production builds. Development and Production
  are separate environments; a successful Debug test does not prove Production works.
- Review privacy disclosures before distribution. Own rows and delivery status use
  the user's private database; no new shared public database is introduced here.

Common draw history still uses the existing SwiftData store and its configured
sync behavior. Moving it into an independent local cache is a separate data-store
migration and has not been performed in this change. Local display preferences
(such as hiding registered rows) remain device-specific. Full exported backups
remain available alongside synchronization.

References: [SwiftData synchronization](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices),
[CloudKit schema deployment](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema).

## Device verification on 2026-11-10

The same signed Debug build was installed as an update on an iPhone 15 Pro and
an iPad (10th generation), without uninstalling the app. The user confirmed the
devices use the same iCloud account and that account access was Available on both.

Verified basic flow:
- A new Vikinglotto row saved on iPhone appeared on iPad.
- A registered mark set on iPhone reached iPad. A read-only diagnostic snapshot
  confirmed the same change identifier and value in both stores.
- The mark was removed on iPad. The iPad store contained the newer false change
  and reported a successful export after that change. The user subsequently
  confirmed the mark was removed on iPhone after unlocking and reopening Lotto.

Observed limitation: propagation was delayed. The iPhone had not started a new
import in the inspected interval, and a later diagnostic relaunch was blocked
while the phone was locked. This test establishes basic two-way delivery and
undo behavior; it does not establish immediate background delivery.

Temporary device-database snapshots used for diagnosis were deleted from the Mac
after inspection. No diagnostic snapshot was written back to either device.

Still pending before release: the offline/concurrent-edit checks, cross-device
backup restoration, and equivalent tests with the Production schema and
TestFlight builds. No production-schema deployment or App Store submission was
performed during this test.

## Offline and backup checks on 2026-11-10

Physical offline check confirmed by the user:
- With iPad in airplane mode and Wi-Fi off, the Vikinglotto test row was marked
  registered. The mark remained after closing and reopening Lotto while offline.
- After reconnecting iPad, the user confirmed that the offline mark appeared on
  iPhone. This verifies offline persistence and eventual upload/download in this flow.

The Settings backup workflow now delegates to LottoBackupStore, shared with the
integration tests. Full restore validates numbers/dates and status records before
replacing data; replacement deletes are staged until the final save. Draws-only
import leaves personal rows and registration changes intact.

The new Check backup file action trial-restores the selected file into an
independent, local, in-memory database with CloudKit disabled. Full backups are
compared for Lotto data, international data and positive/removed registration
status. The check does not replace device data or publish anything to iCloud.

Automated tests additionally cover offline disk reopen, ISO-8601 JSON file round
trip into a second disk store, malformed/truncated files, legacy full backups,
idempotent draws-only imports, isolated change merging and the complete bundled
archive. A physical full-restore-over-existing-data test and concurrent edits on
two physical offline devices remain outside the checks completed so far.

## Exported-file regression on 2026-11-10

The user's actual exported full backup was initially rejected because one older
own Lotto row contained an out-of-range number. This is a domain-data warning,
not proof of a corrupt backup container. The compatibility fix preserves old own
rows exactly and reports those issues; draw data, unreadable dates and malformed
files remain validated. Current row-entry validation is unchanged.

The actual exported file was decoded and trial-restored through LottoBackupStore
in an isolated in-memory database on the Mac. It passed content comparison for
885 own Lotto rows, one own Vikinglotto row, 3,584 draws and registration status.
The single historical data issue was preserved and reported. The original JSON
file and the device databases were not modified by this check. Regression tests
cover lossless recovery of such historical rows and unchanged new-entry rules.

## Favorites follow-up

Favorites add a new private-CloudKit model, LotteryFavoriteChange. The existing
container and all older row/change model fields are retained. The local first-run
prompt flag is not synchronized; favorites and enabled/disabled/cleared choices
are synchronized per game. Backup restore retains old-backup compatibility.

Automated coverage includes favorite validation, inclusion in every suggestion
mode, separate extra pools, limited unique-combination counts, deterministic
completion fallback, disable/clear resolution, additive disk migration and backup
round trip. Actual favorite propagation between the physical iPhone and iPad still
needs its own verification. Deploy the new favorite record type to Production
before testing it through TestFlight.
