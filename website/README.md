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

## Port configuration

Compose defaults to port 8080. To change it:

```bash
cp .env.example .env
# Edit .env, for example PORT=3000
docker compose up -d
```

`.env` is ignored by Git and excluded from the Docker image.

## Release downloads

The hero and download section link directly to GitHub Releases, so the server does not need to host an installer:

- Repository: https://github.com/DeaglePC/MonitorX
- Release notes: https://github.com/DeaglePC/MonitorX/releases/latest
- `releases.js` queries the public GitHub API for the latest stable release and updates both DMG links and the displayed version.
- If JavaScript is disabled, the API is unavailable/rate-limited, or the release has no matching DMG, the verified v1.2.0 link in `index.html` remains available. Refresh this fallback when publishing a new release.
- This API request is made by the website; MonitorX system monitoring stays local; optional Codex usage monitoring lets the official local CLI query OpenAI.

The `downloads/` mount remains available for optional local files, but the page's buttons no longer use it.

## Local preview without Docker

```bash
cd website && python3 -m http.server 8080
```

## About the page

- `index.html`, `style.css`, `charts.js`: no framework, no build. The charts are drawn with canvas and plain DOM.
- **All chart data is generated in the browser for demonstration** (the page says so next to the charts). System-monitoring screenshots in `images/` come from the running app. The Codex/Claude quota images use the production SwiftUI cards with clearly labeled demo readings. Regenerate both website and README copies with `Scripts/render_usage_screenshots.sh` from the repository root.
- Charts only animate while on screen, pause in background tabs, and do not loop when the visitor prefers reduced motion.
- Light and dark themes follow the system and can be toggled; the choice is remembered in `localStorage`.
- Headline numerals use *Bricolage Grotesque* from Google Fonts. If it can't load (offline, blocked network) the page falls back to system fonts; to self-host it, download the font files into this folder and replace the `<link>` in `index.html` with an `@font-face` rule.
- **Liquid Glass**: `glass.js` drives the screenshot deck and the glass effects. Everywhere it is a blur + saturation + lit rim. In Chromium it additionally generates an SVG displacement map per element so the glass edges refract what is behind them (`backdrop-filter: url(#…)`); Safari and Firefox keep the plain glass. The screenshot section is a fixed dark "wallpaper" band in both themes so the glass has something to refract.
- The screenshot deck supports drag (mouse), swipe (touch), arrow keys, the previous/next buttons and the tab dock.
