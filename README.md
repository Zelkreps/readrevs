# ReadRevs

ReadRevs is a native SwiftUI macOS app for collecting and researching public written App Store reviews.

## What it does

- Finds apps by name through Apple's public iTunes Search API, or accepts an App Store ID/URL.
- Checks the latest written reviews across all 175 App Store storefronts with bounded concurrency.
- Filters the synced dataset by full text, rating, storefront, version, and sort order.
- Exports every synced review as lossless JSON or spreadsheet-safe CSV.
- Creates a local read-only research bundle and opens an embedded Codex conversation with an editable, prefilled analysis prompt. Nothing is sent automatically.
- Saves completed research conversations locally so previous analyses can be reopened from the history button.
- Lets you choose the Codex model and reasoning level and customize or restore the default analysis prompt in Settings.
- Keeps the saved app library locally; no App Store Connect or developer account is required.

## Data sources and limits

- App lookup: `https://itunes.apple.com/lookup?id={id}&country={country}`
- App suggestions: `https://itunes.apple.com/search?term={term}&country={country}&media=software&entity=software`
- Written reviews: `https://itunes.apple.com/{country}/rss/customerreviews/page=1/id={id}/sortby=mostrecent/json`

The app currently loads the first feed page per storefront, up to 50 of the latest written reviews in each region. Apple's customer-review RSS feed is a legacy public endpoint without a documented stability or rate-limit contract. Lookup ratings are storefront-specific and are displayed separately from metrics calculated over the synced written-review dataset.

## Build

Requirements:

- macOS 14 or newer
- Xcode 26 / Swift 6.2 or newer

Run tests:

```sh
swift test
```

Build the app bundle, regenerate the icon asset catalog, and apply an ad-hoc local signature:

```sh
./Scripts/package-app.sh
```

The resulting application is written to `.build/app/ReadRevs.app`.

## App icon

`Assets/AppIcon.svg` is the editable vector source. `Scripts/build-app-icon.sh` renders the transparent 1024 px master, generates every required macOS representation, and compiles `AppIcon.icns` plus `Assets.car` with Xcode's `actool`.
