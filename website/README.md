# MonitorX landing page

Pure static site (HTML + CSS + a little JS, no build step) served by nginx.

## Run with Docker

```bash
cd website
docker compose up -d --build        # http://localhost:8080  (PORT=3000 docker compose up -d to change)
```

or without compose:

```bash
docker build -t monitorx-site website
docker run -d --name monitorx-site -p 8080:80 monitorx-site
```

Health check: `GET /healthz` → `ok`.

## Publishing a new release

The download button points at `downloads/MonitorX.dmg`.

```bash
cp ../dist/MonitorX-<version>.dmg downloads/MonitorX.dmg
```

With `docker compose` the folder is mounted read-only into the container, so no rebuild is needed.
With plain `docker build` the file is baked into the image, so rebuild after replacing it.

## Local preview without Docker

```bash
cd website && python3 -m http.server 8080
```

## About the page

- `index.html`, `style.css`, `charts.js`: no framework, no build. The charts are drawn with canvas and plain DOM.
- **All chart data is generated in the browser for demonstration** (the page says so next to the charts). Real screens are the screenshots in `images/`.
- Charts only animate while on screen, pause in background tabs, and do not loop when the visitor prefers reduced motion.
- Light and dark themes follow the system and can be toggled; the choice is remembered in `localStorage`.
- Headline numerals use *Bricolage Grotesque* from Google Fonts. If it can't load (offline, blocked network) the page falls back to system fonts; to self-host it, download the font files into this folder and replace the `<link>` in `index.html` with an `@font-face` rule.
- **Liquid Glass**: `glass.js` drives the screenshot deck and the glass effects. Everywhere it is a blur + saturation + lit rim. In Chromium it additionally generates an SVG displacement map per element so the glass edges refract what is behind them (`backdrop-filter: url(#…)`); Safari and Firefox keep the plain glass. The screenshot section is a fixed dark "wallpaper" band in both themes so the glass has something to refract.
- The screenshot deck supports drag (mouse), swipe (touch), arrow keys, the previous/next buttons and the tab dock.
