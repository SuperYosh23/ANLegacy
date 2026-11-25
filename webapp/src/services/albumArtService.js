// Album art service ported from the mobile app (LTYouTubeClient.m image
// pipeline, LTGraphics.m blur, and LTPlaylistStore.m artist avatars).
//
// The mobile app persists artwork to a disk directory (art/<md5>.jpg). The web
// equivalent used here is an IndexedDB object store keyed by the md5 hex of the
// resolved URL. Images are decoded, trimmed of letterbox/pillarbox borders,
// and re-encoded to JPEG 0.85 before caching, matching the mobile pipeline.

import { highResThumbnailURL, squareAvatarURL, largestThumbnailURLFromArray } from '../utils/thumbnail';

const memoryCache = new Map();
const pending = new Map();

let dbPromise = null;
function openArtDB() {
  if (dbPromise) return dbPromise;
  dbPromise = new Promise((resolve, reject) => {
    if (!('indexedDB' in window)) { reject(new Error('indexedDB unavailable')); return; }
    const req = indexedDB.open('audioninja-art', 1);
    req.onupgradeneeded = () => { req.result.createObjectStore('files'); };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error || new Error('art db open failed'));
  });
  return dbPromise;
}

async function dbPut(key, blob) {
  try {
    const db = await openArtDB();
    return new Promise((resolve, reject) => {
      const tx = db.transaction('files', 'readwrite');
      tx.objectStore('files').put(blob, key);
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error || new Error('art db put failed'));
    });
  } catch {
    // DB unavailable: fall through silently, memory cache still helps.
  }
}

async function dbGet(key) {
  try {
    const db = await openArtDB();
    return new Promise((resolve, reject) => {
      const tx = db.transaction('files', 'readonly');
      const req = tx.objectStore('files').get(key);
      req.onsuccess = () => resolve(req.result || null);
      req.onerror = () => reject(req.error || new Error('art db get failed'));
    });
  } catch {
    return null;
  }
}

async function dbDelete(key) {
  try {
    const db = await openArtDB();
    return new Promise((resolve, reject) => {
      const tx = db.transaction('files', 'readwrite');
      tx.objectStore('files').delete(key);
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error || new Error('art db delete failed'));
    });
  } catch {
    // ignore
  }
}

// Cache key generator. The mobile app uses MD5 hex (CC_MD5); WebCrypto only
// exposes SHA-1/SHA-256, so SHA-256 is used here. The exact digest is not part
// of any sync contract; it only needs to be stable and collision-safe for a
// given URL/identifier within the app.
async function cacheKeyHex(string) {
  if (typeof crypto?.subtle?.digest === 'function') {
    const data = new TextEncoder().encode(string);
    const digest = await crypto.subtle.digest('SHA-256', data);
    return Array.from(new Uint8Array(digest)).map(b => b.toString(16).padStart(2, '0')).join('');
  }
  let h = 5381;
  for (let i = 0; i < string.length; i++) {
    h = ((h << 5) + h + string.charCodeAt(i)) >>> 0;
  }
  return `h${h.toString(16)}`;
}

// ---------------------------------------------------------------------------
// Border-scan artwork trim, ported from LTTrimmedArtworkImage.
//
// Some YouTube Topic auto-gen covers are letterboxed/pillarboxed (uniform
// bars of one or two colors). This scans each border row/column for uniformity
// against the current corner, peeling bars stage by stage, then for i.ytimg
// thumbs does a final centered crop of the long edge into a clean square.
// ---------------------------------------------------------------------------

function withinTolerance(a, b) {
  return Math.abs(a[0] - b[0]) <= 18 && Math.abs(a[1] - b[1]) <= 18 && Math.abs(a[2] - b[2]) <= 18;
}

function rowUniform(data, W, y, x0, x1, ref) {
  const stride = W * 4;
  let offset = y * stride + x0 * 4;
  for (let x = x0; x < x1; x++) {
    if (!withinTolerance([data[offset], data[offset + 1], data[offset + 2]], ref)) return false;
    offset += 4;
  }
  return true;
}

function colUniform(data, W, x, y0, y1, ref) {
  const stride = W * 4;
  for (let y = y0; y < y1; y++) {
    const offset = y * stride + x * 4;
    if (!withinTolerance([data[offset], data[offset + 1], data[offset + 2]], ref)) return false;
  }
  return true;
}

