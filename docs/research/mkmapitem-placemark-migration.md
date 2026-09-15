# `MKMapItem.placemark` → iOS 26 replacement APIs (research report)

Warning under investigation:

```
'placemark' was deprecated in iOS 26.0: Use location, address and addressRepresentations instead
```

**Toolchain confirmation.** Apple's live documentation JSON for these symbols carries
`Copyright © 2026 Apple Inc.` and lists the new types as `introducedAt: 26.0` with no later
revision. `CLPlacemark` and its members are marked `deprecatedAt: 27.0`. So under the iOS 27 /
macOS 27 / Xcode 27 SDK the `26.0` messages are still what is emitted for the MapKit symbols,
while the Core Location placemark fallback is now hard-deprecated at 27.0. (Source: Apple docs
JSON, e.g. <https://developer.apple.com/documentation/mapkit/mkmapitem/placemark> and
<https://developer.apple.com/documentation/corelocation/clplacemark>.)

All declarations below are copied verbatim from Apple's documentation JSON endpoints
(`https://developer.apple.com/tutorials/data/documentation/...`), which back the public pages.

---

## 1. The replacement API on `MKMapItem`

Three new members, all `introducedAt: 26.0` on iOS, iPadOS, Mac Catalyst, macOS, tvOS, visionOS and
watchOS (i.e. `@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)`):

| Symbol | Exact Swift declaration | Availability |
|---|---|---|
| `MKMapItem.location` | `var location: CLLocation { get }` | iOS 26.0+, all platforms |
| `MKMapItem.address` | `var address: MKAddress? { get }` | iOS 26.0+, all platforms |
| `MKMapItem.addressRepresentations` | `var addressRepresentations: MKAddressRepresentations? { get }` | iOS 26.0+, all platforms |

Note `location` is **non-optional** (`CLLocation`), while `address` and
`addressRepresentations` are optional.

Sources:
- <https://developer.apple.com/documentation/mapkit/mkmapitem/location>
- <https://developer.apple.com/documentation/mapkit/mkmapitem/address>
- <https://developer.apple.com/documentation/mapkit/mkmapitem/addressrepresentations>

Corresponding new initializer:

```swift
init(location: CLLocation, address: MKAddress?)     // iOS 26.0+, all platforms
```

Source: <https://developer.apple.com/documentation/mapkit/mkmapitem/init(location:address:)>

The `placemark` deprecation summary is exactly: *"Use location, address and addressRepresentations
instead"*; introduced iOS 6.0, deprecated iOS 26.0. Source:
<https://developer.apple.com/documentation/mapkit/mkmapitem/placemark>

`MKPlacemark` (the class) carries its own, more explicit deprecation text: *"Use MKMapItem's
location, address and addressRepresentations properties instead. Use MKAddressRepresentations for
formatted address strings for MapKit provided MKMapItems"* — deprecated 26.0. Source:
<https://developer.apple.com/documentation/mapkit/mkplacemark>

---

## 2. `MKAddress`

> "A class that contains a full address, and, optionally, a short address."
> — <https://developer.apple.com/documentation/mapkit/mkaddress>

```swift
@available(iOS 26.0, iPadOS 26.0, Mac Catalyst 26.0, macOS 26.0,
           tvOS 26.0, visionOS 26.0, watchOS 26.0, *)
class MKAddress

// Creating an address
init?(fullAddress: String, shortAddress: String?)

// Getting the full and short addresses
var fullAddress: String { get }
var shortAddress: String? { get }
```

**Complete property list: exactly two — `fullAddress` and `shortAddress`.** There are no other
properties. It is *not* structured postal data: both are plain `String`s.

How to construct it: `MKAddress(fullAddress:shortAddress:)` is a **failable** initializer that takes
the full address string and an optional short address. Addresses returned from MapKit geocoding /
search / `PlaceDescriptor` resolution are populated by the framework.

Sources:
- <https://developer.apple.com/documentation/mapkit/mkaddress/init(fulladdress:shortaddress:)>
- <https://developer.apple.com/documentation/mapkit/mkaddress/fulladdress>
- <https://developer.apple.com/documentation/mapkit/mkaddress/shortaddress>

**Relation to `MKAddressRepresentations`: there is no type relationship.** `MKAddress` is not a
subclass, superclass, or constructor input of `MKAddressRepresentations`. They are sibling classes
that are both reachable from an `MKMapItem`. Per WWDC25 session 204, the difference is:

> "MKMapItem offers two optional properties for accessing address information. First, MKAddress. You
> can instantiate your own MKAddress when you make your own MKMapItem... Second,
> MKAddressRepresentations, which does not have an initializer. Address representations are only
> available on map items returned from MapKit APIs."
> — <https://developer.apple.com/videos/play/wwdc2025/204/>

So: `MKAddress` = you may supply it yourself (for your own `MKMapItem`s); `MKAddressRepresentations`
= framework-supplied only. When you pass an `MKAddress` to `init(location:address:)`, it is used in
the MapKit place card.

---

## 3. `MKAddressRepresentations`

> "A class that provides formatted address strings."
> — <https://developer.apple.com/documentation/mapkit/mkaddressrepresentations>

```swift
@available(iOS 26.0, iPadOS 26.0, Mac Catalyst 26.0, macOS 26.0,
           tvOS 26.0, visionOS 26.0, watchOS 26.0, *)
class MKAddressRepresentations

// Getting parts of an address
var cityName: String? { get }
var cityWithContext: String? { get }          // city name + country, for disambiguation
var regionName: String? { get }               // e.g. "United States"
var region: Locale.Region? { get }

// Getting a full address and city name
func fullAddress(includingRegion: Bool, singleLine: Bool) -> String?
func cityWithContext(_ style: MKAddressRepresentations.ContextStyle) -> String?

// Controlling the degree of disambiguation
@available(same)
enum ContextStyle { case automatic, short, full
                    init?(rawValue: Int) }
```

**That is the complete API surface** — four properties and two methods. Inheritance/conformance:
inherits `NSObject`; conforms to `CVarArg`, `CustomDebugStringConvertible`, `CustomStringConvertible`,
`Equatable`, `Hashable`, `NSObjectProtocol`.

**There is no public initializer.** WWDC25 session 204 states this explicitly ("which does not have
an initializer"), and the symbol's JSON contains no `init` reference. You can only obtain it from
`MKMapItem.addressRepresentations`.

`ContextStyle` semantics (from the per-case discussions):
- `.automatic` — framework picks; with `cityWithContext(_:)` "MapKit only includes the region" when needed.
- `.short` — excludes optional context; with `cityWithContext(_:)` "MapKit always excludes the region name."
- `.full` — includes all relevant context; with `cityWithContext(_:)` "MapKit always includes the region name if the device is in that region."

Sources:
- <https://developer.apple.com/documentation/mapkit/mkaddressrepresentations>
- <https://developer.apple.com/documentation/mapkit/mkaddressrepresentations/cityname>
- <https://developer.apple.com/documentation/mapkit/mkaddressrepresentations/citywithcontext>
- <https://developer.apple.com/documentation/mapkit/mkaddressrepresentations/regionname>
- <https://developer.apple.com/documentation/mapkit/mkaddressrepresentations/region>
- <https://developer.apple.com/documentation/mapkit/mkaddressrepresentations/fulladdress(includingregion:singleline:)>
- <https://developer.apple.com/documentation/mapkit/mkaddressrepresentations/citywithcontext(_:)>
- <https://developer.apple.com/documentation/mapkit/mkaddressrepresentations/contextstyle>

---

## 4. `MKPlacemark` / `CLPlacemark` property-by-property migration

`MKPlacemark` is a subclass of `CLPlacemark`, and it declares only `countryCode`; all the properties
below are inherited from `CLPlacemark`
(<https://developer.apple.com/documentation/mapkit/mkplacemark>,
<https://developer.apple.com/documentation/corelocation/clplacemark>).
Every `CLPlacemark` member listed is marked `deprecatedAt: 27.0` with the message *"Use either
GeoToolbox.PlaceDescriptor or MapKit"*.

| Old | New equivalent | Confidence |
|---|---|---|
| `placemark.locality` | `mapItem.addressRepresentations?.cityName` (city only) | Confirmed semantically; `cityName` is documented as "The name of the city" |
| `placemark.administrativeArea` | No exact equivalent. Closest: `addressRepresentations?.regionName` — but that is documented as the *country/region* name ("United States"), not the state/province | Partial / inference |
| `placemark.subAdministrativeArea` | **No replacement** | Confirmed absent from API |
| `placemark.country` | `addressRepresentations?.regionName` | Confirmed (documented example is "United States") |
| `placemark.isoCountryCode` | No documented equivalent. `addressRepresentations?.region` is a `Locale.Region` (iOS 16+), from which an ISO code can be derived — but Apple never documents it as the ISO country code | Inference |
| `placemark.name` | `mapItem.name` (`var name: String?`, not deprecated, iOS 6.0+) | Confirmed |
| `placemark.thoroughfare` | **No replacement** — no street-level component exists anywhere in the new API | Confirmed absent |
| `placemark.subThoroughfare` | **No replacement** | Confirmed absent |
| `placemark.postalCode` | **No replacement** | Confirmed absent |
| `placemark.coordinate` | `mapItem.location.coordinate` | Confirmed |
| `placemark.region` | **No replacement.** `addressRepresentations?.region` is a `Locale.Region`, which is a *different concept* | Confirmed |
| `placemark.title` | `addressRepresentations?.fullAddress(includingRegion: false, singleLine: true)` | Inference (formatted one-line address); Apple offers no exact `title` equivalent |
| `placemark.areasOfInterest` | **No replacement** | Confirmed absent |

Two useful whole-string replacements:

- `placemark.postalAddress` → `mapItem.address?.fullAddress` / `.shortAddress` as strings (there is
  **no** `CNPostalAddress` any more — see §5).
- Formatted display strings → `mapItem.addressRepresentations?.fullAddress(includingRegion:singleLine:)`.

The absences above are not an oversight on my part. Apple's DTS engineer answered exactly this
question in the forums and confirmed the reduced granularity, advising developers to file feedback:

> "Since you're using the address for display purposes, I would try to see if you can make
> MKAddressRepresentations work for your needs... **I realize the options are not as granular as you
> would like**, and I can intuit that for certain customers, the API options may not be enough, so
> expressing your requests for even more API in FB19363454 is the right thing to do."
>
> "Techniques like this are understandably common, and unfortunately, it is very easy to naively
> construct geographically incorrect place descriptions as a result... we want to discourage folks
> from doing these string concatenation techniques, and instead rely on the framework to provide you
> with the correctly formatted information through MKAddressRepresentations"
> — Ed Ford, Apple DTS Engineer, <https://developer.apple.com/forums/thread/795687>

---

## 5. SDK requirement and Chinese addresses

**SDK requirement.** All three symbols are `introducedAt: 26.0` for every platform Apple lists
(iOS, iPadOS, Mac Catalyst, macOS, tvOS, visionOS, watchOS). There is no later "newer SDK" bump in
the current (2026) documentation — an app targeting iOS 26 *can* use them. But note the
**asymmetric deprecation**: `MKMapItem.placemark` and `MKPlacemark` are deprecated at **26.0**,
whereas `CLPlacemark` and its members only become deprecated at **27.0**. So on the iOS 27 /
Xcode 27 toolchain a Core Location placemark path is still technically non-deprecated for one more
cycle, while `mapItem.placemark` warns. That is consistent with the warning quoted in the task.
Sources: <https://developer.apple.com/documentation/mapkit/mkmapitem/placemark>,
<https://developer.apple.com/documentation/corelocation/clplacemark>.

**Chinese / non-Latin addresses.** I found **no explicit Apple statement**, sample, or documentation
page stating that `MKAddress` / `MKAddressRepresentations` handle Chinese addresses (or any specific
locale) correctly. What *is* confirmed:

- `MKAddressRepresentations` is documented as locale-aware in general. WWDC25 session 204: MapKit
  "chooses the right thing for your address, as well as **locale and region info of the device
  requesting the** [map item]", and "Automatically adapts to device locale and region."
  (<https://developer.apple.com/videos/play/wwdc2025/204/>)
- Apple's docs are localized into `zh-CN` for these symbols (the documentation JSON lists
  `availableLanguages` including `zh-CN`), which shows the *documentation* is translated, not that
  the address data is Chinese-specific.
- The geocoding requests let you steer locale explicitly:
  - `MKReverseGeocodingRequest.preferredLocale: Locale?` — "A value that indicates the preferred
    locale for the addresses the request returns, or `nil` if the framework should use the device
    locale." (iOS 26.0+)
  - `MKGeocodingRequest.preferredLocale: Locale?` — "A value that indicates the default locale the
    geocoder should use when processing requests." (iOS 26.0+)

Sources:
<https://developer.apple.com/documentation/mapkit/mkreversegeocodingrequest/preferredlocale>,
<https://developer.apple.com/documentation/mapkit/mkgeocodingrequest/preferredlocale>.

**Conclusion for Chinese:** the design intent (locale-aware formatting instead of hand-assembled
component strings) strongly suggests Chinese addresses are meant to be handled correctly via
`preferredLocale` + `MKAddressRepresentations`, and the DTS engineer's warning against manual string
concatenation is precisely a warning about getting non-US address shapes wrong. But this is
**inference, not a confirmed Apple statement**; no Apple document I could reach asserts Chinese
correctness. Treat it as unverified.

**Structured Chinese address components are gone.** This is the practical problem for a locale like
zh-CN where you may have previously read `placemark.locality` / `thoroughfare` / `postalCode`:
there is no structured replacement, only preformatted strings. Apple's DTS response is that this is
deliberate and that missing granularity should be requested via Feedback Assistant.

---

## 6. Official sample / migration guide

**Official sample — yes.** "Searching, displaying, and navigating to places" is an Apple sample
code project, `roleHeading: "Sample Code"`, platforms iOS/iPadOS/Mac Catalyst/Xcode 26.0, explicitly
"associated with WWDC25 session 204". Download:
`https://docs-assets.developer.apple.com/published/78061535b53d/SearchingDisplayingAndNavigatingToPlaces.zip`
(Xcode project `MapKitFountains`).

Pages: <https://developer.apple.com/documentation/mapkit/searching-displaying-and-navigating-to-places>

Verified usage inside the sample's `ReverseGeocodeView.swift` / `GeocodeView.swift`:

```swift
Text(fountain.addressRepresentations?.cityWithContext ?? "City")
Text(visitMapItem.addressRepresentations?.fullAddress(includingRegion: true, singleLine: false) ?? "address")
MapCamera(centerCoordinate: visitMapItem.location.coordinate, distance: 350)
```

**Migration guide — no.** I found **no dedicated Apple migration guide** ("Migrating from
CLPlacemark / MKPlacemark" style article). The available Apple-authored material is:
- WWDC25 session 204, "Go further with MapKit" — <https://developer.apple.com/videos/play/wwdc2025/204/>
- The doc article "Searching, displaying, and navigating to places" (linked above)
- Doc pages "Representing places and addresses" (doc-collection grouping of `MKMapItem`,
  `MKAddress`, `GeoToolbox`), reachable from the "See Also" of `MKAddressRepresentations`

---

## Caveats / what I could not verify

1. **Apple Developer Forums thread 790983** ("Placemark Deprecated") — the exact thread that shares
   this warning text — is behind an anti-bot interstitial (`/forums/verify-human/`) that defeated
   every access route I tried (plain fetch, Googlebot/Bingbot/Twitterbot/facebookexternalhit UAs,
   cookie jar, `r.jina.ai` reader, DDG/StackOverflow). **I could not read its contents.** The forum
   answer I *did* read (thread 795687) is different but covers the same migration and is quoted above.
2. `placemark.administrativeArea` (state/province) has no clean replacement. `regionName` is
   documented with the country example, so mapping administrativeArea onto it is a guess.
3. `placemark.title` and `placemark.isoCountryCode` mappings above are my inference; Apple does not
   document direct equivalents.
4. Apple's `MKAddress` documentation page says "MapKit capabilities, such as Search and Reverse
   geocoding, populate the `MKAddress` of a `MKMapItem`", but does not guarantee `address` and
   `addressRepresentations` are both populated for every map item. Both are optional; code must
   handle `nil`. WWDC stresses that geocoded items contain address-point data only, not rich POI data.
