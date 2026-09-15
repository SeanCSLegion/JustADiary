# iOS 27 / Xcode 27 upgrade research for a SwiftUI iOS app

Researched ~2026-09-15 (environment date). Baseline: Xcode 27.0 (27A266a), iOS 27.0 SDK (24A437), macOS 27.0 SDK.

**Release facts.** Apple's [Software Releases page](https://developer.apple.com/news/releases/) lists Xcode 27 (27A266a), iOS 27.0 (24A437) and macOS 27.0 (26A428) as released **September 14, 2026**; iOS 27.0 RC (24A437) was September 11, 2026. macOS 27 is named **Golden Gate**.

**Source-quality convention used below.**
- **[Apple]** = Apple primary source (release notes, docs, technotes, WWDC session, news), with URL.
- **[Symbol]** = Apple documentation metadata (`metadata.platforms[].introducedAt / deprecatedAt`) fetched from the DocC JSON.
- **[Secondary]** = third-party source, explicitly flagged.
- **[Not found]** = I could not find authoritative information; this is *not* a claim that none exists.

A note on method that matters for re-checking: Apple's release-notes and documentation HTML pages are JavaScript-rendered and a plain fetch returns almost nothing. The full article is available as JSON at
`https://developer.apple.com/tutorials/data/documentation/<path>.json`, and Apple also serves Markdown at `https://developer.apple.com/<path>.md`. All release-notes claims below come from the full JSON/Markdown, not the rendered page.

---

## 1. iOS 27: what is new for SwiftUI developers

