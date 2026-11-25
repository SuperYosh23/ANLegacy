export function hexToHsl(hex) {
  let r = 0, g = 0, b = 0;
  if (hex.length === 4) {
    r = parseInt(hex[1] + hex[1], 16);
    g = parseInt(hex[2] + hex[2], 16);
    b = parseInt(hex[3] + hex[3], 16);
  } else if (hex.length === 7) {
    r = parseInt(hex.slice(1, 3), 16);
    g = parseInt(hex.slice(3, 5), 16);
    b = parseInt(hex.slice(5, 7), 16);
  }
  r /= 255; g /= 255; b /= 255;
  const max = Math.max(r, g, b), min = Math.min(r, g, b);
  let h = 0, s, l = (max + min) / 2;
  if (max !== min) {
    const d = max - min;
    s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    switch (max) {
      case r: h = ((g - b) / d + (g < b ? 6 : 0)) / 6; break;
      case g: h = ((b - r) / d + 2) / 6; break;
      case b: h = ((r - g) / d + 4) / 6; break;
    }
  } else {
    s = 0;
  }
  return { h: h * 360, s: s * 100, l: l * 100 };
}

export function hslToHex(h, s, l) {
  s /= 100; l /= 100;
  const k = n => (n + h / 30) % 12;
  const a = s * Math.min(l, 1 - l);
  const f = n => l - a * Math.max(-1, Math.min(k(n) - 3, 9 - k(n), 1));
  return '#' + [f(0), f(8), f(4)].map(v => Math.round(v * 255).toString(16).padStart(2, '0')).join('');
}

export function extractColorsFromImage(file) {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => {
      const canvas = document.createElement('canvas');
      const ctx = canvas.getContext('2d');
      const size = 64;
      canvas.width = size;
      canvas.height = size;
      ctx.drawImage(img, 0, 0, size, size);
      const data = ctx.getImageData(0, 0, size, size).data;

      const colorMap = {};
      for (let i = 0; i < data.length; i += 8) {
        const r = Math.round(data[i] / 32) * 32;
        const g = Math.round(data[i + 1] / 32) * 32;
        const b = Math.round(data[i + 2] / 32) * 32;
        const key = `${r},${g},${b}`;
        colorMap[key] = (colorMap[key] || 0) + 1;
      }

      const sorted = Object.entries(colorMap)
        .sort((a, b) => b[1] - a[1])
        .slice(0, 5)
        .map(([key]) => {
          const [r, g, b] = key.split(',').map(Number);
          return '#' + [r, g, b].map(v => v.toString(16).padStart(2, '0')).join('');
        });

      URL.revokeObjectURL(img.src);
      resolve(sorted);
    };
    img.onerror = () => { URL.revokeObjectURL(img.src); reject(new Error('Failed to load image')); };
    img.src = URL.createObjectURL(file);
  });
}

function tone(hue, sat, lightness) {
  return hslToHex(hue, Math.max(sat, 8), lightness);
}

