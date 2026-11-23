# Repository audit (ponytail-audit)

Audit done on 2026-11-23 with the [ponytail](https://github.com/dietrichgebert/ponytail) `ponytail-audit` skill, on `main` at `f5e83d0`.
Findings marked **(fixed in this PR)** have a small fix in the same pull request. Everything else is a report only.

**What this repo does:** A menu bar app for macOS that talks to Nothing and CMF earbuds and headphones over Bluetooth. It opens a serial channel (RFCOMM, a Bluetooth "cable") to the device, sends small binary commands (noise control, EQ, gestures, ring) and reads back battery and settings. Settings and saved devices are kept in two JSON files in the app's sandbox.

**Load assumed:** one person, one Mac, one connected device at a time, but the app runs for days (sleep/wake, many menu bar opens, devices coming and going).

## Must fix

1. **A device with no serial number was treated as an Ear (1)** (`framework/NothingServiceImpl.swift` `readSerial`, `framework/utils/SKUUtil.swift` `skuFromSerial`) **(fixed in this PR)**
   - **What this is:** After connecting, the app asks the device for its serial number and uses it to guess the model.
   - **Problem:** When the answer has no serial line, the code made up the serial `12345678901234567`, and `skuFromSerial` maps that fake serial to Ear (1). This overwrote a model already known from the device name or saved config, so a Headphone (1) or any new model could become "Ear (1)": wrong icon, wrong features (case LED), wrong ring command. The fake number was also shown as the serial in Settings.
   - **Fix:** No fake serial. If the answer has no serial, keep the model already known; only fall back to Ear (1) when nothing else identifies the device (same as before for real Ear (1) units).
   - **If we skip it:** Newer devices are shown and driven as an Ear (1) as soon as the serial answer arrives.

2. **A quick second setting change could be undone by the first one's retry** (`framework/NothingServiceImpl.swift` `processNextRequest`) **(fixed in this PR)**
   - **What this is:** Commands go through a queue; a command that gets no answer in 1 s is retried up to 3 times.
   - **Problem:** The retry was put at the *end* of the queue. Tap "ANC" then "Transparency": if the ANC command times out, it is resent *after* Transparency, so the buds end up in ANC while the UI shows Transparency.
   - **Fix:** Put the retry at the front of the queue (`insert(request, at: 0)`).
   - **If we skip it:** On a weak link, the buds sometimes end in a different mode than the one the user picked last.

3. **Any incoming packet moves the queue on, so commands lose their answer** (`framework/NothingServiceImpl.swift` `processPacket`, last lines)
   - **What this is:** After every packet received, the code calls `processNextRequest()`.
   - **Problem:** Devices also send packets nobody asked for (battery, charging status, ear detection). If one arrives while a command waits for its answer, the next command is sent and `currentRequest` is replaced. The real answer then matches nothing, so the first command's success handler never runs: e.g. `switchANC` never sets `nothingDevice?.anc`, and the UI keeps the old mode until the next refresh. `setRingBuds` also writes directly to the channel outside the queue, which has the same effect.
   - **Fix:** In `processPacket`, only call `processNextRequest()` when the packet's operation id matches `currentRequest` (or when there is no current request); let the timeout handle the rest. Route `setRingBuds` through `addRequest`. Needs testing on real hardware, because some devices may answer with a different id and would then wait for the 1 s timeout.
   - **If we skip it:** Settings sometimes look like they did not apply, and the UI shows stale values.

4. **The command queue is used from three threads without a lock on every path** (`framework/NothingServiceImpl.swift` `fetchData`, `processNextRequest`, `processPacket`; `framework/BluetoothManager.swift` `connectToDevice`)
   - **What this is:** `fetchData` and the request timeout run on a background queue (`DispatchQueue.global()`); received data runs on the main thread.
   - **Problem:** `processPacket` reads `currentRequest` without the semaphore while a timeout on another thread writes it. Timeouts also call completions and `send()` from the background, so `@Published` device properties change off the main thread and IOBluetooth is written from a random thread. In `BluetoothManager.connectToDevice`, `isConnecting` is checked and set on a background queue, so two connects fired together (Bluetooth-on plus system-connect at launch, or the 30 s reattach timer) can both pass the check.
   - **Fix:** Do all queue and Bluetooth work on the main thread: replace the `DispatchQueue.global()` calls in `fetchData`/`processNextRequest` with `DispatchQueue.main`, then remove `queueSemaphore`. Check and set `isConnecting` on the main thread before dispatching the blocking `openConnection()`.
   - **If we skip it:** Rare crashes and "Publishing changes from background threads" warnings; occasional double connect attempts.

5. **Disconnecting during a channel retry blocks all future connects** (`framework/BluetoothManager.swift` `handleChannelOpenFailure`, `disconnectDevice`)
   - **What this is:** If the control channel fails to open, the app retries after 1.5 s; `isConnecting` stays `true` until a retry ends.
   - **Problem:** If the user disconnects inside that 1.5 s, `device` becomes `nil`, the retry block returns early, and nothing sets `isConnecting` back to `false`. Every later connect logs "Connection attempt already in progress" and does nothing until the app restarts.
   - **Fix:** In `disconnectDevice()`, add `isConnecting = false` and `channelOpenGeneration += 1`.
   - **If we skip it:** The app looks stuck and the user has to quit and reopen it.

## Should fix

6. **Saved devices list used the serial as its row id** (`presentation/window/NXConnectScreen.swift`, `presentation/window/NXMyDevicesScreen.swift`) **(fixed in this PR)**
   - **What this is:** SwiftUI `ForEach(..., id: \.serial)` lists the saved devices.
   - **Problem:** Two devices with the same serial (both empty before the serial is read, or both the old fake serial) have the same id. SwiftUI then shows the wrong row or drops one.
   - **Fix:** Use the MAC address: `id: \.bluetoothDetails.mac`, which is also the key the JSON store uses.
   - **If we skip it:** With two saved devices, one can vanish from "My devices" or tapping one connects the other.

7. **Settings files could be lost if the app quit mid-write** (`data/JSON/JsonEncoder.swift`, `data/EQPresetStorage.swift`) **(fixed in this PR)**
   - **What this is:** Saved devices and EQ presets are written with `data.write(to:)`.
   - **Problem:** A plain write replaces the file in place. A crash or power loss in the middle leaves a half file; on the next launch decoding fails, the list starts empty, and the next save overwrites the old data for good.
   - **Fix:** `write(to:options: .atomic)`, which writes a temp file and swaps it in.
   - **If we skip it:** Users occasionally lose their saved devices and custom EQ presets.

8. **The noise control view model leaked on every menu bar open** (`presentation/models/NoiseControlViewViewModel.swift`) **(fixed in this PR)**
   - **What this is:** The quick panel creates a new `NoiseControlViewViewModel` each time the popover opens.
   - **Problem:** Its notification observer held `self` strongly and was never removed, so every old instance stayed alive and kept animating on every device update. After a few hundred opens, each battery report runs hundreds of handlers.
   - **Fix:** Keep the observer token, capture `[weak self]`, remove it in `deinit` (same pattern as `SettingsViewViewModel`).
   - **If we skip it:** Memory and CPU slowly grow for as long as the app runs.

9. **No test covers the packet parser or model detection** (`Nothing X MacOSTests/Nothing_X_MacOSTests.swift`)
   - **What this is:** The only unit test file is the Xcode template, and CI only builds.
   - **Problem:** The riskiest logic is pure functions with no Bluetooth needed: `codenameFromDeviceName`, `skuFromSerial`, `onDataReceived` splitting several packets, `readBattery`, `CRC16`. A wrong change there (e.g. reordering the `"buds 2"` / `"buds 2 plus"` checks) breaks a device and nothing fails.
   - **Fix:** One test file with a handful of byte arrays captured from real devices and the expected model/battery. Make the parse helpers `internal` (or `static`) so the test can call them.
   - **If we skip it:** Model detection regressions are found by users.

10. **About 3,400 lines of the old UI are no longer used** (`presentation/views/*` except `ModalSheetView.swift`, most of `presentation/views/Components/*`, `presentation/animations/PulsingCirclesAnimation.swift`, `presentation/models/{BatteryIndicatorView,BluetoothIsOff,BudsPickerComponent,FailedToConnectView}ViewModel.swift`)
    - **What this is:** The app now starts `NXQuickPanel` and `NXWindowView` (`presentation/window/*`). The older `HomeView`, `ConnectView`, `SettingsView`, `EqualizerView`, `ControlsView`, `FindMyBudsView`, etc. are only referenced by each other.
    - **Problem:** 26 files (about a quarter of the Swift code) are still compiled, still show up in searches, and must be kept building. Example: `BatteryIndicatorViewViewModel` has the same observer leak as finding 8, in code nobody runs.
    - **Fix:** Delete those files (checked by following references from `Nothing_X_MacOSApp.swift`; Xcode must also drop them from the project). Left out of this PR on purpose, to avoid clashing with the UI work on device support happening in parallel.
    - **If we skip it:** Every UI change has to be checked against two UIs, one of them dead.

11. **Request completions report failure and then success for the same command** (`framework/NothingServiceImpl.swift` `processNextRequest`)
    - **What this is:** On a timeout with retries left, the code calls `completion(.failure)` and re-queues the request.
    - **Problem:** If the retry then succeeds, the same completion runs again with `.success`. Today callers only log on failure, so the effect is noise in the logs, but any future caller that reverts state on failure would revert a change that worked.
    - **Fix:** Only call the completion when the request is finally done (success or last retry).
    - **If we skip it:** Misleading "Failed to …" logs now, and a trap for the next feature.

## Nice to have

12. **Saved-device lookups only see the 5 most recent devices** (`data/NothingRepositoryImpl.swift` `getSaved`)
    - **What this is:** `getSaved()` returns at most 5 devices; `NothingServiceImpl` uses it to restore a device's model on connect.
    - **Problem:** A 6th saved device is still stored, but its saved model and name are not restored, so it falls back to name detection.
    - **Fix:** Use `JsonEncoder.shared.getAllDevices()` (or a `find(mac:)`) for lookups; keep the limit only for the list on screen.

13. **Serial numbers and MAC addresses are logged as public** (`framework/utils/NXLogger.swift`)
    - **What this is:** Every log message uses `privacy: .public`.
    - **Problem:** Serials and MACs land in the system log readable by any admin or sysdiagnose.
    - **Fix:** Log serial/MAC with `privacy: .private`, or keep `.public` only for messages without identifiers.

Verdict: The protocol layer works for the happy path, but the command queue (findings 2 to 5) is where real users see wrong or stale settings. Fix 3 and 4 next, with a device in hand.

Lean: -3,400 lines possible (finding 10), -0 dependencies (there are none).

Not checked: nothing was built or run (no macOS/Xcode in the audit environment, no device), so every finding comes from reading the code. Read in full: `framework/*`, `data/*`, `NothingServiceImpl`, `BluetoothManager`, `SKUUtil`, the app entry point and the view models. Skimmed: the SwiftUI screens in `presentation/window/*` and `NXTheme.swift`. Not checked: the custom EQ byte layout and the per-model capability table against real devices, and the CI/release workflow and device icons (handled in separate pull requests).
