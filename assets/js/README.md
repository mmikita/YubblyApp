# Solver JavaScript

`solver.js` is the generated bundle used by the hidden platform WebView:

1. `meriyah-astring.min.js` — Meriyah 6.1.4 + astring, from
   [`yt-dlp/ejs`](https://github.com/yt-dlp/ejs) (Unlicense; bundled
   dependencies keep their ISC/MIT notices).
2. `solver-prelude.js` — exposes `meriyah`/`astring` as globals expected by
   the ejs core.
3. `ejs-core.min.js` — yt-dlp ejs core, from the same repository (Unlicense).
4. `solver-bootstrap.js` — `window.__yubblySolveN(playerUrl, playerJs, n)`.

Sources are copied from the `yt-dlp-ejs` package installed with yt-dlp
2026.03.17. To regenerate:

```sh
cat meriyah-astring.min.js solver-prelude.js ejs-core.min.js solver-bootstrap.js > solver.js
```

The app only uses this bundle to transform YouTube's `n` query parameter with
the player JavaScript fetched at runtime. It does not contain or store tokens,
cookies or media.
