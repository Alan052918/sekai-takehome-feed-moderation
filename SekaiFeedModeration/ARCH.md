# Sekai Feed Moderation Architecture

## Goals and constraints

- Target iOS and iPadOS 15 using Apple frameworks only: SwiftUI, Combine, UIKit, and WebKit. Set app and test deployment targets to 15.0 during platform setup; the current project template uses 26.5.
- Use feature-scoped MVVM with explicit dependency injection.
- Keep moderation visibility as the single shared source of truth.
- Derive every visible list from fetched items and moderation state; never remove items independently in views or action handlers.
- Keep at most three `WKWebView` instances alive and start playback only for the settled feed item.
- Keep the implementation within roughly six focused hours, including measurement, the submission README, and the screen recording.

## System overview

```text
App Root ── explicit dependencies ──┬─ FeedViewModel ───── API
                                    ├─ CreatorViewModel ── API
                                    └─ ModerationStore ─── API + UserDefaults
                                             │
                                   visibility-only publisher
                                      ┌───────┴────────┐
                                   Feed            Creator
                                      │
                              UICollectionView pager
                                      │
                          ≤3 WKWebViews + playback state
```

The app root constructs the live API client and the app-scoped `ModerationStore`, then injects them into feature view models. The store and view models use `@MainActor` and `ObservableObject`/`@Published`; UIKit and WebKit updates also stay on the main actor. Navigation, dialogs, loading indicators, and toast presentation remain UI state rather than global business state.

## Core boundaries

### Domain

Immutable value types represent `Sekai`, `CreatorProfile`, `CreatorGamesPage`, and `VisibilitySnapshot`. The backend `game_id` is the stable identity everywhere, including Combine projections and collection snapshots.

### Networking

`SekaiAPIClient` exposes async operations for the feed, creator profile, creator games, creator blocking, and content reporting. The live implementation:

- builds requests with `URLComponents`;
- decodes explicit `snake_case` coding keys;
- handles the feed's bare-array response separately from `{code, message, data}` responses;
- validates both HTTP success and backend `code == 0`;
- receives its base URL and `URLSession` as dependencies.

The localhost mock uses a narrowly scoped local-network ATS allowance. The mock server remains unchanged.

### Visibility and moderation

`VisibilityProviding` exposes the current `VisibilitySnapshot` and a Combine publisher that immediately emits the current value to new subscribers. Both feature view models derive their visible items through the same rule:

```text
visibleSekais = fetchedSekais
    - sekais whose creator is blocked
    - individually reported sekais
```

`ModerationStore` is the only shared mutable domain store. It loads blocked creator IDs and reported game IDs from `UserDefaults` before either screen starts fetching, so hidden content cannot flash on launch. Each action saves the updated hidden sets and publishes the new visibility snapshot without awaiting a network request. This supports normal app restarts; it does not claim synchronous disk durability on an abrupt process kill.

Block and report operations are local-first: content disappears immediately and is never restored after a network failure. After the local change, the store makes one POST attempt per new action and retains that task independently of the originating screen. Repeated taps for the same hidden ID do not submit duplicate requests. There is no outbox or automatic retry across activation or restart; server delivery is best-effort and the README documents that limitation. No backend idempotency guarantee is assumed.

The app root presents short moderation toasts: an immediate local confirmation, then a failure message if the server request fails. Feature views do not own the network task, allowing a creator page to dismiss immediately while its block request continues.

## Requirement 1: Feed

`FeedViewModel` owns the raw, ordered, deduplicated feed stream plus cursor, loading, retry, and terminal-page state. It derives `visibleItems` with `CombineLatest(rawFeed, visibility)`. Requests use a fixed `limit = 6` and a zero-based `refresh` page index. Only one page request may be in flight; success increments `refresh` by one, while retry reuses the failed page index. A raw response containing fewer than six items marks the feed terminal. Filtering and deduplication never determine the cursor or end-of-feed state.

A `UIViewControllerRepresentable` wraps a vertical `UICollectionView` with paging enabled, zero item spacing, and cells sized to its viewport. On bounds changes, update cell sizes and recenter the selected stable ID before resuming playback. A diffable data source applies stable `game_id` snapshots. UIKit retains high-frequency offset and gesture state internally and reports only coarse events such as near-end and settled item ID.

The pager owns up to three `WKWebView` slots for the previous, current, and next items; cells never create WebViews. The current item has loading priority, neighbor loads are serialized, collection prefetching is disabled, and cells outside the active window show lightweight placeholders. Each slot carries a load generation so a completion from recycled content cannot trigger playback. Before reassigning a slot, invalidate its generation, finish any in-flight playback command, confirm the old content is paused, and stop its old navigation. Cell detachment may happen immediately, but the slot cannot be reused while a playback command is pending; command failure follows the shutdown policy below. Generation checks do not replace cancellation or releasing cell references.

One playback coordinator owns the desired item, actual playing item, slot readiness, scrolling state, feed visibility, scene activity, and a transition generation. Its invariant is **at most one playing item, with the ready, settled item playing whenever the feed is visible and active**; zero may play during transitions, loading, or failures.

- Ordinary touches inside a settled sekai preserve playback and interaction. Pause when feed dragging begins, before programmatic scrolling, and on removal, reuse, navigation away, or scene inactivity.
- Determine settlement after dragging ends without deceleration, deceleration ends, or programmatic scrolling completes. Play only after page alignment is verified; passing over a visible cell never starts it.
- Serialize JavaScript commands: await successful `sekaiPause()` completion on the previous player, then recheck the transition generation, desired ID, slot generation/readiness, alignment, visibility, and scene activity before issuing `sekaiPlay()`. Reconcile again after each command completes so a changed target cannot leave stale playback running. A failed pause leaves playback uncertain: withhold the next play and stop, detach, and release that WebView before recovery.
- A memory warning releases both neighbor WebViews, including their cell references, and retains the current one. Current playback still follows the same eligibility checks; rebuild neighbors only after subsequent user navigation.

