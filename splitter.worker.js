/*
 * XVVIIX separation engine - pure JavaScript, runs entirely in the browser.
 *
 * Algorithm (no neural net, no server, no downloads):
 *   1. STFT of both channels (Hann window, 4096 frame / 1024 hop).
 *   2. HPSS - harmonic/percussive source separation via median filtering.
 *        median across TIME  -> harmonic (sustained pitches: vocals, bass, keys)
 *        median across FREQ  -> percussive (broadband transients: drums)
 *   3. Center-channel extraction - vocals sit centred and correlated across
 *      L/R, instruments are usually panned. Per-bin similarity gives a
 *      centre mask.
 *   4. Band weighting - bass below ~260 Hz, vocals in the ~180 Hz-12 kHz range.
 *   5. Masks are normalised so they sum to exactly 1 per bin, which means the
 *      four stems reconstruct the original mix sample-for-sample.
 *   6. ISTFT with weighted overlap-add for each requested stem.
 */

'use strict';

/* ------------------------------ FFT ------------------------------ */
class FFT {
  constructor(n) {
    this.n = n;
    this.levels = Math.log2(n) | 0;
    if (2 ** this.levels !== n) throw new Error('FFT size must be a power of 2');
    this.cos = new Float32Array(n / 2);
    this.sin = new Float32Array(n / 2);
    for (let i = 0; i < n / 2; i++) {
      this.cos[i] = Math.cos((2 * Math.PI * i) / n);
      this.sin[i] = Math.sin((2 * Math.PI * i) / n);
    }
    this.rev = new Uint32Array(n);
    for (let i = 0; i < n; i++) {
      let x = i, r = 0;
      for (let j = 0; j < this.levels; j++) { r = (r << 1) | (x & 1); x >>= 1; }
      this.rev[i] = r;
    }
  }
  // in-place complex FFT; inverse = true performs the unscaled inverse
  transform(re, im, inverse) {
    const n = this.n, rev = this.rev, cos = this.cos, sin = this.sin;
    for (let i = 0; i < n; i++) {
      const j = rev[i];
      if (j > i) {
        let t = re[i]; re[i] = re[j]; re[j] = t;
        t = im[i]; im[i] = im[j]; im[j] = t;
      }
    }
    const s = inverse ? 1 : -1;
    for (let size = 2; size <= n; size <<= 1) {
      const half = size >> 1, step = n / size;
      for (let i = 0; i < n; i += size) {
        for (let j = i, k = 0; j < i + half; j++, k += step) {
          const c = cos[k], sn = s * sin[k];
          const l = j + half;
          const tre = re[l] * c - im[l] * sn;
          const tim = re[l] * sn + im[l] * c;
          re[l] = re[j] - tre; im[l] = im[j] - tim;
          re[j] += tre;        im[j] += tim;
        }
      }
    }
  }
}

/* --------------------------- median helper --------------------------- */
// Small windows (<= 33), so insertion sort on a scratch array beats anything fancier.
function medianOf(scratch, len) {
  for (let i = 1; i < len; i++) {
    const v = scratch[i];
    let j = i - 1;
    while (j >= 0 && scratch[j] > v) { scratch[j + 1] = scratch[j]; j--; }
    scratch[j + 1] = v;
  }
  const m = len >> 1;
  return (len & 1) ? scratch[m] : 0.5 * (scratch[m - 1] + scratch[m]);
}

/* ------------------------------ config ------------------------------ */
const FRAME = 4096;
const HOP = 1024;
const T_MED = 17;   // frames, harmonic median window
const F_MED = 17;   // bins, percussive median window
const EPS = 1e-10;

function hann(n) {
  const w = new Float32Array(n);
  for (let i = 0; i < n; i++) w[i] = 0.5 - 0.5 * Math.cos((2 * Math.PI * i) / n);
  return w;
}

/* ---------------------------- WAV encoder ---------------------------- */
function encodeWav(left, right, sampleRate) {
  const len = left.length;
  const bytes = 44 + len * 4; // stereo 16-bit
  const buf = new ArrayBuffer(bytes);
  const dv = new DataView(buf);
  const wr = (o, s) => { for (let i = 0; i < s.length; i++) dv.setUint8(o + i, s.charCodeAt(i)); };
  wr(0, 'RIFF'); dv.setUint32(4, bytes - 8, true); wr(8, 'WAVE');
  wr(12, 'fmt '); dv.setUint32(16, 16, true); dv.setUint16(20, 1, true);
  dv.setUint16(22, 2, true); dv.setUint32(24, sampleRate, true);
  dv.setUint32(28, sampleRate * 4, true); dv.setUint16(32, 4, true); dv.setUint16(34, 16, true);
  wr(36, 'data'); dv.setUint32(40, len * 4, true);
  let o = 44;
  for (let i = 0; i < len; i++) {
    let l = left[i], r = right[i];
    l = l > 1 ? 1 : l < -1 ? -1 : l;
    r = r > 1 ? 1 : r < -1 ? -1 : r;
    dv.setInt16(o, l < 0 ? l * 0x8000 : l * 0x7fff, true); o += 2;
    dv.setInt16(o, r < 0 ? r * 0x8000 : r * 0x7fff, true); o += 2;
  }
  return buf;
}

