export const EQ_BAND_COUNT_MIN = 10;
export const EQ_BAND_COUNT_MAX = 20;
export const EQ_GAIN_MIN = -12;
export const EQ_GAIN_MAX = 12;

export const EQ_BANDS_POOL = [
  { freq: 31, type: 'lowshelf', label: '31', unit: 'Hz' },
  { freq: 40, type: 'peaking', label: '40', unit: 'Hz' },
  { freq: 63, type: 'peaking', label: '63', unit: 'Hz' },
  { freq: 80, type: 'peaking', label: '80', unit: 'Hz' },
  { freq: 100, type: 'peaking', label: '100', unit: 'Hz' },
  { freq: 125, type: 'peaking', label: '125', unit: 'Hz' },
  { freq: 160, type: 'peaking', label: '160', unit: 'Hz' },
  { freq: 200, type: 'peaking', label: '200', unit: 'Hz' },
  { freq: 250, type: 'peaking', label: '250', unit: 'Hz' },
  { freq: 315, type: 'peaking', label: '315', unit: 'Hz' },
  { freq: 400, type: 'peaking', label: '400', unit: 'Hz' },
  { freq: 500, type: 'peaking', label: '500', unit: 'Hz' },
  { freq: 630, type: 'peaking', label: '630', unit: 'Hz' },
  { freq: 800, type: 'peaking', label: '800', unit: 'Hz' },
  { freq: 1000, type: 'peaking', label: '1k', unit: 'Hz' },
  { freq: 1600, type: 'peaking', label: '1.6k', unit: 'Hz' },
  { freq: 2000, type: 'peaking', label: '2k', unit: 'Hz' },
  { freq: 4000, type: 'peaking', label: '4k', unit: 'Hz' },
  { freq: 8000, type: 'peaking', label: '8k', unit: 'Hz' },
  { freq: 16000, type: 'highshelf', label: '16k', unit: 'Hz' },
];

export const EQ_DEFAULT_BAND_INDICES = [0, 2, 4, 6, 8, 10, 12, 14, 16, 19];

export const EQ_PRESETS = [
  { name: 'Flat', gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0] },
  { name: 'Rock', gains: [5, 4, 5, 4, 3, 3, 2, 1, 1, 0, -1, -1, -1, 0, 1, 1, 2, 3, 4, 5] },
  { name: 'Pop', gains: [-1, 0, -1, 1, 2, 3, 4, 4, 5, 5, 4, 4, 3, 2, 1, 1, 0, -1, -1, 0] },
  { name: 'Jazz', gains: [4, 4, 4, 3, 3, 3, 3, 2, 2, 2, 2, 2, 1, 1, 2, 2, 2, 3, 3, 3] },
  { name: 'Classical', gains: [5, 5, 5, 4, 4, 4, 3, 3, 2, 2, 2, 2, 2, 3, 3, 3, 4, 4, 5, 5] },
  { name: 'Bass Boost', gains: [7, 7, 7, 6, 6, 5, 4, 3, 2, 1, 0, -1, -1, -1, 0, 0, 1, 1, 2, 3] },
  { name: 'Vocal', gains: [-1, -1, -1, -1, 0, 1, 2, 3, 4, 5, 5, 4, 3, 2, 1, 1, 0, -1, -1, -1] },
  { name: 'Acoustic', gains: [4, 4, 4, 3, 3, 2, 2, 1, 1, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5] },
];

export function getActiveBands(indices, gains) {
  return indices.map((idx, i) => ({
    ...EQ_BANDS_POOL[idx],
    gain: gains[i] ?? 0,
    Q: 0.7,
  }));
}

export function findNextBandIndex(activeIndices) {
  let maxGap = 0;
  let insertAfter = -1;
  for (let i = 0; i < activeIndices.length - 1; i++) {
    const low = activeIndices[i];
    const high = activeIndices[i + 1];
    const gap = EQ_BANDS_POOL[high].freq - EQ_BANDS_POOL[low].freq;
    let hasAvailable = false;
    for (let m = low + 1; m < high; m++) {
      if (!activeIndices.includes(m)) { hasAvailable = true; break; }
    }
    if (hasAvailable && gap > maxGap) {
      maxGap = gap;
      insertAfter = i;
    }
  }
  if (insertAfter === -1) return -1;
  const low = activeIndices[insertAfter];
  const high = activeIndices[insertAfter + 1];
  for (let mid = low + 1; mid < high; mid++) {
    if (!activeIndices.includes(mid)) return mid;
  }
  return -1;
}