Navigation failures or a failed play command mark the slot unready and show a lightweight retry control while keeping report/block available. A failed play may have partially executed: pause or release that slot before allowing another player. Handle `webViewWebContentProcessDidTerminate` by invalidating the slot generation and clearing its ready/playing state. Reload the affected current item once if it is still desired, visible, and active; defer hidden slots until needed and offer explicit retry after another failure. App-process death requires no pause command. Every load completion re-enters the coordinator rather than playing directly.

Pagination is requested within two visible items of the end. Automatic loading scans no more than three consecutive fully filtered pages per trigger, preventing an infinite loop when no future content is visible; the UI then offers an explicit retry/load-more action.

## Requirement 2: Moderation actions

Feed controls send intentions to `ModerationStore`; they never edit `visibleItems`. Blocking adds a creator ID, while reporting adds a game ID and submits the fixed wire reason `spam`. Label the action "Report as spam" so its meaning is clear; a reason picker is outside the initial scope.

On a visibility change, preserve selection by stable ID if it survives. If the selected item is removed, immediately hide/detach its cell and request its pause without delaying the visible removal for JavaScript completion. Apply the new snapshot, choose the nearest surviving successor or otherwise predecessor, and recenter without animation. The replacement plays only after the pager is stationary and the coordinator has completed the previous player's shutdown. With no survivors, clear selection and show the empty/loading state.

Both hidden sets survive restart, and later feed or creator pages are filtered through the same visibility projection. Local confirmation says "Creator blocked on this device" or "Content hidden on this device". Submission failure says "Still hidden on this device; the server request failed. It won't retry automatically." Failed moderation never restores the content or claims successful server delivery.

## Requirement 3: Creator page

An iOS 15 stack-style `NavigationView` presents the creator screen. Because feed cells are hosted inside UIKit, creator taps return a stable route to the parent SwiftUI view instead of navigating directly from a cell-hosting controller.

`CreatorViewModel` loads `userProfile` and the first `userGames` page concurrently, tracks their errors independently, and paginates games using the server's `page` and `has_more` values. Game pages start at zero, advance only after success, and allow one request at a time. Its visible games are derived from raw pages and the shared visibility publisher. Apply the same bounded scan/load-more behavior as the feed when reported items hide a full page; an empty visible list alone does not mean there are no more games.

The screen renders native profile text and a stable-ID list of lightweight sekai titles and metadata; game rows create no WebViews. The mock's avatar is SVG, so a single small, noninteractive `WKWebView` loads the profile's avatar URL, with initials as a loading/error fallback. Its accessible top-right `⋯` menu remains available even if profile loading fails because the creator identity came from the feed. Blocking synchronously hides the creator's work, starts the request through `ModerationStore`, and returns to the feed while the app-root toast remains visible. An already-blocked route dismisses without fetching.

The three-WebView cap applies across both screens. Before creating the avatar WebView, suspend the feed pager, finish playback shutdown under the same command policy, and stop/detach/release all feed WebViews, preserving fetched metadata and the selected game ID. Pager callbacks cannot allocate while suspended; the creator screen can show its native header and avatar placeholder during teardown. On return, release the avatar WebView before rebuilding the feed window and revalidate selection against current visibility. Reloading the selected sekai on return is an intentional trade-off for simple ownership and bounded memory.

## Verification strategy

- Keep a small unit suite around the rules: shared filtering across screens and future pages, persistence/restart, failure without rollback, API response shapes, pagination retry/end detection, and ordered deduplication.
- Test the playback coordinator with fake WebView controls whose completions can be delayed or failed: pause-before-play, target changes during a command, stale loads, backgrounding, current-item removal, and WebContent termination. Check touch interaction, snapping, creator navigation, and retry UI manually; a broad UI test suite is outside scope.
- Build with the iOS 15 deployment floor and check both feed and creator flows, including an all-failure moderation run (`--fail-rate 1.0`) and finite pagination (`--total 40`). Keep the mock server unchanged.
- Profile a Release build against the default 5 MB mock using Instruments after at least 20 rapid swipes and a creator-page round trip. Record device/OS, refresh rate, hitch count and duration (or frame-time percentiles), peak app and WebContent memory, and maximum live WebViews. Publish the numeric results and any changes prompted by them; the live WebView count must never exceed three and no off-screen item may play. Three instances alone are not proof of a memory bound.

## Delivery milestones

1. **Feed:** iOS 15 platform configuration, domain/network foundation, derived feed, pager, bounded WebViews, playback, and an early performance check.
2. **Moderation actions:** persistent hidden sets, one-shot submissions, feed actions, toasts, removal reconciliation, and focused rule tests.
3. **Creator page:** profile/avatar and games paging, shared filtering, creator blocking and dismissal, and WebView ownership across navigation.
4. **Submission:** reserve roughly the final hour for targeted verification, the Release Instruments trace, a short README, and a roughly one-minute screen recording.

Build and check each milestone before moving on. Keep the README short: run instructions, iOS 15 support, local HTTP configuration, scope cuts, numeric frame/memory results, and the best-effort moderation failure policy. The recording must show scrolling, one settled item playing, immediate removal after blocking, scrolling back past hidden items, and blocking from a creator page's `⋯` panel. If time runs short, cut optional preloading or polish and document the trade-off; preserve derived visibility, persistence, settled autoplay, both screens, and the submission evidence.