// Resolves to the trimmed square artwork as a JPEG 0.85 data URL, or null.
async function trimArtwork(source, allowCenterCrop) {
  try {
    const img = await loadImageElement(source);
    const W = img.naturalWidth;
    const H = img.naturalHeight;
    if (W < 64 || H < 64) return null;

    const canvas = document.createElement('canvas');
    canvas.width = W;
    canvas.height = H;
    const ctx = canvas.getContext('2d', { willReadFrequently: true });
    ctx.drawImage(img, 0, 0);

    let pixel;
    try {
      pixel = ctx.getImageData(0, 0, W, H).data;
    } catch {
      // Cross-origin taint: fall back to raw encode without trimming.
      return encodeCanvas(canvas);
    }

    let top = 0, bottom = H, left = 0, right = W;
    for (let pass = 0; pass < 4; pass++) {
      const refOff = (top * W + left) * 4;
      const ref = [pixel[refOff], pixel[refOff + 1], pixel[refOff + 2]];
      const ot = top, ob = bottom, ol = left, orr = right;
      while (top < bottom - 1 && rowUniform(pixel, W, top, left, right, ref)) top++;
      while (bottom > top + 1 && rowUniform(pixel, W, bottom - 1, left, right, ref)) bottom--;
      while (left < right - 1 && colUniform(pixel, W, left, top, bottom, ref)) left++;
      while (right > left + 1 && colUniform(pixel, W, right - 1, top, bottom, ref)) right--;
      if (top === ot && bottom === ob && left === ol && right === orr) break;
      let cw = right - left, ch = bottom - top;
      if (cw < 32 || ch < 32 || cw * 2 < W || ch * 2 < H) {
        top = ot; bottom = ob; left = ol; right = orr;
        break;
      }
    }

    let cw = right - left;
    let ch = bottom - top;
    if (cw >= W && ch >= H) {
      return encodeCanvas(canvas);
    }
    if (allowCenterCrop && cw !== ch) {
      if (cw > ch) { left += Math.floor((cw - ch) / 2); cw = ch; }
      else { top += Math.floor((ch - cw) / 2); ch = cw; }
    }

    const crop = document.createElement('canvas');
    crop.width = cw;
    crop.height = ch;
    const cropCtx = crop.getContext('2d');
    cropCtx.drawImage(canvas, left, top, cw, ch, 0, 0, cw, ch);
    return encodeCanvas(crop);
  } catch {
    return null;
  }
}

function loadImageElement(src) {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.crossOrigin = 'anonymous';
    img.onload = () => resolve(img);
    img.onerror = () => reject(new Error('image decode failed'));
    img.src = src;
  });
}

function encodeCanvas(canvas) {
  try {
    return canvas.toDataURL('image/jpeg', 0.85);
  } catch {
    return null;
  }
}

function isYtimg(url) {
  return typeof url === 'string' && url.includes('i.ytimg.com');
}

// Port of mobile loadImageWithURL: memory cache -> disk(IndexedDB) cache ->
// network fetch, with maxresdefault fallback to sddefault and a usable-size
// guard. Resolves to a JPEG data URL (trimmed square for artwork URLs).
export async function loadArtwork(urlString) {
  if (!urlString || typeof urlString !== 'string') return null;
  const resolved = highResThumbnailURL(urlString);
  const cacheKey = `${resolved}`;
  if (memoryCache.has(cacheKey)) return memoryCache.get(cacheKey);
  if (pending.has(cacheKey)) return pending.get(cacheKey);

  const promise = (async () => {
    const hex = await cacheKeyHex(resolved);
    const diskKey = `${hex}.jpg`;
    const cached = await dbGet(diskKey);
    if (cached) {
      const dataUrl = blobToDataUrl(cached);
      memoryCache.set(cacheKey, dataUrl);
      return dataUrl;
    }

    const maxresFallback = resolved.endsWith('maxresdefault.jpg')
      ? resolved.replace('maxresdefault.jpg', 'sddefault.jpg')
      : null;

    let blob = await fetchBlob(resolved);
    if (!blob && maxresFallback) blob = await fetchBlob(maxresFallback);
    if (!blob) return null;

    const objectUrl = URL.createObjectURL(blob);
    const usable = await imageUsable(resolved, objectUrl);
    URL.revokeObjectURL(objectUrl);
    if (!usable) {
      if (maxresFallback) {
        const fbBlob = await fetchBlob(maxresFallback);
        if (!fbBlob) return null;
        const fbUrl = URL.createObjectURL(fbBlob);
        const fbUsable = await imageUsable(maxresFallback, fbUrl);
        URL.revokeObjectURL(fbUrl);
        if (!fbUsable) return null;
        blob = fbBlob;
      } else {
        return null;
      }
    }

    const dataUrl = await trimArtwork(blobToObjectUrl(blob), isYtimg(resolved));
    if (!dataUrl) return null;

    // Persist the trimmed JPEG to the art store (mobile writes art/<md5>.jpg).
    await persistDataUrl(diskKey, dataUrl);
    memoryCache.set(cacheKey, dataUrl);
    return dataUrl;
  })();

  pending.set(cacheKey, promise);
  try {
    return await promise;
  } finally {
    pending.delete(cacheKey);
  }
}