/* ------------------------------ engine ------------------------------ */
function separate(L, R, sampleRate, wanted, onProgress) {
  const N = L.length;
  const bins = FRAME / 2 + 1;
  const fft = new FFT(FRAME);
  const win = hann(FRAME);

  const nFrames = Math.ceil(N / HOP) + 1;
  const padded = (nFrames + 1) * HOP + FRAME;

  // output accumulators, only for the stems actually requested
  const out = {};
  for (const s of wanted) {
    out[s] = { l: new Float32Array(padded), r: new Float32Array(padded) };
  }
  const wsum = new Float32Array(padded); // sum of squared windows for WOLA

  // ring buffer of recent magnitude frames, for the temporal median
  const ring = [];
  for (let i = 0; i < T_MED; i++) ring.push(new Float32Array(bins));
  const ringMeta = new Array(T_MED).fill(null);
  let ringPos = 0;

  // scratch
  const re1 = new Float32Array(FRAME), im1 = new Float32Array(FRAME);
  const re2 = new Float32Array(FRAME), im2 = new Float32Array(FRAME);
  const magM = new Float32Array(bins);
  const harm = new Float32Array(bins);
  const perc = new Float32Array(bins);
  const centre = new Float32Array(bins);
  const tScratch = new Float32Array(T_MED);
  const fScratch = new Float32Array(F_MED);
  const ore = new Float32Array(FRAME), oim = new Float32Array(FRAME);

  // frequency landmarks
  const hz = i => (i * sampleRate) / FRAME;
  const half = T_MED >> 1;

  const stored = []; // spectra held while waiting for the median window to fill

  const totalFrames = nFrames + half;
  let lastPct = -1;

  for (let f = 0; f < totalFrames; f++) {
    const start = (f - 0) * HOP;

    if (f < nFrames) {
      // ---- analysis ----
      for (let i = 0; i < FRAME; i++) {
        const idx = start + i - (FRAME >> 1);
        const s = (idx >= 0 && idx < N) ? i : -1;
        const wv = win[i];
        if (idx >= 0 && idx < N) {
          re1[i] = L[idx] * wv; re2[i] = R[idx] * wv;
        } else {
          re1[i] = 0; re2[i] = 0;
        }
        im1[i] = 0; im2[i] = 0;
      }
      fft.transform(re1, im1, false);
      fft.transform(re2, im2, false);

      const cl = new Float32Array(bins), cli = new Float32Array(bins);
      const cr = new Float32Array(bins), cri = new Float32Array(bins);
      const mag = ring[ringPos];
      for (let i = 0; i < bins; i++) {
        cl[i] = re1[i]; cli[i] = im1[i];
        cr[i] = re2[i]; cri[i] = im2[i];
        const ml = Math.hypot(re1[i], im1[i]);
        const mr = Math.hypot(re2[i], im2[i]);
        mag[i] = 0.5 * (ml + mr);
      }
      ringMeta[ringPos] = { f, cl, cli, cr, cri };
      stored.push(ringMeta[ringPos]);
      ringPos = (ringPos + 1) % T_MED;
    } else {
      ringMeta[ringPos] = null;
      ring[ringPos].fill(0);
      ringPos = (ringPos + 1) % T_MED;
    }

    // we can emit the frame that sits in the middle of the ring
    const emitIdx = f - half;
    if (emitIdx < 0 || emitIdx >= nFrames) continue;

    const meta = stored.shift();
    if (!meta) continue;

    // ---- HPSS masks ----
    const centreRing = (ringPos + T_MED - 1 - half + T_MED) % T_MED;
    const magCur = ring[centreRing];

    for (let i = 0; i < bins; i++) {
      for (let t = 0; t < T_MED; t++) tScratch[t] = ring[t][i];
      harm[i] = medianOf(tScratch, T_MED);
    }
    const fHalf = F_MED >> 1;
    for (let i = 0; i < bins; i++) {
      let c = 0;
      for (let k = -fHalf; k <= fHalf; k++) {
        const j = i + k;
        fScratch[c++] = (j >= 0 && j < bins) ? magCur[j] : 0;
      }
      perc[i] = medianOf(fScratch, F_MED);
    }

    // ---- centre (vocal) likeness ----
    for (let i = 0; i < bins; i++) {
      const lr = meta.cl[i], li = meta.cli[i];
      const rr = meta.cr[i], ri = meta.cri[i];
      const ml = Math.hypot(lr, li), mr = Math.hypot(rr, ri);
      const bal = 1 - Math.abs(ml - mr) / (ml + mr + EPS);        // equal level?
      const dot = (lr * rr + li * ri) / (ml * mr + EPS);          // in phase?
      const coh = Math.max(0, dot);
      centre[i] = Math.pow(Math.max(0, bal) * coh, 1.5);
    }

    // ---- build masks ----
    for (let i = 0; i < bins; i++) {
      const h = harm[i], p = perc[i];
      const hp = h * h + p * p + EPS;
      let mh = (h * h) / hp;   // harmonic share
      let mp = (p * p) / hp;   // percussive share

      const freq = hz(i);
      // bass: low harmonic energy
      const bassW = freq < 180 ? 1 : freq < 320 ? (320 - freq) / 140 : 0;
      // vocal band emphasis
      const vocW = freq < 140 ? 0
                 : freq < 260 ? (freq - 140) / 120
                 : freq < 9000 ? 1
                 : freq < 14000 ? (14000 - freq) / 5000 : 0;

      let mb = mh * bassW;
      let mv = mh * (1 - bassW) * vocW * centre[i];
      let md = mp;
      let mo = Math.max(0, 1 - mb - mv - md);

      const sum = mb + mv + md + mo;
      if (sum > EPS) { mb /= sum; mv /= sum; md /= sum; mo /= sum; }

      // stash per-bin masks in reusable arrays
      harm[i] = mv;   // reuse: vocals
      perc[i] = md;   // reuse: drums
      centre[i] = mb; // reuse: bass
      magM[i] = mo;   // other
    }

    // ---- synthesise each requested stem ----
    const base = emitIdx * HOP - (FRAME >> 1);
    for (const name of wanted) {
      const mask = name === 'vocals' ? harm
                 : name === 'drums'  ? perc
                 : name === 'bass'   ? centre
                 : magM;
      const dst = out[name];

      for (const [src, srci, target] of [
        [meta.cl, meta.cli, dst.l],
        [meta.cr, meta.cri, dst.r],
      ]) {
        // rebuild the full hermitian spectrum
        ore[0] = src[0] * mask[0]; oim[0] = srci[0] * mask[0];
        for (let i = 1; i < bins; i++) {
          const m = mask[i];
          const a = src[i] * m, b = srci[i] * m;
          ore[i] = a; oim[i] = b;
          if (i < FRAME - i) { ore[FRAME - i] = a; oim[FRAME - i] = -b; }
        }
        fft.transform(ore, oim, true);
        const inv = 1 / FRAME;
        for (let i = 0; i < FRAME; i++) {
          const idx = base + i;
          if (idx < 0 || idx >= padded) continue;
          target[idx] += ore[i] * inv * win[i];
        }
      }
    }

    for (let i = 0; i < FRAME; i++) {
      const idx = base + i;
      if (idx >= 0 && idx < padded) wsum[idx] += win[i] * win[i];
    }

    const pct = Math.round((emitIdx / nFrames) * 92) + 4;
    if (pct !== lastPct) { lastPct = pct; onProgress(pct); }
  }

  // ---- normalise overlap-add and trim ----
  const result = {};
  for (const name of wanted) {
    const l = new Float32Array(N), r = new Float32Array(N);
    const sl = out[name].l, sr = out[name].r;
    for (let i = 0; i < N; i++) {
      const w = wsum[i] > 1e-6 ? wsum[i] : 1;
      l[i] = sl[i] / w;
      r[i] = sr[i] / w;
    }
    result[name] = { l, r };
    out[name] = null;
  }
  return result;
}

/* ------------------------------ messaging ------------------------------ */
self.onmessage = e => {
  const { left, right, sampleRate, stems } = e.data;
  try {
    const L = new Float32Array(left);
    const R = new Float32Array(right);

    self.postMessage({ type: 'progress', value: 3, note: 'Analysing spectrum...' });

    const res = separate(L, R, sampleRate, stems, v => {
      self.postMessage({ type: 'progress', value: v, note: 'Separating stems...' });
    });

    self.postMessage({ type: 'progress', value: 97, note: 'Encoding audio...' });

    const payload = {};
    const transfer = [];
    for (const name of Object.keys(res)) {
      const wav = encodeWav(res[name].l, res[name].r, sampleRate);
      payload[name] = {
        wav,
        left: res[name].l.buffer,
        right: res[name].r.buffer,
      };
      transfer.push(wav, res[name].l.buffer, res[name].r.buffer);
    }
    self.postMessage({ type: 'done', stems: payload, sampleRate }, transfer);
  } catch (err) {
    self.postMessage({ type: 'error', message: err && err.message ? err.message : String(err) });
  }
};
