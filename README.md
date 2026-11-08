# Catalog

A first version of a product catalog for merchants who run their shop from their phone, built in SwiftUI on the
[DummyJSON Products API](https://dummyjson.com/docs/products). Home starts with what needs attention (low and out of
stock), then a shelf per category. A product shows its stock, copies its SKU and barcode in one tap, and has Restock
and Share.

## Run it

Open `Catalog.xcodeproj`, pick the **Catalog** scheme and an iPhone simulator, press Run. No setup, no keys, no
third-party packages. Xcode 27.2, Swift 6, iOS 17 and later.

```sh
(cd Packages/CatalogKit && xcodebuild test -scheme CatalogKit -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ../../.build/dd-kit)
```

To see slow or offline screens, add `-ui-test-scenario slow` or `-ui-test-scenario offline` to the launch arguments.

## Decisions

**Product**

- **A merchant's view, not a shop window.** The first question is "what is running out?", so Home answers it first.
  Stock is always an icon, a word and a count, never colour alone.
- **The API's stock label, not my own threshold.** The API calls 7 left "Low Stock" on one product and "In Stock" on
  another, so I show what it says.
- **Restock lasts until the app quits.** The API's `PUT` answers but never saves, so a real save waits for a backend.

**Code**

- **MVVM, not TCA.** No extra library to learn or explain. Each screen has one `State`, so one test checks the whole
  screen with `==`.
- **A repository protocol, not a struct of closures.** Plain Swift, and one fake covers every test.
- **No DTO layer.** The API's fields already fit the screens. I'll add one when they stop fitting.
- **My own image loader, not `AsyncImage`.** `AsyncImage` decodes at full size and keeps nothing, which makes a photo
  grid stutter. Mine decodes at display size and keeps recent photos in memory.
- **Pages of 12, then 24, then 48.** The first screen comes fast, and a long scroll needs few requests.
- **Sorting on the server, not the phone.** The phone only holds the pages it loaded, so sorting them there would be
  wrong.
- **iOS 17, not 18.** More merchants' phones run it. The zoom from a cell to a product is iOS 18 only; on 17 the
  product opens as a plain full-screen cover.

## Not done, and why

**The API can't do it yet**

- **SKU and barcode search, and scanning.** The API's search matches names and descriptions only. Faking it on the
  phone would miss products that aren't loaded.
- **Filter by stock status.** The API has none, so "Needs attention only" reads products sorted by stock and stops
  at the first page with nothing low. A real filter belongs on the server.

**Left for the next version**

- **Offline.** No cache and no "connection lost" banner. When a request fails you get a plain message and Try again,
  and what is already on screen stays. Next: keep the last catalog on the phone (`Persistence` has a tested file cache
  ready).
- **Localization.** English only, no string catalog yet. Prices are in USD because the API's are.
- **Low-stock alerts.** Need push notifications and a backend.
- **iPad layout.** iPhone first, where merchants check stock between customers.
- **Analytics.** None yet, so the app can't tell how merchants use it. The plan is below.

## How we'd know it works for merchants

Not measured yet: this version has no analytics. The plan:

- **Track:** time from launch to a low-stock product; restocks, SKU copies and shares per product opened; errors and
  Try again per screen.
- **How it runs:** Xcode Organizer and MetricKit give crashes, hangs, launch time and scroll hitches for free.
- **What merchants do:** events through one `AnalyticsProtocol`, so the vendor is one file. My pick is Firebase (free,
  events plus Crashlytics); Amplitude or Mixpanel for deeper funnels, TelemetryDeck if privacy comes first.
- **First:** watch five merchants find and restock a low-stock product.

## How AI was used

Claude Code wrote most of the code and tests, with screens built in parallel; gpt-image drew icon options. I set the
rules, made the decisions above, reviewed every change and checked each screen on the simulator. What I changed:

- **Share was the main button.** For a merchant, Restock is.
- **Category chips opened a new screen.** Now they filter Home in place.
- **Planned a stock threshold and a list price.** The API labels 7 left both ways, and `price` is before the discount.
- **The product flashed on open, and photos scaled as they faded in.** Now the list's photo stays until the sharp one
  is ready, and photos only fade.