Primary sources: [WWDC26 "What's new in SwiftUI" (session 269)](https://developer.apple.com/videos/play/wwdc2026/269/), [What's new in SwiftUI](https://developer.apple.com/swiftui/whats-new/), [SwiftUI updates](https://developer.apple.com/documentation/updates/swiftui), [iOS & iPadOS 27 Release Notes › SwiftUI](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes).

### 1a. Liquid Glass APIs — no API changes, but a mandatory new appearance

**Confirmed [Apple]:** Apple's "What's new in SwiftUI" 2027 page has **no Liquid Glass API section at all**; it covers toolbar customization, the Document API, presentation/interaction, and performance. The [SwiftUI updates](https://developer.apple.com/documentation/updates/swiftui) page's only Liquid Glass entries appear under **June 2025** (iOS 26), not June 2026. The iOS 27 release notes' SwiftUI section never mentions glass.

**Confirmed [Symbol]:** every Liquid Glass symbol still reports `introducedAt: 26.0` and **no `deprecatedAt`** in Apple's current (iOS 27) docs:

| Symbol | Status |
|---|---|
| [`View.glassEffect(_:in:)`](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)) | iOS 26.0, not deprecated; declaration unchanged |
| [`View.glassEffectID(_:in:)`](https://developer.apple.com/documentation/swiftui/view/glasseffectid(_:in:)) | iOS 26.0, not deprecated |
| [`View.glassEffectUnion(id:namespace:)`](https://developer.apple.com/documentation/swiftui/view/glasseffectunion(id:namespace:)) | iOS 26.0, not deprecated |
| [`GlassEffectContainer`](https://developer.apple.com/documentation/swiftui/glasseffectcontainer) | iOS 26.0, not deprecated |
| [`PrimitiveButtonStyle.glass`](https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/glass) | iOS 26.0, not deprecated |
| [`PrimitiveButtonStyle.glassProminent`](https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/glassprominent) | iOS 26.0, not deprecated |

**What actually changes [Apple]:**
- **The refined Liquid Glass look is automatic.** WWDC26 session 269: *"the Liquid Glass design automatically takes on its updated appearance. Apps gain this look without having to change a single line of code!"* and it *"automatically responds to the new Liquid Glass slider to adjust its tint."* On macOS, custom Liquid Glass elements can be marked "interactive" (session 269) — this is the pre-existing interactive-glass behavior, not a new SDK requirement.
- **The `UIDesignRequiresCompatibility` escape hatch is gone for SDK 27 builds.** Apple's [Information Property List reference](https://developer.apple.com/documentation/bundleresources/information-property-list/uidesignrequirescompatibility): *"The system ignores this key when you build for iOS 27 or later, iPadOS 27 or later, Mac Catalyst 27 or later, macOS 27 or later, or tvOS 27 or later."* An app rebuilt with the iOS 27 SDK gets the new design (and the new tab/navigation-bar/menu treatments) whether or not the key is `YES`. WidgetKit/UIKit/SwiftUI all inherit this.
- **Liquid Glass guidance (not API) [Apple]:** the [SwiftUI Group Lab (WWDC26 session 8120)](https://developer.apple.com/videos/play/wwdc2026/8120/) advises: avoid Liquid Glass in the *content* area (nothing underneath to refract); for a glass button use the **glass button style (`.glass` / `.glassProminent`)** rather than a raw `.glassEffect`, which yields "a button sitting on glass"; pair with `buttonBorderShape`.
- Related system-level change [Apple]: on iPadOS 27 / macOS 27, **menu item symbol images are hidden by default**; opt back in with `labelStyle(.titleAndIcon)`, or in UIKit with the new `UIMenuElement.preferredImageVisibility` (iOS 27 release notes IDs 170480710 / 170479084).

**Net for planning:** no Liquid Glass code migration is required, but a **visual regression pass is required** for any app that had `UIDesignRequiresCompatibility = YES`, plus apps with custom bars/backgrounds (secondary guidance on the common trouble spots is in the [DevelopersIO article](https://dev.classmethod.jp/en/articles/ios27-xcode27-migration-preparation-guide/), flagged secondary).

### 1b. New SwiftUI APIs in iOS 27 (all `[Symbol]`-confirmed at iOS 27.0 unless noted)

- **Document API (largest addition):** [`Document`](https://developer.apple.com/documentation/swiftui/document), [`ReadableDocument`](https://developer.apple.com/documentation/swiftui/readabledocument), [`WritableDocument`](https://developer.apple.com/documentation/swiftui/writabledocument) — all iOS 27.0 — plus `DocumentReader`, `DocumentWriter`, `FileWrapperDocumentReader`, `FileWrapperDocumentWriter`, `URLDocumentConfiguration`, `DocumentCreationSource` and `NewDocumentButton` per source ([Apple] WWDC26 269 + SwiftUI updates). Apple: *"New applications should prefer `ReadableDocument` and `WritableDocument` over `ReferenceFileDocument`."*
- **Reordering in any container:** [`DynamicViewContent.reorderable()`](https://developer.apple.com/documentation/swiftui/dynamicviewcontent/reorderable()) and [`View.reorderContainer(for:isEnabled:move:)`](https://developer.apple.com/documentation/swiftui/view/reordercontainer(for:isenabled:move:)) — iOS 27.0.
- **Swipe actions outside `List`:** [`View.swipeActionsContainer()`](https://developer.apple.com/documentation/swiftui/view/swipeactionscontainer()) — iOS 27.0 (used with the existing `swipeActions(edge:allowsFullSwipe:content:onPresentationChanged:)`).
- **Toolbar:** [`ToolbarContent.visibilityPriority(_:)`](https://developer.apple.com/documentation/swiftui/toolbarcontent/visibilitypriority(_:)) (27.0), [`ToolbarOverflowMenu`](https://developer.apple.com/documentation/swiftui/toolbaroverflowmenu) (27.0), [`ToolbarItemPlacement.topBarPinnedTrailing`](https://developer.apple.com/documentation/swiftui/toolbaritemplacement/topbarpinnedtrailing) (27.0), `toolbarMinimizationBehavior(_:for:)` (27.0 — replaces `toolbarMinimizeBehavior`), `.toolbarVisibility(_:for: .statusBar)`, `.toolbarColorScheme(_:for: .statusBar)`.
- **Tab bars:** [`TabRole.prominent`](https://developer.apple.com/documentation/swiftui/tabrole/prominent) (27.0).
- **AsyncImage caching:** `AsyncImage(request:)` initializers + [`View.asyncImageURLSession(_:)`](https://developer.apple.com/documentation/swiftui/view/asyncimageurlsession(_:)) (27.0) — HTTP caching is now on by default.
- **Presentation:** item/error-based `alert` and `confirmationDialog` overloads (SwiftUI updates; now back-deployable to iOS 15 per release note 179388848), [`NavigationTransition.crossFade`](https://developer.apple.com/documentation/swiftui/navigationtransition/crossfade) (27.0).
- **Gestures:** gesture-input-source initializers across `DragGesture`, `TapGesture`, `MagnifyGesture`, `RotateGesture`, `SpatialTapGesture`, etc. (`GestureInputKinds`) [Apple] SwiftUI updates.
- **Other:** `TextInputBorderShape` + `textInputBorderShape(_:)`; `TabsPickerStyle`; [`GeometryProxy.concentricCornerRadii`](https://developer.apple.com/documentation/swiftui/geometryproxy/concentriccornerradii) (27.0); `LabeledContent` inside `Menu` maps to a menu-item subtitle; `.sceneAccessory` with `ExternalNonInteractiveAccessory`; `fileExporter(isPresented:documents:contentTypes:…)` for a collection of `WritableDocument`; `.font`/`buttonSizing` etc. unchanged.
- **Language/tooling changes:** `@State` is implemented as a **Swift macro** in Xcode 27 (see §1c); `@ContentBuilder` unifies the result builders. Note `ContentBuilder` is a `typealias ContentBuilder = ViewBuilder` and its doc page reports iOS 13.0, i.e. it **back-deploys** ([symbol](https://developer.apple.com/documentation/swiftui/contentbuilder)).

### 1c. SwiftUI deprecations and source-breaking changes in iOS 27

**Deprecated at 27.0 [Symbol]/[Apple]:**
| Symbol | Replacement | Note |
|---|---|---|
| [`FileDocument`](https://developer.apple.com/documentation/swiftui/filedocument) | `Document` / `ReadableDocument` | `deprecatedAt: 27.0`; also in release notes Deprecations (178776840) |
| [`ReferenceFileDocument`](https://developer.apple.com/documentation/swiftui/referencefiledocument) | `Document` | `deprecatedAt: 27.0`; release notes New Features (177458781) |
| [`View.statusBarHidden(_:)`](https://developer.apple.com/documentation/swiftui/view/statusbarhidden(_:)) | `.toolbarVisibility(_, for: .statusBar)` | `deprecatedAt: 27.0` |
| [`TextFieldStyle.roundedBorder`](https://developer.apple.com/documentation/swiftui/textfieldstyle/roundedborder) | `.textFieldStyle(.bordered)` | `deprecatedAt: 27.0` |
| `TextFieldStyle.squareBorder` | `.textFieldStyle(.bordered)` | soft-deprecated per release notes (173362083) |
| `toolbarMinimizeBehavior` | `toolbarMinimizationBehavior` | [Apple] release notes say the new modifier *"replaces"* it (177954148); exact deprecation attribute **not verified** |
| `PreviewProvider` and its family of preview modifiers | `#Preview` macro | Deprecated in the **Xcode 27 release notes › Previews** (144168701) — an Xcode-level deprecation rather than an OS one |

**Source-breaking / behavior changes [Apple] release notes:**
- **`@State` macro.** *"Xcode 27 introduces a new `@State` implementation that avoids this repeated evaluation. This new behavior back-deploys to iOS 17 aligned OSes. The new `@State` is implemented with a Swift macro. It is largely source compatible … with a few exceptions."* Documented failures: assigning at declaration **and** in `init` no longer compiles; the synthesized memberwise/private `init` is disabled when all stored members are private; generic inference is less flexible; composing `@State` with other property wrappers/macros is unsupported. Apple published [TN3211: Resolving SwiftUI source incompatibilities for State and ContentBuilder](https://developer.apple.com/documentation/technotes/tn3211-resolving-swiftui-source-incompatibilities-for-state-and-contentbuilder).
- **`TabView` selection is enforced:** *"a `TabView` enforces that its selection is set to a visible tab. `TabView` might crash when its selection is set to a hidden or otherwise unavailable tab."* (164516837)
- **Selectable `Text`** now uses the system text-selection UI on iOS/iPadOS 27 SDK builds and adds gestures; Apple suggests `.highPriorityGesture()` for custom gestures (79770704).
- **Menu item images** hidden by default on iPadOS 27/macOS 27 (170480710).
- **`makeFileWrapper` closure of `FileWrapperDocumentWriter` gains a second argument `previous: FileWrapper?`** — *"Existing call sites must update their closures to accept the new parameter."* (180301399)
- **`DocumentReader`/`DocumentWriter` requirements are `@concurrent`, not `nonisolated`** — conformers that used `nonisolated` should switch (180302015).
- **`URLDocumentConfiguration` is `@MainActor` and no longer `Sendable`** (180302075).
- **Control environment values are reset in sheets/popovers** built with the 27.0 SDK (`controlSize`, `buttonSizing`, `buttonRepeatBehavior`, `menuIndicatorVisibility`, `ButtonBorderShape`) (167448274).
- `containerRelativeFrame(_:alignment:)` safe-area bug fixed (behavior change) (165913417); retroactive `Equatable` conformances now consulted (167443223).

---

## 2. iOS 27 SDK: APIs deprecated in iOS 27 but not in iOS 26

Sources: the iOS 27 release notes' `Deprecations` sections and Apple per-symbol `deprecatedAt` metadata. Apple does **not** publish one consolidated deprecation list, and it publishes `deprecated-symbols` index pages for only some frameworks, so for the frameworks with no index page "not found" ≠ "none".

### 2a. Confirmed new-at-27.0 deprecations

| Framework | Symbol(s) | Replacement | Evidence |
|---|---|---|---|
| UIKit | [`UIApplication.canOpenURL(_:)`](https://developer.apple.com/documentation/uikit/uiapplication/canopenurl(_:)) | Attempt the open and handle failure; prefer universal links | `deprecatedAt: 27.0`; release notes; [WebKit bug 319176](https://bugs.webkit.org/show_bug.cgi?id=319176) shows the SDK annotation `API_DEPRECATED(..., ios(3.0, 27.0))` |
| UIKit | `UIGraphicsBeginImageContext`, `UIGraphicsBeginImageContextWithOptions`, `UIGraphicsGetImageFromCurrentImageContext`, `UIGraphicsEndImageContext` | `UIGraphicsImageRenderer` (and `UIGraphicsImageRendererContext.currentImage`) | `[Symbol]` `deprecatedAt: 27.0` — **not** mentioned in the release notes |
| UIKit | `UIRequiresFullScreen` (Info.plist key / build setting) | resizable scenes; `UIRequiresFullScreenIgnoredStartingWithVersion` to stage the change | [TN3192](https://developer.apple.com/documentation/technotes/tn3192-migrating-your-app-from-the-deprecated-uirequiresfullscreen-key) |
| CoreLocation | `CLLocationManager.startMonitoring(for:)`, `stopMonitoring(for:)`, `requestState(for:)` | `CLMonitor` | `[Symbol]` `deprecatedAt: 27.0` — **not** mentioned in the release notes |
| SwiftUI | `FileDocument`, `ReferenceFileDocument` | `Document` / `ReadableDocument` | `[Symbol]` + release notes |
| SwiftUI | `View.statusBarHidden(_:)` | `.toolbarVisibility(_, for: .statusBar)` | `[Symbol]` `deprecatedAt: 27.0` |
| SwiftUI | `.roundedBorder` (attribute) / `.squareBorder` (soft) text-field styles | `.textFieldStyle(.bordered)` | `[Symbol]` + release notes |
| MetricKit | `MXMetricManager`, `MXMetricManagerSubscriber`, `MXMetricPayload`, `MXDiagnosticPayload` | `MetricManager` (new Swift API) | Release notes (174892111) + `[Symbol]`; wording is *"no longer recommended for new adoption"* |
| MetricKit | `MetricResult.scrollHitchTime(_:)`, `ScrollHitchTimeMetric` | `hitchTime(_:)`, `HitchTimeMetric` | Release notes (180455992); *"Recompile your app with the latest SDK to avoid a missing symbol crash"* |
| PhotoKit | `PHAssetResource.originalFilename` | new nullable `PHAssetResource.filename` | Release notes (175412725) + `[Symbol]` |
| PassKit | `PKPassLibrary.activate(_:withActivationData:completion:)`, `remotePaymentPasses()` and related `*PaymentPass*` names | `*SecureElementPass*` equivalents | `[Symbol]` `deprecatedAt: 27.0` (release notes silent) |
| CoreMIDI | `MIDISend`, `MIDIReceived`, `MIDIPacketListInit`, `MIDIPacketListAdd`, `MIDIDestinationCreate`, `MIDIInputPortCreate`, `MIDISourceCreate`, `MIDIReadBlock`/`MIDIReadProc` | `MIDIEventList`/`MIDIReceiveBlock`/`…WithProtocol` APIs | `[Symbol]` `deprecatedAt: 27.0` (release notes silent) |
| On Demand Resources | ODR and `NSBundleResourceRequest` | Background Assets | Release notes (170066290) |
| PencilKit | `__PKStrokeRenderState` | `PKStrokeRenderStateReference` + `init(…)` | Release notes (176410709) |
| App Intents | `calendar.deleteEvents` schema | `calendar.deleteEvent` | Release notes (176751155) |

`UIApplication.statusBarFrame` / `statusBarOrientation` / `statusBarStyle` / `isStatusBarHidden` are **not** newly deprecated in 27 — they were deprecated earlier — but the release notes add a *behavior* warning: in iOS 27 SDK builds they *"might return NaN or null values"* (162044221). Read status-bar state from the window scene instead.

### 2b. Frameworks the question named, with the result

| Framework | iOS 27 deprecations |
|---|---|
| **SwiftUI** | `FileDocument`, `ReferenceFileDocument`, `statusBarHidden(_:)`, text-field border styles (above). No Liquid Glass deprecations. |
| **UIKit** | `canOpenURL(_:)`, the `UIGraphics*` image-context quartet, `UIRequiresFullScreen`. |
| **MapKit** | **[Not found]** — the MapKit `deprecated-symbols` index has no 27.0 entries; no MapKit section in the release notes. |
| **CoreLocation** | `startMonitoring(for:)` / `stopMonitoring(for:)` / `requestState(for:)` → `CLMonitor` (not in release notes; from symbol metadata). |
| **Foundation** | **[Not found]** — the Foundation `deprecated-symbols` index has no 27.0 entries. The only Foundation-family 27.0 deprecation I found is `NSBundleResourceRequest`, filed under On Demand Resources. |
| **AVFoundation** | **[Not found]** — no `avfoundation/deprecated-symbols` page exists (404); AVFAudio's index has no 27.0 entries; no release-notes section. |
| **PhotosUI** | **[Not found]** — no deprecation. `PHPickerMetadataOptions` is **new** at iOS 27.0. |
| **UserNotifications** | **[Not found]** — the release-notes "Notifications" section has only a resolved issue (critical alerts). |
| **WidgetKit** | **[Not found]** — the release-notes WidgetKit section has only a resolved issue (`@UnionValue` timelines). |

---

## 3. iOS 27 app-level requirements and behavior changes

### 3a. UIScene lifecycle — now a hard launch gate [Apple]

iOS 27 release notes, UIKit › Deprecations: *"Apps built with the latest SDK must adopt the scene-based life cycle or they fail to launch."* (141837548). Migration guide: [Transitioning to the UIKit scene-based life cycle](https://developer.apple.com/documentation/uikit/transitioning-to-the-uikit-scene-based-life-cycle). Secondary corroboration of the exact assertion at runtime: [expo/expo#46664](https://github.com/expo/expo/issues/46664) shows `Application failed to launch: UIScene life cycle is required for apps built with this SDK.`

- **Required Info.plist keys:** [`UIApplicationSceneManifest`](https://developer.apple.com/documentation/bundleresources/information-property-list/uiapplicationscenemanifest) (root dictionary) → `UIApplicationSupportsMultipleScenes` (`false` is fine — **multi-scene support is not required**) + `UISceneConfigurations` → `UIWindowSceneSessionRoleApplication` → `UISceneConfigurationName`, `UISceneDelegateClassName` (e.g. `$(PRODUCT_MODULE_NAME).SceneDelegate`), optional `UISceneStoryboardFile`. None of these keys is new; they became mandatory.
- **Dynamic alternative:** implement `application(_:configurationForConnecting:options:)` in the app delegate.
- **Trigger is the SDK you build with, not the OS the user runs** — so an existing binary keeps working; the gate bites the first time you ship an SDK-27 build.
- `UIScene.extendStateRestoration` / `completeStateRestoration` are new (161843040).

### 3b. Launch screen — now an App Store upload gate [Apple]

The Flutter warning lead ([flutter/flutter#191043](https://github.com/flutter/flutter/issues/191043)) is answered authoritatively by [TN3208](https://developer.apple.com/documentation/technotes/tn3208-preparing-your-apps-launch-screen-to-meet-app-store-requirements):
- App Store Connect requires a launch-screen configuration for apps uploaded **built with the iOS 27 SDK or later** (iPhone and iPad, App Store and alternative marketplaces).
- `Info.plist` must contain **at least one** of `UILaunchStoryboardName`, `UILaunchStoryboards`, `UILaunchScreen`, `UILaunchScreens`.
- Otherwise the upload is rejected with `ITMS-90870: Missing launch screen.`
- It is **not** a runtime requirement, and apps that already have a launch screen need no change. Xcode generates `UILaunchScreen` by default for new SwiftUI projects when the `Generate Info.plist File` and `Launch Screen (Generation)` build settings are enabled.

### 3c. Privacy manifests — [Not found]

I found **no** iOS 27 privacy-manifest change. The iOS 27 release notes never mention privacy manifests or required-reason APIs (the only "privacy" string is the site's privacy-policy link), and Apple's [Upcoming Requirements](https://developer.apple.com/news/upcoming-requirements/) page contains no privacy-manifest item. The existing `PrivacyInfo.xcprivacy` / `NSPrivacyAccessedAPITypes` regime appears unchanged; treat this as "no change found", not "confirmed no change".

### 3d. Deployment targets and SDK submission rules [Apple]

- **Deployment-target range (Xcode 27):** Apple's [SDKs and system requirements](https://developer.apple.com/xcode/system-requirements) lists Xcode 27 deployment targets as **iOS 15–27, iPadOS 15–27, tvOS 15–27, watchOS 9–27, visionOS 1–27, macOS 12–27, DriverKit 21–27**. So **iOS 15.0** is the floor. (Third-party reports, e.g. Flutter issues, say Xcode 27 *errors* below 15.0 where it previously warned — consistent, but the explicit error text is secondary.)
- **Current App Store SDK floor:** since **April 28, 2026**, uploads must be built with Xcode 26 or later using the iOS 26 / iPadOS 26 / tvOS 26 / visionOS 26 / watchOS 26 SDK ([Upcoming Requirements](https://developer.apple.com/news/upcoming-requirements/)). **There is no iOS 27 SDK submission mandate in effect today.**
- **Announced future floor:** Apple News, **September 9, 2026** — *"Starting April 2027, apps and games uploaded to App Store Connect need to meet the following minimum requirements: iOS and iPadOS apps must be built with the iOS 27 & iPadOS 27 SDK or later; tvOS apps must be built with the tvOS 27 SDK or later; visionOS … 27; watchOS … 27."* ([source](https://developer.apple.com/news/?id=k1mtkt1k)). So the practical deadline is **April 2027**, not the September 2026 OS release.

### 3e. Other behavior changes that can break or alter apps (iOS 27 release notes unless noted)

- **Resizability is now the norm.** Apps built with the iOS 27 SDK are fully resizable in **iPhone Mirroring on Mac**, an iPhone-only app on iPad, and (via discrete resizing) even with `UIRequiresFullScreen`: WWDC26 session 278 [Modernize your UIKit app](https://developer.apple.com/videos/play/wwdc2026/278/) and [TN3192](https://developer.apple.com/documentation/technotes/tn3192-migrating-your-app-from-the-deprecated-uirequiresfullscreen-key).
  - Supported interface orientations become a **preference** and are ignored when resizing; in iPhone Mirroring apps always report **portrait**.
  - The **user-interface idiom trait is no longer meaningful for layout**; use size classes and the view's available size. `UIScreen.main` references are wrong — use the window scene's screen/effective geometry and traits.
- **iPad settings:** an iPad app whose `UISupportedInterfaceOrientations` lacks all four orientations is treated as non-continuously-resizable (166422120); iPhone Mirroring/iPad resize behaviors changed for SDK-27 builds (178555304, 178561952, etc.).
- **Traits:** a presented view controller now inherits traits by walking up its superview chain rather than jumping to the presentation controller; custom `UIPresentationController` subclasses may need changes (170005251).
- **External displays:** `windowExternalDisplayNonInteractive` scenes are no longer offered automatically; use `UIViewController.registerSceneAccessory(_:)` with `UISceneAccessory.externalNonInteractive` (177015874). SwiftUI equivalent: `.sceneAccessory`.
- **Search scope bar** is now inline with the search field for center placement (173860616).
- **Animation/hitch metrics type change** and removed MetricKit symbols can crash on launch unless recompiled (see §2a).
- **Network security:** selected system processes (MDM, DDM, Automated Device Enrollment, profile/app installation, software updates) now enforce TLS 1.2 minimum with ATS-compliant ciphers/certs (176055825) — relevant to enterprise/MDM-facing servers.
- **Core AI:** background Neural Engine access now requires the entitlement `com.apple.developer.background-tasks.continued-processing.inference` (179282606).
- **App Intents:** entities conforming to `@AppEntity(schema: .photos.asset)` may no longer compile because properties were added (181800016) — workaround: adopt the new properties behind an availability check.
- **UIKit menu images:** hidden by default on iPadOS/macOS 27 unless `preferredImageVisibility` says otherwise (170479084).
- **UIKit navigation bar:** `UINavigationItem.navigationBarMinimization` replaces `barMinimizeBehavior` and `barMinimizationSafeAreaAdjustment` (177953926).

---

## 4. macOS 27: what changed for developers (and iOS apps on Mac)

Primary: [macOS 27 Golden Gate Release Notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes), [What's new in macOS 27](https://developer.apple.com/macos/whats-new/), [Apple News 2026-09-09](https://developer.apple.com/news/?id=k1mtkt1k).

- **Apple silicon only.** Apple News: *"macOS 26 is the final release supporting Intel Mac computers and Rosetta — macOS 27 will be Apple silicon only. To limit your app to Macs with Apple silicon, set your Xcode build architecture to arm64 only, then rebuild and resubmit."* Release notes confirm Rosetta is not reinstalled after upgrade, apps previously set to "Open using Rosetta" launch natively, installer packages without `hostArchitecture` default to arm64, and **all Intel-based software will be incompatible with macOS 28.0** (legacy games excepted). Xcode 27 itself only installs/runs on Apple silicon.
- **Mac Catalyst:**
  - *"Catalyst apps now behave like AppKit apps when you switch to them with no open windows - they won't automatically create new windows unless activated through Dock or Spotlight."* (69906818) — an observable behavior change for Catalyst windowing.
  - `UIRefreshControl` and `UIStepper` are now fully supported in the Mac idiom; Mac-idiom Catalyst `UIStepper` bug fixed (UIKit updates June 2026; macOS notes 57819435).
  - Catalyst inherits the iOS 27 SDK requirements: **scene-lifecycle launch requirement**, **`UIDesignRequiresCompatibility` ignored**, menu-image visibility, etc. (macOS 27 release notes › UIKit).
- **SwiftUI on macOS 27 [Apple]:**
  - Menu item images hidden by default on macOS 27 and iPadOS 27 (SwiftUI + UIKit).
  - `TabView`s in inspectors match sidebars and use the new `.tabs` picker style (170678002).
  - Bordered `Menu`/`Picker` buttons no longer use `NSPopUpButton` (68559433); `Slider` no longer uses `NSSlider` (173990195); disabled `.checkbox` toggles are no longer tinted (172689844) — visual changes to regression-test.
  - `TextField` respects custom font/color on its prompt; `.glass`/`.glassProminent` buttons outside a toolbar now have a hover state (158800693); `List` accepts drops in two cases that previously failed (174628712).
  - All the iOS 27 SwiftUI Document API additions, `@State` macro, toolbar/reorder/swipe APIs, and deprecations apply on macOS 27 as well.
- **"Designed for iPad" / iPhone apps on Mac:** I found **no macOS-27-specific change to the Designed-for-iPad distribution mechanism itself**. What is relevant:
  - Such apps are iOS binaries and therefore inherit the iOS 27 SDK gates (scene lifecycle, launch screen, resizability) when rebuilt — they run resizable on Mac by design.
  - `UIDesignRequiresCompatibility` is also ignored for **macOS 27** and **Mac Catalyst 27**, so a Designed-for-iPad app rebuilt on the 27 SDK gets the refined design too.
  - Xcode's build settings still expose `SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD` to show/hide the Mac (Designed for iPad) destination ([Build settings reference](https://developer.apple.com/documentation/xcode/build-settings-reference)).
  - For source-based apps, `ARCHS_STANDARD` no longer includes `x86_64` when `MACOSX_DEPLOYMENT_TARGET` ≥ 27.0, so macOS-27-targeted builds are Apple-silicon-only by default (Xcode 27 release notes, 161837535).
- **iPhone Mirroring (the "iPhone on Mac" experience) improved [Apple]:** macOS 27 + iOS 27 make the mirrored iPhone window fully resizable, and the app sees real scene-size changes. Apps should drop `UIScreen.main`, idiom and orientation-based layout; see [TN3210: Optimizing your app for iPhone Mirroring](https://developer.apple.com/documentation/technotes/tn3210-optimizing-your-app-for-iphone-mirroring) and WWDC26 session 278. TN3210 specifics: add/keep `UIApplicationSupportsIndirectInputEvents = YES`; use `UIPanGestureRecognizer.allowedScrollTypesMask` for trackpad/mouse scroll; use GameController for game pointer input; **biometric auth from the Mac fails by default** — switch `.deviceOwnerAuthenticationWithBiometrics` to `.deviceOwnerAuthenticationWithBiometricsOrCompanion`.
- **[Not found]** I could not retrieve an Apple page titled "Designed for iPad" that documents 2027 changes; the Apple support article on using iPhone/iPad apps on Apple-silicon Mac is consumer-facing.

---

## 5. Xcode 27: build settings, warnings, Swift language modes, upcoming features, macro sandboxing

Primary: [Xcode 27 Release Notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes), [SDKs and system requirements](https://developer.apple.com/xcode/system-requirements), [Build settings reference](https://developer.apple.com/documentation/xcode/build-settings-reference), [WWDC26 "What's new in Xcode 27" (session 258)](https://developer.apple.com/videos/play/wwdc2026/258/).

### 5a. Toolchain baseline [Apple]

- Xcode 27 includes **Swift 6.4** and SDKs for iOS 27 / iPadOS 27 / tvOS 27 / watchOS 27 / macOS 27 / visionOS 27.
- **Xcode 27 requires a Mac running macOS Tahoe 26.6 or later** and **only installs/runs on Apple silicon**. (One secondary article claims macOS Tahoe 26.4 — that contradicts Apple's own pages; use **26.6**.)
- **Language modes offered: Swift 6, Swift 5, Swift 4.2, Swift 4** ([system requirements](https://developer.apple.com/xcode/system-requirements)). Swift 6.4 is the compiler; the *language mode* is a separate setting (`SWIFT_VERSION`). Apple does not publish a "default language mode for new projects" statement on these pages — check the project template. Swift 6 language mode turns on strict concurrency as errors and enables the Swift-6 upcoming features unconditionally.

### 5b. New/notable build settings and defaults [Apple]

- **`ARCHS_STANDARD` no longer includes `x86_64`** when `MACOSX_DEPLOYMENT_TARGET` or `DRIVERKIT_DEPLOYMENT_TARGET` ≥ 27.0; macOS-27-targeted targets don't build Universal by default. Add `x86_64` to `ARCHS` if needed (161837535).
- **Interface Builder:** new default compilation mode `toolchain` for UIKit (Cocoa Touch) documents; opt out with `IBC_COCOATOUCH_COMPILER_MODE = simulator` (or `ibtool --cocoatouch-compiler-mode simulator`) (114401122).
- **Linking:** the **`ld64` linker has been removed and `-ld_classic` is no longer supported** (165165518).
- **Enhanced Security** build settings (opt-in via the capability; Apple documents each in [Enabling enhanced security for your app](https://developer.apple.com/documentation/xcode/enabling-enhanced-security-for-your-app)): the umbrella `ENABLE_ENHANCED_SECURITY`, plus `ENABLE_POINTER_AUTHENTICATION`, `CLANG_ENABLE_C_TYPED_ALLOCATOR_SUPPORT`, `CLANG_ENABLE_CPLUSPLUS_TYPED_ALLOCATOR_SUPPORT`, `CLANG_ENABLE_STACK_ZERO_INIT`, `ENABLE_SECURITY_COMPILER_WARNINGS`, `ENABLE_CPLUSPLUS_BOUNDS_SAFE_BUFFERS`, `ENABLE_C_BOUNDS_SAFETY`, and `ENABLE_HARDWARE_CHECKED_POINTER_ARITHMETIC_SLICE` (adds the `arm64e.x1` slice to `ARCHS_STANDARD`; Xcode 27 release-notes item 152104701), plus entitlements such as `com.apple.security.hardened-process.checked-allocations`. `ENABLE_SECURITY_COMPILER_WARNINGS = Yes` turns on `-Wshadow`, `-Wempty-body`, `-Wbuiltin-memcpy-chk-size`, `-Wformat-nonliteral`, `-Warray-bounds`, `-Warray-bounds-pointer-arithmetic`, `-Wsuspicious-memaccess`, `-Wsizeof-array-div`, `-Wsizeof-pointer-div`, `-Wreturn-stack-address`. Xcode 27 adds two Code Intelligence skills to help adopt these (`adopt-c-bounds-safety`, `audit-xcode-security-settings`).
- Existing sandbox build settings remain `ENABLE_APP_SANDBOX` and `ENABLE_USER_SCRIPT_SANDBOXING` (Build settings reference).
- Swift-side settings documented in the Build settings reference include `SWIFT_STRICT_CONCURRENCY`, `SWIFT_STRICT_MEMORY_SAFETY`, `SWIFT_DEFAULT_ACTOR_ISOLATION` (`nonisolated` / `MainActor` → `-default-isolation=MainActor`), `SWIFT_APPROACHABLE_CONCURRENCY`, `SWIFT_TREAT_WARNINGS_AS_ERRORS`, `SWIFT_WARNINGS_AS_ERRORS_GROUPS`, `SWIFT_WARNINGS_AS_WARNINGS_GROUPS`, `SWIFT_ENABLE_BARE_SLASH_REGEX`.

### 5c. New compiler warnings on by default

Apple does **not** publish a consolidated "new default warnings" list for Xcode 27, and the Xcode 27 release notes' Swift Compiler section mentions no default-warning change. From the [Swift CHANGELOG (Swift 6.4 section)](https://raw.githubusercontent.com/swiftlang/swift/main/CHANGELOG.md):

- **New default warning:** throwing unstructured task initializers (`Task.init`, `Task.immediate`, `Task.detached`, …) now use typed throws and **warn** when a throwing operation's result is unused — diagnostic group `NoUseUnstructuredThrowingTask`, with a literal `Task { … }` example in the changelog.
- **New warning-control mechanism (SE-0522):** the `@diagnose(GroupID, as: error|warning|ignored, reason:)` declaration attribute lets you elevate/silence a diagnostic group in lexical scope; warning group IDs appear in brackets (e.g. `[#DeprecatedDeclaration]`).
- **Source-breaking diagnostics (not just warnings):** illegal forward references to local variables are now rejected consistently inside closures (breaks `lazy var x = { y }` patterns); the SE-0503 prototype (`SuppressedAssociatedTypes`) is deprecated and emits a migration warning.
- **Swift 6.4 feature additions** that may affect builds: `anyAppleOS` availability shorthand for OS 26+; `async` in `defer` (SE-0493); `~Sendable` (SE-0518); `~Copyable`/`~Escapable` associated types (SE-0503); trailing closures after array/dictionary literals (SE-0508); `withTaskCancellationShield` (SE-0504); library-evolution modules now use module selectors in `.swiftinterface` by default (disable with `-Xfrontend -disable-module-selectors-in-module-interface`); new `stat`/`lstat`/`fstat` Swift APIs on `FilePath`/`FileDescriptor` can collide with unqualified `stat()` calls (use `Darwin.stat()`).
- Also from the Xcode 27 release notes: the Swift dependency scanner now requires **unique Clang module names** within a dependency-scan action and may report an error where it previously tolerated duplicates (136303612).

Caveat: I could not find an Apple statement enumerating which warnings are new *and on by default*, so treat the list above as "documented in the Swift 6.4 changelog" rather than an exhaustive Apple-published set.

### 5d. "Upcoming feature flags" / "Enable Upcoming Features"

This is real and documented in two places:

- **Apple's [Build settings reference](https://developer.apple.com/documentation/xcode/build-settings-reference)** exposes them individually in the **"Swift Compiler – Upcoming Features"** category, with these exact identifiers: `SWIFT_UPCOMING_FEATURE_CONCISE_MAGIC_FILE`, `_DEPRECATE_APPLICATION_MAIN`, `_DISABLE_OUTWARD_ACTOR_ISOLATION`, `_DYNAMIC_ACTOR_ISOLATION`, `_EXISTENTIAL_ANY`, `_FORWARD_TRAILING_CLOSURES`, `_GLOBAL_ACTOR_ISOLATED_TYPES_USABILITY`, `_GLOBAL_CONCURRENCY`, `_IMPLICIT_OPEN_EXISTENTIALS`, `_IMPORT_OBJC_FORWARD_DECLS`, `_INFER_ISOLATED_CONFORMANCES`, `_INFER_SENDABLE_FROM_CAPTURES`, `_INTERNAL_IMPORTS_BY_DEFAULT`, `_ISOLATED_DEFAULT_VALUES`, `_MEMBER_IMPORT_VISIBILITY`, `_NONFROZEN_ENUM_EXHAUSTIVITY`, `_NONISOLATED_NONSENDING_BY_DEFAULT`, `_REGION_BASED_ISOLATION`. Apple notes most are *"always enabled when in the Swift 6 language mode"*.
- **The aggregate switch** is visible in Apple's Swift build-system spec (open source [swiftlang/swift-build `Swift.xcspec`](https://raw.githubusercontent.com/swiftlang/swift-build/main/Sources/SWBUniversalPlatform/Specs/Swift.xcspec)): `ENABLE_SWIFT_6_UPCOMING_FEATURES_IN_SWIFT_VERSION_6_0` gates `SWIFT_UPCOMING_FEATURE_6_0`, and each `SWIFT_UPCOMING_FEATURE_*` defaults to it. Crucially, the individual flags carry `Condition = "$(EFFECTIVE_SWIFT_VERSION) == '4' || … == '5'"` — i.e. **they are surfaced/enabled only for Swift 4/4.2/5 language mode projects**, which is exactly the "enable upcoming features for Swift 5 projects" mechanism. That spec is [secondary] (open-source build system, not the shipping Xcode UI), so verify in Xcode's Swift Compiler settings.
- **Xcode 27's recommended concurrency bundle:** `SWIFT_APPROACHABLE_CONCURRENCY` = `DisableOutwardActorInference`, `GlobalActorIsolatedTypesUsability`, `InferIsolatedConformances`, `InferSendableFromCaptures`, `NonisolatedNonsendingByDefault` (Build settings reference). `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is the other recommended companion for app targets.
- Xcode 27 also ships **agent "skills"** that walk a project through adopting new SwiftUI APIs and best practices, and a skill for auditing security build settings ([What's new in SwiftUI](https://developer.apple.com/swiftui/whats-new/), Xcode 27 release notes 178289150 / 181104536).

### 5e. Macro plugin sandboxing and `-disable-sandbox`

**Confirmed [Apple/Swift upstream]:**
- The Swift compiler has a frontend flag **`-disable-sandbox`**, documented in the compiler options as *"Disable using the sandbox when executing subprocesses"* ([swift `Options.td`](https://raw.githubusercontent.com/swiftlang/swift/main/include/swift/Option/Options.td)).
- It was introduced for **executable macro plugins** in Swift 5.10 ([swift PR #70079](https://github.com/swiftlang/swift/pull/70079), merged 2023-11-29) with the rationale: *"Since `sandbox(7)` in macOS doesn't support nested sandbox, compilations used to fail when the parent build process is sandboxed."* In `PluginRegistry::loadExecutablePlugin` the compiler calls `Sandbox::apply(command, …)` unless `disableSandbox` is set — i.e. **macro plugins are launched as sandboxed subprocesses by default**, and this flag removes that containment.
- SwiftPM exposes the equivalent as **`--disable-sandbox`** for package managers whose *outer* build environment already provides a sandbox (Homebrew, Nix): *"Some package systems (e.g: HomeBrew, Nix) use a custom build sandbox. Within the outer sandbox, Swift Toolchain should not create their own sandbox"* ([swift-package-manager PR #10249](https://github.com/swiftlang/swift-package-manager/pull/10249)). That PR notes the option was **ineffective in the Xcode 27 beta toolchain (27A5194q, Swift 6.4.0.20.104)** and adds a regression test.
- To route it through Xcode's build system, SwiftBuild added a new XCSpec setting **`SWIFTC_DISABLE_SANDBOX`** (Boolean, default `NO`) that passes `-disable-sandbox` to `swiftc` when `YES` ([swift-build PR #1498](https://github.com/swiftlang/swift-build/pull/1498), merged 2026-07-03; setting at `Swift.xcspec` line ~1218).
- **What the sandbox actually is (Swift 6.4 source):** `lib/AST/PluginRegistry.cpp` applies `Sandbox::apply(command, …)` unless `disableSandbox` is set, and `lib/Basic/Sandbox.cpp` runs the plugin via `/usr/bin/sandbox-exec -p <profile>` with `(version 1) (deny default) (import "system.sb") (allow file-read-metadata) (allow file-read* (regex #"\.dylib$")) (allow process-exec*)` — i.e. deny-by-default, **no network and no arbitrary filesystem writes**, only metadata reads, `.dylib` reads and `execve`. Sources: [swiftlang/swift `release/6.4.x` PluginRegistry.cpp](https://raw.githubusercontent.com/swiftlang/swift/release/6.4.x/lib/AST/PluginRegistry.cpp), [Sandbox.cpp](https://raw.githubusercontent.com/swiftlang/swift/release/6.4.x/lib/Basic/Sandbox.cpp).
- **Nuance:** `SWIFTC_DISABLE_SANDBOX` is **not** in Apple's public [Build settings reference](https://developer.apple.com/documentation/xcode/build-settings-reference) (I searched it; zero hits). So in shipping Xcode 27 it is effectively an undocumented build setting intended for toolchain/package-system integrators. Also, I found **no Apple statement that Xcode 27 *requires* disabling the sandbox** — the evidence is that Xcode 27 adds an *opt-out*. Treat "Xcode 27 requires `-disable-sandbox` for macros" as **unconfirmed**.
- **Security implication:** the flag *disables* a sandbox around plugin subprocesses, so a macro plugin then runs unsandboxed with the build process's privileges (network + filesystem). Use it only where an external sandbox already exists (Homebrew/Nix/CI wrapper) or where you fully trust the macro dependencies; it is not a general build speed-up.

---

## 6. Published release notes — what exists and what matters

- **iOS & iPadOS 27 Release Notes** — exists: https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes (an RC variant also appears in search). Full article retrievable as JSON/Markdown (see §Method). Structured by ~93 framework/feature sections with New Features / Resolved Issues / Known Issues / Deprecations. SwiftUI-relevant content is summarised in §1 and §2; the actionable SwiftUI items are the `@State` macro, the Document API migration, `TabView` selection enforcement, selectable-text gestures, menu-image defaults, and the `makeFileWrapper` signature change.
- **Xcode 27 Release Notes** — exists: https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes (also `.md` and DocC-JSON variants). Structure: Overview + per-area sections with New Features / Resolved Issues / Known Issues / Deprecations. Notably it has **no SwiftUI section and no Xcode Cloud section** — SwiftUI-27 changes live in [Updates/SwiftUI](https://developer.apple.com/documentation/updates/swiftui). Top-level: Swift 6.4 + 27 SDKs; requires macOS Tahoe 26.6+; Apple-silicon-only install; `ARCHS_STANDARD` drops x86_64 at macOS 27; `ld64` removed / `-ld_classic` unsupported; IB `toolchain` mode default; Swift dependency-scanner unique-module-name error; SE-0508 source break (`init` accessor ordering); `PreviewProvider` deprecated; Instruments now requires iOS 17+/watchOS 10+/tvOS 17+ targets; Device Hub/Previews/Instruments/Coding Intelligence/Organizer feature work. Known issues worth noting: standalone Swift files opened from Finder may fail to run `#Playground`/`#Preview` (177587795); Console may delay interleaved stdout/stderr in parallel testing (165098287); ASan may fail to launch on 27.0 with Xcode ≤ 26.4 (178072780); some simulator runtimes are not fully deleted (141290052).
- **macOS 27 Golden Gate Release Notes** — exists: https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes (see §4).
- **Swift 6.4** is documented at [What's new in Swift](https://developer.apple.com/swift/whats-new), the [WWDC26 Swift guide](https://developer.apple.com/wwdc26/guides/swift/), and the [Swift CHANGELOG](https://raw.githubusercontent.com/swiftlang/swift/main/CHANGELOG.md).
- **Not found:** a separately titled "iOS 27 SDK Release Notes" distinct from the iOS & iPadOS 27 release notes; and a single Apple page that lists all iOS 27 deprecations.

---

## Top concrete migration steps for an iOS 26 SwiftUI app moving to the iOS 27 SDK

Ordered by risk × effort. "Gate" = will block launch or App Store upload.

1. **Adopt the UIScene lifecycle if you haven't (GATE).** Add `UIApplicationSceneManifest` (+ `UIApplicationSupportsMultipleScenes=false` and a `UISceneConfigurations` entry with a `SceneDelegate`) or implement `application(_:configurationForConnecting:options:)`. Verify every target/extension. Foundation for the resizability work below. Migration doc: [Transitioning to the UIKit scene-based life cycle](https://developer.apple.com/documentation/uikit/transitioning-to-the-uikit-scene-based-life-cycle).
2. **Add a launch screen (GATE for upload).** Ensure `UILaunchScreen` (or a storyboard name key) is in `Info.plist`; do this before your first SDK-27 upload to avoid `ITMS-90870`. [TN3208](https://developer.apple.com/documentation/technotes/tn3208-preparing-your-apps-launch-screen-to-meet-app-store-requirements).
3. **Compile with the iOS 27 SDK and fix `@State` source breaks.** Expect "used before being initialized"/synthesized-init/generic-inference errors; follow the release-notes patterns (no initial value at the declaration when assigning in `init`; assign members explicitly in extensions) and [TN3211](https://developer.apple.com/documentation/technotes/tn3211-resolving-swiftUI-source-incompatibilities-for-state-and-contentbuilder).
4. **Do a Liquid Glass visual pass.** Remove `UIDesignRequiresCompatibility` expectations (ignored on SDK-27 builds), then screenshot-test navigation bars, tab bars, toolbars, sheets, menus, buttons and custom backgrounds on iOS 27. Prefer `.buttonStyle(.glass/.glassProminent)` over raw `.glassEffect` on buttons. Re-check menu icons (hidden by default) and `.titleAndIcon`.
5. **Remove layout dependencies on resizability-hostile APIs.** Delete `UIScreen.main` uses; stop using the idiom trait and interface orientation for layout; use size classes, view/superview size, window-scene effective geometry and `windowScene(_:didUpdateEffectiveGeometry:)`. Handle `UIRequiresFullScreen` via [TN3192](https://developer.apple.com/documentation/technotes/tn3192-migrating-your-app-from-the-deprecated-uirequiresfullscreen-key) (discrete resizing, or add `UIRequiresFullScreenIgnoredStartingWithVersion`).
6. **Migrate the document layer if applicable.** Move `FileDocument`/`ReferenceFileDocument` to `Document`/`ReadableDocument`/`WritableDocument`; add the new `previous:` argument to `FileWrapperDocumentWriter.makeFileWrapper`; switch `nonisolated` reader/writer methods to `@concurrent`; drop `Sendable` on `URLDocumentConfiguration`.
7. **Clear new-at-27 deprecation warnings on your own code:** `canOpenURL(_:)` → attempt-and-handle; `UIGraphics*BeginImageContext` quartet → `UIGraphicsImageRenderer`; CoreLocation region monitoring → `CLMonitor`; `View.statusBarHidden(_:)` → `.toolbarVisibility(_, for: .statusBar)`; `.roundedBorder`/`.squareBorder` → `.bordered`; status-bar accessors → window scene; `PreviewProvider` → `#Preview`; `NSBundleResourceRequest` → Background Assets.
8. **Audit against behavior changes:** `TabView` selection validity; selectable `Text` gesture conflicts; trait inheritance in custom presentations; external-display accessories; `@AppEntity(schema: .photos.asset)` compile break; MetricKit recompile (missing-symbol crash).
9. **Check iPhone Mirroring / iPhone-on-Mac behavior** (biometric policy `.deviceOwnerAuthenticationWithBiometricsOrCompanion`, indirect input, drag and drop) using [TN3210](https://developer.apple.com/documentation/technotes/tn3210-optimizing-your-app-for-iphone-mirroring) and Device Hub's resize mode.
10. **Decide the Swift language-mode/upcoming-feature posture.** For a Swift 5-mode target, review the "Swift Compiler – Upcoming Features" settings and consider `SWIFT_APPROACHABLE_CONCURRENCY` (+ `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` for app targets) before attempting Swift 6 mode. Do not disable the macro sandbox (`SWIFTC_DISABLE_SANDBOX`) unless an outer sandbox already exists.
11. **Plan for April 2027:** the iOS 27 SDK becomes an App Store submission requirement then, so schedule the SDK-27 release well before that rather than scrambling ([Apple News](https://developer.apple.com/news/?id=k1mtkt1k)).
12. **If you ship on Mac** (Mac Catalyst or Designed for iPad): rebuild for Apple silicon (macOS 26 is the last Intel/Rosetta release), re-test Catalyst window behavior, and validate the new macOS SwiftUI control appearances (menu images, `NSPopUpButton`/`NSSlider` replacements, slider/checkbox styling).

---

## Uncertainty and gaps (explicit)

- **No single authoritative iOS 27 deprecation list exists.** Apple publishes `deprecated-symbols` index pages for only some frameworks (SwiftUI, PhotosUI, UserNotifications, WidgetKit and AVFoundation have none / 404). For those, "no deprecation found" is not proof of absence. The MapKit/Foundation/AVFoundation/PhotosUI/UserNotifications/WidgetKit negatives are best-effort.
- **Some confirmed deprecations are not in the release notes at all** (CoreLocation region-monitoring trio, the `UIGraphics*` images-context quartet, PassKit/CoreMIDI renames, `View.statusBarHidden(_:)`) and were found only in Apple's symbol metadata. So release-notes-only review misses real changes.
- **`toolbarMinimizeBehavior`'s deprecation attribute is unverified** — the release notes say the new modifier "replaces" it, but I could not retrieve the old symbol page.
- **"New warnings on by default in Xcode 27" is not documented by Apple as a list.** The only clearly documented new default warning I found is the unused throwing unstructured task (`NoUseUnstructuredThrowingTask`) in the Swift 6.4 changelog.
- **The `ENABLE_SWIFT_6_UPCOMING_FEATURES_IN_SWIFT_VERSION_6_0` / `SWIFT_UPCOMING_FEATURE_6_0` aggregate and the per-flag `Condition`** come from the open-source `swift-build` Swift.xcspec, not from Apple's published UI docs; verify the defaults in your Xcode 27 project.
- **Xcode 27's default language mode for new projects is unconfirmed.** Apple's [system requirements](https://developer.apple.com/xcode/system-requirements) lists the *available* modes (Swift 6/5/4.2/4) but no Xcode 27 source states the template default; Apple's [Adopting strict concurrency in Swift 6 apps](https://developer.apple.com/documentation/Swift/AdoptingSwift6) says "new projects default to the Swift 5 language mode" but its prose is Xcode-16-era and may be stale. Existing projects keep their current mode (Swift 6 is opt-in).
- **No Apple-published list of "recommended upcoming features" for Swift 5 mode exists**; the only documented bundle is `SWIFT_APPROACHABLE_CONCURRENCY`, and the per-flag defaults above come from the open-source spec. Likewise, Apple publishes no consolidated "new warnings on by default" list, and `SWIFT_WARNINGS_AS_ERRORS_GROUPS`/`SWIFT_WARNINGS_AS_WARNINGS_GROUPS` exist but are **not confirmed new in Xcode 27**.
- **The build number `27A266a`** in the task prompt is confirmed by Apple's [Software Releases page](https://developer.apple.com/news/releases/) ("Xcode 27 (27A266a) September 14, 2026"), not by the release notes.
- **Some third-party guidance is speculative:** the [DevelopersIO article](https://dev.classmethod.jp/en/articles/ios27-xcode27-migration-preparation-guide/) (written pre-release) predicts an April 2027 mandate and lists trouble spots — the date is now confirmed by Apple, but its component-level "what will break" list is informed guesswork. The `artemnovichkov/xcode-27-system-prompts` GitHub repository is a third-party extraction of Xcode 27's bundled skill text and is useful as a cross-check only.
- **I did not inspect the actual iOS 27 SDK headers or `.swiftinterface`s**, so availability/deprecation claims rest on Apple's published documentation metadata rather than the compiled SDK.
- **[Not found]:** any iOS 27 privacy-manifest / required-reason API change; any macOS-27-specific "Designed for iPad" policy change; a distinct "iOS 27 SDK Release Notes" document separate from the iOS & iPadOS 27 release notes.