function biquadMagnitude(freq, sampleRate, band) {
  const fc = band.freq / sampleRate;
  const pi2fc = 2 * Math.PI * fc;
  const cosW = Math.cos(pi2fc);
  const sinW = Math.sin(pi2fc);
  const A = Math.pow(10, band.gain / 40);
  const Q = band.Q;

  let b0, b1, b2, a0, a1, a2;

  switch (band.type) {
    case 'peaking': {
      const alpha = sinW / (2 * Q);
      b0 = 1 + alpha * A;
      b1 = -2 * cosW;
      b2 = 1 - alpha * A;
      a0 = 1 + alpha / A;
      a1 = -2 * cosW;
      a2 = 1 - alpha / A;
      break;
    }
    case 'lowshelf': {
      const alpha = sinW / 2 * Math.sqrt((A + 1/A) * (1/Q - 1) + 2);
      const twoSqrtA = 2 * Math.sqrt(A) * alpha;
      b0 = A * ((A + 1) - (A - 1) * cosW + twoSqrtA);
      b1 = 2 * A * ((A - 1) - (A + 1) * cosW);
      b2 = A * ((A + 1) - (A - 1) * cosW - twoSqrtA);
      a0 = (A + 1) + (A - 1) * cosW + twoSqrtA;
      a1 = -2 * ((A - 1) + (A + 1) * cosW);
      a2 = (A + 1) + (A - 1) * cosW - twoSqrtA;
      break;
    }
    case 'highshelf': {
      const alpha = sinW / 2 * Math.sqrt((A + 1/A) * (1/Q - 1) + 2);
      const twoSqrtA = 2 * Math.sqrt(A) * alpha;
      b0 = A * ((A + 1) + (A - 1) * cosW + twoSqrtA);
      b1 = -2 * A * ((A - 1) + (A + 1) * cosW);
      b2 = A * ((A + 1) + (A - 1) * cosW - twoSqrtA);
      a0 = (A + 1) - (A - 1) * cosW + twoSqrtA;
      a1 = 2 * ((A - 1) - (A + 1) * cosW);
      a2 = (A + 1) - (A - 1) * cosW - twoSqrtA;
      break;
    }
    default:
      return 1;
  }

  const phi = 2 * Math.PI * freq / sampleRate;
  const reNum = b0 + b1 * Math.cos(phi) + b2 * Math.cos(2 * phi);
  const imNum = b1 * Math.sin(phi) + b2 * Math.sin(2 * phi);
  const reDen = a0 + a1 * Math.cos(phi) + a2 * Math.cos(2 * phi);
  const imDen = a1 * Math.sin(phi) + a2 * Math.sin(2 * phi);
  const magSq = (reNum * reNum + imNum * imNum) / (reDen * reDen + imDen * imDen);
  return Math.sqrt(magSq);
}

export function computeEqCurve(activeBands, numPoints = 128) {
  const sampleRate = 44100;
  const minFreq = 20;
  const maxFreq = 20000;
  const curve = [];

  for (let i = 0; i < numPoints; i++) {
    const t = i / (numPoints - 1);
    const freq = minFreq * Math.pow(maxFreq / minFreq, t);
    let totalDb = 0;
    for (const band of activeBands) {
      if (band.gain === 0) continue;
      totalDb += 20 * Math.log10(biquadMagnitude(freq, sampleRate, band));
    }
    curve.push(totalDb);
  }

  return curve;
}

function buildPoolGains(indices, activeGains) {
  const pool = new Array(EQ_BANDS_POOL.length).fill(0);
  indices.forEach((idx, i) => {
    pool[idx] = activeGains[i] ?? 0;
  });
  return pool;
}

export function createEqEngine(audioElement, indices, activeGains, analyserRef) {
  let audioContext = null;
  let source = null;
  let filters = [];
  let analyser = null;
  let destination = null;
  let contextDestroyed = false;

  function ensureContext() {
    if (contextDestroyed) return null;
    if (!audioContext) {
      audioContext = new AudioContext();
    }
    if (audioContext.state === 'suspended') {
      audioContext.resume();
    }
    return audioContext;
  }

  function connect() {
    if (!audioElement || source) return;
    const ctx = ensureContext();
    if (!ctx) return;

    try {
      source = ctx.createMediaElementSource(audioElement);
      destination = ctx.destination;

      const poolGains = buildPoolGains(indices, activeGains);

      let lastNode = source;
      filters = EQ_BANDS_POOL.map((band, i) => {
        const filter = ctx.createBiquadFilter();
        filter.type = band.type;
        filter.frequency.value = band.freq;
        filter.Q.value = 0.7;
        filter.gain.value = poolGains[i];
        lastNode.connect(filter);
        lastNode = filter;
        return filter;
      });

      analyser = ctx.createAnalyser();
      analyser.fftSize = 256;
      lastNode.connect(analyser);
      analyser.connect(destination);

      if (analyserRef) analyserRef.current = analyser;
    } catch (err) {
      console.error('[EQ] connect failed:', err);
    }
  }

  function setGain(poolIndex, value) {
    if (filters[poolIndex]) {
      filters[poolIndex].gain.value = value;
    }
  }

  function setGainsFromActive(activeIndices, activeGainsArr) {
    const poolGains = buildPoolGains(activeIndices, activeGainsArr);
    poolGains.forEach((v, i) => {
      if (filters[i]) filters[i].gain.value = v;
    });
  }

  function setEnabled(enabled, activeIndices, activeGainsArr) {
    if (filters.length === 0) return;
    if (!enabled) {
      filters.forEach(f => { f.gain.value = 0; });
    } else if (activeIndices && activeGainsArr) {
      setGainsFromActive(activeIndices, activeGainsArr);
    }
  }

  function destroy() {
    contextDestroyed = true;
    if (analyserRef) analyserRef.current = null;
    if (source) {
      try { source.disconnect(); } catch {}; source = null;
    }
    filters.forEach(f => { try { f.disconnect(); } catch {}; });
    filters = [];
    if (analyser) { try { analyser.disconnect(); } catch {}; analyser = null; }
    if (audioContext) {
      audioContext.close();
      audioContext = null;
    }
    destination = null;
  }

  return { connect, setGain, setGainsFromActive, setEnabled, destroy };
}
