# docs/

GitHub Pages site for Aetherfin. Plain HTML + CSS, no build step.

## How deployment works

The site is deployed by `.github/workflows/pages.yml` on every push to `main`
that touches `docs/**` (or via manual trigger from the Actions tab).
The workflow uploads the `docs/` folder as a Pages artifact and the
`actions/deploy-pages` action publishes it.

## One-time setup

In the repo on GitHub:

1. **Settings → Pages**
2. Under **Build and deployment**, set **Source** to **GitHub Actions**

That's it — no branch/folder picker, the workflow handles everything.

The site will be live at `https://aetherfin.github.io/mobile-app/`.

## Files

- `index.html` — landing page
- `styles.css` — styles (mirrors the app's design tokens)
- `assets/` — logos and screenshots
- `assets/screencapture/demo.mp4` / `demo.webm` — hero demo video (~1.2 MB each)
- `.nojekyll` — bypass Jekyll processing
- `robots.txt` — allow all crawlers
