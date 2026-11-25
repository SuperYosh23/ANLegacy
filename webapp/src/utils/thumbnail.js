// Ported URL-resolution helpers from the mobile app's LTYouTubeClient.m.
// Mirrors the mobile behavior exactly:
//   - highResThumbnailURL: i.ytimg.com paths are left alone (sddefault is what
//     list browsing caches and trims cleanly); lh3/ggpht size params are
//     rewritten to a clean 1200x1200 square.
//   - largestThumbnailURLFromArray: picks the widest thumbnail entry.
//   - squareAvatarURL/channelAvatarURL: rewrite yt3/lh3 avatar specs to a
//     square request at the requested size.

function isMissing(val) {
  return typeof val !== 'string' || val.length < 8;
}

export function highResThumbnailURL(urlString) {
  if (isMissing(urlString)) return urlString;
  // i.ytimg.com paths are left alone: sddefault is already disk-cached from
  // list browsing and trims to a clean square, while maxresdefault fetches
  // proved unreliable on device.
  if (urlString.includes('i.ytimg.com')) return urlString;
  let result = urlString;
  const patterns = [
    [/=w\d+-h\d+/g, '=w1200-h1200'],
    [/\/w\d+-h\d+/g, '/w1200-h1200'],
  ];
  for (const [regex, replacement] of patterns) {
    result = result.replace(regex, replacement);
  }
  return result;
}

// Same contract as mobile's getBestThumbnail-era usage but faithful to the
// ported highResThumbnailURL behavior. Kept for call sites that referenced the
// old util.
export function getBestThumbnail(url) {
  return highResThumbnailURL(url);
}

// Picks the highest-resolution thumbnail from a musicThumbnailRenderer array.
export function largestThumbnailURLFromArray(thumbs) {
  if (!Array.isArray(thumbs) || thumbs.length === 0) return null;
  let best = null;
  let bestWidth = -1;
  for (const t of thumbs) {
    if (!t || typeof t !== 'object') continue;
    const url = t.url;
    if (typeof url !== 'string' || !url.length) continue;
    const width = Number(t.width) || 0;
    if (!best || width > bestWidth) {
      best = t;
      bestWidth = width;
    }
  }
  const url = best?.url;
  return (typeof url === 'string' && url.length) ? url : null;
}

// yt3/lh3 services resolve size params against the ORIGINAL uploaded square
// avatar, so rewriting the (possibly landscape-banner) spec to a square
// request yields the artist's actual profile icon.
export function squareAvatarURL(urlString, size = 160) {
  if (typeof urlString !== 'string' || !urlString.length) return urlString;
  const squareSpec = `=w${size}-h${size}-p-l90-rj`;
  const regex = /=w\d+-h\d+[a-z0-9_-]*$/;
  if (regex.test(urlString)) {
    return urlString.replace(regex, squareSpec);
  }
  if (urlString.includes('googleusercontent.com')) {
    return `${urlString}${squareSpec}`;
  }
  return urlString;
}

// Channel-style avatars use =sN specs; rewrite to the requested size.
export function channelAvatarURL(urlString, size = 160) {
  if (typeof urlString !== 'string' || !urlString.length) return urlString;
  const regex = /=s\d+[a-z0-9_-]*(?=\?|$)/;
  if (regex.test(urlString)) {
    return urlString.replace(regex, `=s${size}`);
  }
  return urlString;
}