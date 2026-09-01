<div align="center">

# XVVIIX - Song Splitter

**Split any song into vocals, drums, bass and instrumental stems - entirely in your browser.**

No upload - No install - No server - Works offline

[**▶ Open the app**](https://xvviix.github.io/song-splitter/)

</div>

---

## What it does

- **Fully independent** - the separation engine is plain JavaScript running in a Web Worker. Nothing is uploaded, nothing is installed, and there is no backend to keep alive.
- **Four stems** - vocals, drums, bass and instrumental.
- **Inline previews** - play every stem straight away.
- **Master editor** - per-stem volume, pan, mute and solo, synced transport with looping, master gain.
- **Export mixdowns** - render a custom mix to WAV in the browser (mute the vocals for an instant karaoke track).
- **Private by design** - your audio physically cannot leave the page.

## How the engine works

This is real-time DSP rather than a neural network, which is what makes it portable enough to run on a static host:

1. **STFT** - a 4096-point short-time Fourier transform (Hann window, 1024 hop) over both channels.
2. **HPSS** - harmonic/percussive separation by median filtering. Filtering across *time* keeps sustained pitches (vocals, bass, keys); filtering across *frequency* keeps broadband transients (drums).
3. **Centre extraction** - vocals are usually mixed centre and phase-correlated between left and right, so per-bin stereo similarity yields a vocal mask.
4. **Band weighting** - energy below ~260 Hz is routed to bass; the vocal mask is limited to roughly 180 Hz-12 kHz.
5. **Reconstruction** - masks are normalised to sum to exactly 1 per bin, so the four stems add back up to the original mix sample-for-sample. Each stem is resynthesised with weighted overlap-add and encoded to WAV.

**Speed:** roughly **7× faster than realtime** - a 3½ minute track separates in about 30 seconds on a typical laptop.

> **Honest limitation:** classic DSP will not match a large neural model such as Demucs. Expect usable, musical stems with some bleed between them - great for karaoke, practice, remixing and sampling, but not a surgical studio acapella.

## Two engines

The site has a **Quality** switch:

| Mode | Engine | Where it runs | Setup |
| --- | --- | --- | --- |
| **Fast** *(default)* | JavaScript DSP | Your browser | None - works instantly |
| **Best** | Demucs `htdemucs` | Your own computer | One-click installer |

**Fast** works everywhere with zero setup and is genuinely offline.

**Best** runs the real Demucs AI model locally. Picking it opens a guided installer
that downloads two small files; double-clicking the installer sets up Python, PyTorch
and Demucs automatically inside its own folder. Once the engine is running, the site
detects it and unlocks Best quality. It uses your GPU if you have an NVIDIA card.

Nothing is ever uploaded in either mode, and there is no cloud service, account or
quota involved. If the local engine is not running, Best silently falls back to the
browser engine so a split never fails.

## Requirements

Any modern browser with Web Workers and the Web Audio API - Chrome, Edge, Firefox or Safari. Tracks up to about 12 minutes; longer ones risk exhausting browser memory.

## Running it locally

It is a static site, so any web server works:

```bash
git clone https://github.com/xvviix/song-splitter
cd song-splitter
python3 -m http.server 8000
```

Then open <http://localhost:8000>.

> Opening `index.html` directly with `file://` will not work - browsers refuse to start Web Workers from that scheme. Serve it over HTTP.

## Deploying

1. Push to GitHub.
2. **Settings → Pages → Build and deployment → Source: GitHub Actions**.
3. Push to `main` - the included workflow publishes the site automatically.

Update the URLs in `index.html` (canonical/OG tags), `sitemap.xml`, `robots.txt` and `404.html` if your repo name differs.

## Project layout

| File | Purpose |
| --- | --- |
| `index.html` | The entire UI, styles and app logic |
| `splitter.worker.js` | The separation engine (STFT, HPSS, masking, WAV encoding) |
| `og.svg` | Social preview card |
| `manifest.webmanifest` | PWA manifest |
| `.github/workflows/deploy.yml` | GitHub Pages deployment |
| `engine/` | The local Demucs engine and its one-click installers |

## Credits

The idea for XVVIIX came from **[Zilola Egamberganova](https://github.com/zilolaegamberganova)**. This implementation is built and maintained by **[XVVIIX](https://github.com/xvviix)**.

---

<div align="center">

Built and maintained by **[XVVIIX](https://github.com/xvviix)**
Original concept by **[Zilola Egamberganova](https://github.com/zilolaegamberganova)**

Released under the [MIT License](LICENSE).

</div>

### Reusing an existing PyTorch

If the installer finds **PyTorch 2.0 or newer** already installed on your system, it creates the environment with `--system-site-packages` and reuses it, downloading only Demucs (a few MB). If PyTorch is missing or older than 2.0, it builds a fully isolated environment and downloads its own copy (~250 MB CPU, ~2.5 GB CUDA).

### Manual setup (no installer)

If you would rather not run a downloaded script, start the engine yourself.
`engine/xvviix_engine.py` is plain Python with no third-party imports, so you
can read it first.

**Windows**

```bat
git clone https://github.com/xvviix/song-splitter
cd song-splitter\engine

python -m venv .venv
.venv\Scripts\activate

pip install demucs soundfile

python xvviix_engine.py
```

**macOS / Linux**

```bash
git clone https://github.com/xvviix/song-splitter
cd song-splitter/engine

python3 -m venv .venv
source .venv/bin/activate

pip install demucs soundfile

python xvviix_engine.py
```

When the terminal prints `READY`, open the site and pick **Best**. The page
polls `127.0.0.1:8765` and unlocks it automatically. Press `Ctrl+C` to stop.