export function generatePaletteFromSource(sourceHex) {
  const { h, s } = hexToHsl(sourceHex);
  const sat = Math.max(s, 25);

  const dark = {
    primary: tone(h, sat, 80),
    'on-primary': tone(h, sat, 20),
    'primary-container': tone(h, sat, 30),
    'on-primary-container': tone(h, sat, 90),
    secondary: tone(h + 30, Math.max(sat - 20, 12), 75),
    'on-secondary': tone(h + 30, Math.max(sat - 20, 12), 20),
    'secondary-container': tone(h + 30, Math.max(sat - 20, 12), 30),
    'on-secondary-container': tone(h + 30, Math.max(sat - 20, 12), 90),
    tertiary: tone(h + 60, Math.max(sat - 15, 8), 75),
    'on-tertiary': tone(h + 60, Math.max(sat - 15, 8), 20),
    'tertiary-container': tone(h + 60, Math.max(sat - 15, 8), 30),
    'on-tertiary-container': tone(h + 60, Math.max(sat - 15, 8), 90),
    error: '#FFB4AB',
    'on-error': '#690005',
    'error-container': '#93000A',
    'on-error-container': '#FFDAD6',
    'surface-dim': tone(h, 5, 7),
    surface: tone(h, 5, 8),
    'surface-bright': tone(h, 5, 22),
    'surface-container-lowest': tone(h, 5, 5),
    'surface-container-low': tone(h, 5, 12),
    'surface-container': tone(h, 5, 14),
    'surface-container-high': tone(h, 5, 18),
    'surface-container-highest': tone(h, 5, 22),
    'on-surface': tone(h, 5, 90),
    'on-surface-variant': tone(h, 5, 78),
    outline: tone(h, 5, 58),
    'outline-variant': tone(h, 5, 28),
    scrim: '#000000',
  };

  const light = {
    primary: tone(h, sat, 40),
    'on-primary': tone(h, sat, 100),
    'primary-container': tone(h, sat, 90),
    'on-primary-container': tone(h, sat, 10),
    secondary: tone(h + 30, Math.max(sat - 20, 12), 40),
    'on-secondary': tone(h + 30, Math.max(sat - 20, 12), 100),
    'secondary-container': tone(h + 30, Math.max(sat - 20, 12), 90),
    'on-secondary-container': tone(h + 30, Math.max(sat - 20, 12), 10),
    tertiary: tone(h + 60, Math.max(sat - 15, 8), 40),
    'on-tertiary': tone(h + 60, Math.max(sat - 15, 8), 100),
    'tertiary-container': tone(h + 60, Math.max(sat - 15, 8), 90),
    'on-tertiary-container': tone(h + 60, Math.max(sat - 15, 8), 10),
    error: '#BA1A1A',
    'on-error': '#FFFFFF',
    'error-container': '#FFDAD6',
    'on-error-container': '#410002',
    'surface-dim': tone(h, 5, 87),
    surface: tone(h, 5, 99),
    'surface-bright': tone(h, 5, 100),
    'surface-container-lowest': tone(h, 5, 100),
    'surface-container-low': tone(h, 5, 94),
    'surface-container': tone(h, 5, 92),
    'surface-container-high': tone(h, 5, 88),
    'surface-container-highest': tone(h, 5, 84),
    'on-surface': tone(h, 5, 11),
    'on-surface-variant': tone(h, 5, 28),
    outline: tone(h, 5, 47),
    'outline-variant': tone(h, 5, 78),
    scrim: '#000000',
  };

  return { dark, light };
}

const THEME_KEYS = [
  'primary', 'on-primary', 'primary-container', 'on-primary-container',
  'secondary', 'on-secondary', 'secondary-container', 'on-secondary-container',
  'tertiary', 'on-tertiary', 'tertiary-container', 'on-tertiary-container',
  'error', 'on-error', 'error-container', 'on-error-container',
  'surface-dim', 'surface', 'surface-bright',
  'surface-container-lowest', 'surface-container-low',
  'surface-container', 'surface-container-high', 'surface-container-highest',
  'on-surface', 'on-surface-variant', 'outline', 'outline-variant', 'scrim',
];

export function clearThemeVars(root) {
  THEME_KEYS.forEach(key => root.style.removeProperty(`--color-${key}`));
}

function readOledPref() {
  try {
    const prefs = JSON.parse(localStorage.getItem('ym_preferences') || '{}');
    return !!prefs.oledBackground;
  } catch {
    return false;
  }
}

// When enabled (and not in light mode), the app background is forced to pure
// black for OLED panels. This only toggles the data-oled attribute; the actual
// color override lives in index.css as a `!important` rule so it beats an
// active custom theme's inline styles without touching button/container colors.
export function applyOledMode() {
  const root = document.documentElement;
  const oledEnabled = readOledPref();
  const isLight = root.dataset.theme === 'light';
  root.dataset.oled = oledEnabled && !isLight ? 'true' : 'false';
}

export function applyTheme(themeColors) {
  localStorage.setItem('ym_custom_theme', JSON.stringify(themeColors));
  applyCurrentTheme(themeColors);
}

export function applyCurrentTheme(themeColors) {
  const root = document.documentElement;
  clearThemeVars(root);
  const isLight = root.dataset.theme === 'light';
  const palette = isLight ? themeColors.light : themeColors.dark;
  Object.entries(palette).forEach(([key, value]) => {
    root.style.setProperty(`--color-${key}`, value);
  });
  applyOledMode();
}

export function loadTheme() {
  try {
    const data = localStorage.getItem('ym_custom_theme');
    return data ? JSON.parse(data) : null;
  } catch {
    return null;
  }
}

export function resetTheme() {
  localStorage.removeItem('ym_custom_theme');
  clearThemeVars(document.documentElement);
}