async function imageUsable(cacheKey, src) {
  try {
    const img = await loadImageElement(src);
    const isMaxres = cacheKey.includes('maxresdefault');
    return !isMaxres || img.naturalWidth >= 200;
  } catch {
    return false;
  }
}

async function fetchBlob(url) {
  try {
    const res = await fetch(url, { cache: 'force-cache' });
    if (!res.ok) return null;
    const blob = await res.blob();
    if (!blob || !blob.size) return null;
    return blob;
  } catch {
    return null;
  }
}

function blobToDataUrl(blob) {
  return new Promise((resolve) => {
    const reader = new FileReader();
    reader.onload = () => resolve(typeof reader.result === 'string' ? reader.result : null);
    reader.onerror = () => resolve(null);
    reader.readAsDataURL(blob);
  });
}

function blobToObjectUrl(blob) {
  if (URL.createObjectURL) return URL.createObjectURL(blob);
  return blobToDataUrl(blob);
}

async function persistDataUrl(diskKey, dataUrl) {
  const parts = dataUrl.split(',');
  if (!parts[1]) return;
  const mime = /^data:([^;]+);/.exec(dataUrl);
  const byteString = atob(parts[1]);
  const bytes = new Uint8Array(byteString.length);
  for (let i = 0; i < byteString.length; i++) bytes[i] = byteString.charCodeAt(i);
  const blob = new Blob([bytes], { type: mime ? mime[1] : 'image/jpeg' });
  await dbPut(diskKey, blob);
}

// ---------------------------------------------------------------------------
// Blurred background, ported from LTGraphics.blurredImageFromImage.
//
// Downscales to <= 100px, applies a 3-pass box blur (radius = max(3, 15% of
// the smaller dimension)), and returns a small JPEG data URL.
// ---------------------------------------------------------------------------

