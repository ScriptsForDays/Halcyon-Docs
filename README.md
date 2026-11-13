# Halcyon docs

The website for [Halcyon](https://github.com/ScriptsForDays/Halcyon), a UI library for Roblox script hubs.

Live at https://scriptsfordays.github.io/Halcyon-Docs/

The library itself lives in its own repo and is all Luau. This repo holds only the site: plain HTML, CSS and a little JavaScript, with no build step. Open `index.html` in a browser to preview it, or serve the folder with any static server.

Pushing to `main` publishes the site through GitHub Pages, and so does a daily build, so the demo keeps up with the library.

The screenshots in `img/` are taken from the library's example hub in Roblox Studio and match the ones in the library's `assets/` folder.

## The demo

`play.html` runs the real library and its example hub in the browser. `play/engine/roblox.luau` is a small stand-in for the Roblox engine written in Luau, `play/render.js` draws its instances as HTML, and the Luau runtime is [luau-web](https://www.npmjs.com/package/luau-web).

The library and example aren't kept in this repo. Copy them in before serving the folder:

```bash
node scripts/sync-library.mjs
```

That reads a library checkout next to this repo (`../YaxUI`). `--remote` fetches the library's `main` branch instead, which is what the Pages build does before it runs `tests/smoke.mjs` to make sure the hub boots.

Third-party code in the demo: luau-web (MIT, `play/vendor/luau-web/LICENSE`), Lucide icons (ISC) and the Discord mark from Simple Icons (CC0), both in `play/icons.js`.
