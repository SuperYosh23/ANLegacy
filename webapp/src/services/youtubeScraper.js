import { apiService } from './apiService'

class YouTubeScraperService {
  parseDuration(text) {
    if (!text) return 0
    text = text.trim()
    const parts = text.split(':')
    if (parts.length === 2) return parseInt(parts[0]) * 60 + parseInt(parts[1])
    if (parts.length === 3) return parseInt(parts[0]) * 3600 + parseInt(parts[1]) * 60 + parseInt(parts[2])
    return 0
  }

  formatDuration(seconds) {
    if (!seconds) return '0:00'
    const h = Math.floor(seconds / 3600)
    const m = Math.floor((seconds % 3600) / 60)
    const s = seconds % 60
    if (h > 0) {
      return `${h}:${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}`
    }
    return `${m}:${s.toString().padStart(2, '0')}`
  }

  async search(query, maxResults = 20, filterExplicit = false) {
    return await apiService.searchSongs(query, maxResults, filterExplicit)
  }

  async searchAll(query, filterExplicit = false) {
    return await apiService.searchAll(query, filterExplicit)
  }

  async searchAlbums(query, maxResults = 10) {
    return await apiService.searchAlbums(query, maxResults)
  }

  async getPlaylistTracks(playlistId) {
    const cleanId = playlistId.replace(/^VL/, '')
    const isAlbum = cleanId.startsWith('MPRE')
    if (isAlbum) {
      const album = await apiService.getAlbum(cleanId)
      return album.tracks
    }
    const playlist = await apiService.getPlaylist(cleanId)
    return playlist.tracks
  }

  async getRelatedVideos(query, maxResults = 20) {
    const searchQuery = typeof query === 'string' ? query : (query.title || query.channelTitle || '')
    if (!searchQuery) return []
    return await apiService.searchSongs(searchQuery, maxResults)
  }

  async getVideoDetails(videoId) {
    return await apiService.getSong(videoId)
  }
}

export const youtubeScraperService = new YouTubeScraperService()
