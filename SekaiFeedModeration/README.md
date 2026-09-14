# Feed milestone

Open `SekaiFeedModeration.xcodeproj`, select an iPhone or iPad simulator, and run the app. From the repository root start the unchanged backend:

```sh
python3 mock/server.py --total 40
```

The app uses `http://127.0.0.1:8787`. The mock derives content URLs from the request host. `NSAllowsLocalNetworking` enables local HTTP without an arbitrary-load exception. All app and test targets have an iOS 15.0 deployment floor; only iOS/iPadOS platforms are enabled. A physical device needs a reachable development-server address injected at the app root.

Implemented here: six-item cursor pagination; Combine-derived visibility; ordered deduplication; bounded scanning of hidden pages; empty/loading/retry states; vertical viewport paging; stable selection across snapshots and resizing; current-first, serialized content loading; settled-only playback; background/visibility shutdown; content retry and process-termination recovery; and a maximum of three live WebViews. JavaScript commands have a three-second timeout. Content navigation has a thirty-second timeout.

Playback commands are serialized independently from UIKit. A pending play counts as potentially playing. The previous player must pause successfully or be detached and released before another play is issued. Slot objects have immutable identity and a navigation identity check, so retired delegates and stale loads cannot start new playback. Allocation also waits for actual WebView deallocation, accounting for transient WebKit retention after detachment.

The app root owns one persistent `ModerationStore`, injected into the feed model as its visibility source. The `⋯` menu on every feed item offers **Report as spam** and **Block creator**. Both actions update the local hidden sets before sending one best-effort request, so content disappears immediately and remains hidden across later pages and app restarts. The report wire reason is fixed to `spam`.

If a moderation request fails, the item or creator stays hidden and the app shows: “Still hidden on this device; the server request failed. It won't retry automatically.” There is no outbox or automatic retry after a failed request, activation, or restart. Repeating an action for an already-hidden ID sends no duplicate request.

## Verification

Run the focused suite with Xcode's Test action or:

```sh
xcodebuild test -project SekaiFeedModeration.xcodeproj \
  -scheme SekaiFeedModeration -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SekaiFeedModerationTests
```

The suite covers raw-page terminal detection despite duplicates, stable ordering, retrying the failed cursor, bounded hidden-page scanning, visibility reprojection, persisted local-first moderation, duplicate suppression, failure without rollback, moderation wire payloads and backend-code validation, delayed pause-before-play, target changes during a command, failed play/pause recovery, and repeated settled-target updates.

Set the launch environment variable `SEKAI_MEASURE=1` to record cumulative `FEED_METRICS` lines after each drag/deceleration. The opt-in probe uses CADisplayLink intervals during scrolling and counts live WebViews using associated lifetime tokens. It stores at most 100,000 interval samples. These intervals measure main-thread scheduling, not GPU presentation or WebContent frame delivery. Physical-device Instruments measurement and combined app/WebContent peak memory remain part of the final submission milestone.

Early Release check: iPhone 16 simulator on iOS 18.6, default 5 MB mock pages, 20 rapid settled swipes. The final sample reported 591 display-link intervals, p95 16.67 ms, a 276.42 ms maximum interval, 25 intervals over the display budget, and a maximum of three live WebViews. The early run initially showed a transient fourth instance because WebKit retained a detached view; allocation now waits for the associated view's actual deallocation before creating a replacement. This is a guardrail and early scheduler measurement, not the physical-device Instruments evidence required for the final submission milestone.
