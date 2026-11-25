import { highResThumbnailURL } from '../utils/thumbnail';

const API_BASE = globalThis.electronAPI?.backendUrl || '/api'

const lyricsCache = new Map()
const pendingLyrics = new Map()

async function fetchJson(url) {
  const res = await fetch(url)
  if (!res.ok) throw new Error(`API ${res.status}`)
  return res.json()
}

async function doCheckLyrics(videoId) {
  if (pendingLyrics.has(videoId)) return pendingLyrics.get(videoId)
  const promise = (async () => {
    try {
      const data = await fetchJson(`${API_BASE}/lyrics/check/${videoId}`)
      const available = data.available ?? false
      lyricsCache.set(videoId, available)
      pendingLyrics.delete(videoId)
      return available
    } catch {
      lyricsCache.set(videoId, false)
      pendingLyrics.delete(videoId)
      return false
    }
  })()
  pendingLyrics.set(videoId, promise)
  return promise
}

function getBestThumbnail(url) {
  return highResThumbnailURL(url)
}

function thumb(thumbnails) {
  if (!thumbnails || !thumbnails.length) return null
  return getBestThumbnail(thumbnails[thumbnails.length - 1].url)
}

function parseDuration(text) {
  if (!text) return 0
  const t = text.trim()
  const parts = t.split(':').map(Number)
  if (parts.length === 2 && !isNaN(parts[0]) && !isNaN(parts[1])) return parts[0] * 60 + parts[1]
  if (parts.length === 3 && !isNaN(parts[0]) && !isNaN(parts[1]) && !isNaN(parts[2])) return parts[0] * 3600 + parts[1] * 60 + parts[2]
  return 0
}

function artistNames(artists) {
  if (!artists || !artists.length) return ''
  return artists.map(a => a.name).join(', ')
}

function songId(artists) {
  if (!artists || !artists.length) return ''
  return artists[0].id || ''
}

function toSong(item) {
  return {
    videoId: item.videoId || '',
    title: item.title || '',
    artists: (item.artists || []).map(a => ({ name: a.name, artistId: a.id || '' })),
    channelTitle: artistNames(item.artists),
    channelId: songId(item.artists),
    thumbnail: thumb(item.thumbnails),
    duration: item.duration_seconds || 0,
    album: item.album?.name || '',
    albumId: item.album?.id || '',
  }
}

function toAlbum(item) {
  const artistName = item.artists?.map?.(a => a.name).join(', ') || ''
  return {
    type: 'album',
    browseId: item.browseId || '',
    playlistId: item.browseId || '',
    title: item.title || '',
    artist: artistName,
    channelTitle: artistName,
    channelId: songId(item.artists),
    thumbnail: thumb(item.thumbnails),
    videoCount: item.itemCount || item.trackCount || 0,
    year: item.year ? String(item.year) : '',
  }
}

