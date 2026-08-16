# App Icon Assets

`AppIcon.svg` and the layered SVG files under `IconComposer` are the editable icon
sources authored for this project. Generated PNG, `AppIcon.icns`, and `Assets.car`
files are committed so a normal application build does not rewrite source assets.

Regenerate the derived assets with:

```sh
./Scripts/build-app-icon.sh
```

Unless otherwise noted, these project assets are distributed under the repository's
MIT License.