export async function blurredImageFromImage(dataUrl) {
  if (!dataUrl) return null;
  try {
    const img = await loadImageElement(dataUrl);
    const srcW = img.naturalWidth;
    const srcH = img.naturalHeight;
    if (srcW < 2 || srcH < 2) return null;

    const maxDim = 100;
    const ratio = Math.min(1, maxDim / Math.max(srcW, srcH));
    const w = Math.max(2, Math.round(srcW * ratio));
    const h = Math.max(2, Math.round(srcH * ratio));

    const canvas = document.createElement('canvas');
    canvas.width = w;
    canvas.height = h;
    const ctx = canvas.getContext('2d', { willReadFrequently: true });
    ctx.drawImage(img, 0, 0, w, h);

    const pixel = ctx.getImageData(0, 0, w, h).data;
    const data = new Uint8ClampedArray(pixel);
    const tmp = new Uint8ClampedArray(w * h * 4);
    const radius = Math.max(3, Math.round(Math.min(w, h) * 0.15));
    const passes = 3;

    for (let p = 0; p < passes; p++) {
      // Horizontal pass.
      for (let y = 0; y < h; y++) {
        for (let x = 0; x < w; x++) {
          let sR = 0, sG = 0, sB = 0, sA = 0, cnt = 0;
          for (let d = -radius; d <= radius; d++) {
            const sx = x + d;
            if (sx < 0 || sx >= w) continue;
            const i = (y * w + sx) * 4;
            sR += data[i]; sG += data[i + 1]; sB += data[i + 2]; sA += data[i + 3];
            cnt++;
          }
          const i = (y * w + x) * 4;
          tmp[i] = sR / cnt; tmp[i + 1] = sG / cnt; tmp[i + 2] = sB / cnt; tmp[i + 3] = sA / cnt;
        }
      }
      // Vertical pass.
      for (let y = 0; y < h; y++) {
        for (let x = 0; x < w; x++) {
          let sR = 0, sG = 0, sB = 0, sA = 0, cnt = 0;
          for (let d = -radius; d <= radius; d++) {
            const sy = y + d;
            if (sy < 0 || sy >= h) continue;
            const i = (sy * w + x) * 4;
            sR += tmp[i]; sG += tmp[i + 1]; sB += tmp[i + 2]; sA += tmp[i + 3];
            cnt++;
          }
          const i = (y * w + x) * 4;
          data[i] = sR / cnt; data[i + 1] = sG / cnt; data[i + 2] = sB / cnt; data[i + 3] = sA / cnt;
        }
      }
    }

    ctx.putImageData(new ImageData(data, w, h), 0, 0);
    return canvas.toDataURL('image/jpeg', 0.85);
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Art store conveniences (covers + avatars), mirroring the mobile art
// directory and artistAvatars.plist.
// ---------------------------------------------------------------------------

// Cover art lives at art/cover-<identifier>.jpg on mobile; here it is keyed in
// IndexedDB by that same filename.
function coverKey(identifier) {
  return `cover-${identifier}.jpg`;
}

export async function saveCoverForPlaylist(identifier, dataUrl) {
  await persistDataUrl(coverKey(identifier), dataUrl);
  return coverKey(identifier);
}

export async function loadCoverForPlaylist(identifier) {
  return dbGet(coverKey(identifier));
}

export async function deleteCoverForPlaylist(identifier) {
  await dbDelete(coverKey(identifier));
}

// Mobile stores the resolved cover file path in coverPath. Desktop keeps the
// same field name; the path is the IndexedDB key (our art directory analog).
export function coverPathFor(identifier) {
  return coverKey(identifier);
}

// Re-encodes a picked image (FileReader data URL) into a square JPEG 0.85,
// matching the mobile setCoverImage (UIImageJPEGRepresentation 0.85). Any image
// source the <canvas> can decode works.
export async function reencodeCover(dataUrl) {
  if (!dataUrl) return null;
  try {
    const img = await loadImageElement(dataUrl);
    const size = Math.min(img.naturalWidth, img.naturalHeight) || img.naturalWidth || img.naturalHeight;
    if (!size) return null;
    const canvas = document.createElement('canvas');
    canvas.width = size;
    canvas.height = size;
    const ctx = canvas.getContext('2d');
    const sx = Math.floor((img.naturalWidth - size) / 2);
    const sy = Math.floor((img.naturalHeight - size) / 2);
    ctx.drawImage(img, sx, sy, size, size, 0, 0, size, size);
    return canvas.toDataURL('image/jpeg', 0.85);
  } catch {
    return dataUrl;
  }
}

// Artist avatars are stored as a name -> URL map (artistAvatars.plist on
// mobile). Kept in localStorage mirroring the plist format.
const ARTIST_AVATARS_KEY = 'ym_artist_avatars';

export const artistAvatars = {
  getMap() {
    try {
      const data = localStorage.getItem(ARTIST_AVATARS_KEY);
      return data ? JSON.parse(data) : {};
    } catch {
      return {};
    }
  },

  keyForName(name) {
    return (name || '').trim().toLowerCase();
  },

  urlForName(name) {
    return this.getMap()[this.keyForName(name)] || null;
  },

  setURL(url, name) {
    const key = this.keyForName(name);
    if (!key.length || !url) return;
    const map = this.getMap();
    map[key] = url;
    localStorage.setItem(ARTIST_AVATARS_KEY, JSON.stringify(map));
  },
};

const pendingNameAvatars = new Map();

// Port of mobile resolveArtistAvatarForName: search for the artist, pick the
// matching artist browse item, resolve its avatar to a clean 160px square, and
// persist it so later lookups hit the store. Multiple concurrent callers for
// the same name share one network request.
export async function resolveArtistAvatarForName(name) {
  const key = artistAvatars.keyForName(name);
  if (!key) return null;
  const cached = artistAvatars.urlForName(name);
  if (cached) return cached;
  if (pendingNameAvatars.has(key)) return pendingNameAvatars.get(key);

  const pending = (async () => {
    try {
      const API_BASE = globalThis.electronAPI?.backendUrl || '/api';
      const res = await fetch(`${API_BASE}/search/artists?q=${encodeURIComponent(name)}&limit=10`);
      if (!res.ok) throw new Error(`API ${res.status}`);
      const data = await res.json();
      let url = null;
      for (const item of data.results || []) {
        if (!item || typeof item !== 'object') continue;
        const title = item.artist || item.title || item.name || '';
        if (title.toLowerCase() !== key) continue;
        try {
          url = largestThumbnailURLFromArray(item.thumbnails || []);
        } catch { /* keep trying */ }
        if (url) break;
      }
      if (url) {
        const square = squareAvatarURL(url, 160);
        artistAvatars.setURL(square, name);
        return square;
      }
      return null;
    } catch {
      return null;
    }
  })();

  pendingNameAvatars.set(key, pending);
  try {
    return await pending;
  } finally {
    pendingNameAvatars.delete(key);
  }
}