export const apiService = {
  async searchSongs(query, limit = 20, filterExplicit = false) {
    const params = new URLSearchParams({ q: query, limit: String(limit) })
    if (filterExplicit) params.set('filter_explicit', 'true')
    const data = await fetchJson(`${API_BASE}/search/songs?${params}`)
    return (data.results || []).map(toSong)
  },

  async searchAll(query, filterExplicit = false) {
    const songParams = new URLSearchParams({ q: query, limit: '20' })
    if (filterExplicit) songParams.set('filter_explicit', 'true')
    const [songData, albumData] = await Promise.all([
      fetchJson(`${API_BASE}/search/songs?${songParams}`),
      fetchJson(`${API_BASE}/search/albums?q=${encodeURIComponent(query)}&limit=10`),
    ])
    return {
      songs: (songData.results || []).map(toSong),
      albums: (albumData.results || []).map(toAlbum),
    }
  },

  async searchAlbums(query, limit = 10) {
    const data = await fetchJson(`${API_BASE}/search/albums?q=${encodeURIComponent(query)}&limit=${limit}`)
    return (data.results || []).map(toAlbum)
  },

  async getRecommendations(seeds, filterExplicit = false) {
    const res = await fetch(`${API_BASE}/recommendations`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ seeds, filter_explicit: filterExplicit }),
    })
    if (!res.ok) throw new Error(`API ${res.status}`)
    const data = await res.json()
    return (data.tracks || []).map(t => ({
      videoId: t.videoId || '',
      title: t.title || '',
      artists: (t.artists || []).map(a => ({ name: a.name, artistId: a.id || '' })),
      channelTitle: (t.artists || []).map(a => a.name).join(', '),
      channelId: t.artists?.[0]?.id || '',
      thumbnail: thumb(t.thumbnail),
      duration: parseDuration(t.length),
      album: t.album?.name || '',
      albumId: t.album?.id || '',
      _seed: t._seed || '',
    }))
  },

  async getAlbum(browseId) {
    const data = await fetchJson(`${API_BASE}/album/${browseId}`)
    return {
      title: data.title || '',
      artist: data.artists?.[0]?.name || '',
      artistId: data.artists?.[0]?.id || '',
      year: data.year || '',
      thumbnail: thumb(data.thumbnails),
      tracks: (data.tracks || []).map(t => ({
        videoId: t.videoId || '',
        title: t.title || '',
        artists: (t.artists || []).map(a => ({ name: a.name, artistId: a.id || '' })),
        channelTitle: artistNames(t.artists),
        channelId: songId(t.artists),
        thumbnail: thumb(t.thumbnails),
        duration: t.duration_seconds || 0,
        album: data.title || '',
      })),
    }
  },

  async getPlaylist(playlistId) {
    const data = await fetchJson(`${API_BASE}/playlist/${playlistId}`)
    return {
      title: data.title || '',
      owner: data.owner?.name || '',
      thumbnail: thumb(data.thumbnails),
      trackCount: data.trackCount || 0,
      tracks: (data.tracks || []).map(t => ({
        videoId: t.videoId || '',
        title: t.title || '',
        artists: (t.artists || []).map(a => ({ name: a.name, artistId: a.id || '' })),
        channelTitle: artistNames(t.artists),
        channelId: songId(t.artists),
        thumbnail: thumb(t.thumbnails),
        duration: t.duration_seconds || 0,
      })),
    }
  },

  async getSong(videoId) {
    const data = await fetchJson(`${API_BASE}/song/${videoId}`)
    const vd = data.videoDetails || {}
    return {
      videoId: vd.videoId || videoId,
      title: vd.title || '',
      artists: [{ name: vd.author || '', artistId: vd.channelId || '' }],
      channelTitle: vd.author || '',
      channelId: vd.channelId || '',
      thumbnail: vd.thumbnail?.thumbnails?.[vd.thumbnail.thumbnails.length - 1]?.url || '',
      duration: parseInt(vd.lengthSeconds) || 0,
      description: vd.shortDescription || '',
    }
  },

  async checkLyrics(videoId) {
    if (lyricsCache.has(videoId)) return lyricsCache.get(videoId)
    return doCheckLyrics(videoId)
  },

  async getLyrics(videoId) {
    const data = await fetchJson(`${API_BASE}/lyrics/${videoId}`)
    return data
  },

  async getAudioUrl(videoId) {
    return fetchJson(`${API_BASE}/audio/${videoId}`)
  },

  prefetchLyrics(videoIds) {
    for (const id of videoIds) {
      if (!id || lyricsCache.has(id)) continue
      doCheckLyrics(id)
    }
  },

  async getAiRecommendations(apiKey, history, filters = {}) {
    const res = await fetch(`${API_BASE}/ai/recommendations`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        api_key: apiKey,
        history,
        type: 'recommendations',
        filter_explicit: filters.filterExplicit || false,
      }),
    })
    if (!res.ok) {
      const err = await res.json().catch(() => ({}))
      throw new Error(err.error || `API ${res.status}`)
    }
    const data = await res.json()
    return (data.recommendations || []).map(t => ({
      videoId: t.videoId || '',
      title: t.title || '',
      artists: (t.artists || []).map(a => ({ name: a.name, artistId: a.id || '' })),
      channelTitle: (t.artists || []).map(a => a.name).join(', '),
      channelId: t.artists?.[0]?.id || '',
      thumbnail: getBestThumbnail(t.thumbnail),
      duration: t.duration || 0,
      album: t.album || '',
      albumId: t.albumId || '',
      _aiTitle: t._ai_title || '',
      _aiArtist: t._ai_artist || '',
    }))
  },

  async getAiPlaylists(apiKey, history, filters = {}) {
    const res = await fetch(`${API_BASE}/ai/recommendations`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        api_key: apiKey,
        history,
        type: 'playlists',
        filter_explicit: filters.filterExplicit || false,
      }),
    })
    if (!res.ok) {
      const err = await res.json().catch(() => ({}))
      throw new Error(err.error || `API ${res.status}`)
    }
    const data = await res.json()
    return (data.playlists || []).map(p => ({
      name: p.name || '',
      description: p.description || '',
      songs: (p.songs || []).map(t => ({
        videoId: t.videoId || '',
        title: t.title || '',
        artists: (t.artists || []).map(a => ({ name: a.name, artistId: a.id || '' })),
        channelTitle: t.channelTitle || (t.artists || []).map(a => a.name).join(', '),
        channelId: t.channelId || t.artists?.[0]?.id || '',
        thumbnail: getBestThumbnail(t.thumbnail),
        duration: t.duration || 0,
        album: t.album || '',
        albumId: t.albumId || '',
      })),
    }))
  },

  albumArtCache: new Map(),

  async getAlbumArt(title, artist) {
    const key = `${title}|${artist}`;
    if (this.albumArtCache.has(key)) return this.albumArtCache.get(key);
    const promise = (async () => {
      try {
        const res = await fetch(`${API_BASE}/albumart?title=${encodeURIComponent(title || '')}&artist=${encodeURIComponent(artist || '')}`);
        const data = await res.json();
        const url = data?.url || null;
        this.albumArtCache.set(key, url);
        return url;
      } catch {
        this.albumArtCache.set(key, null);
        return null;
      }
    })();
    this.albumArtCache.set(key, promise);
    return promise;
  },
}
