import { useState, useEffect, useCallback } from 'react';
import { BarChart3, Clock, Music, Play, TrendingUp, MicVocal, ChevronDown, ChevronUp } from 'lucide-react';
import { usePlayer } from '../context/PlayerContext';
import { statsUtils, storage } from '../utils/storage';
import { ArtImage } from './ArtImage';
import { ArtistAvatar } from './ArtistAvatar';

const TOP_COUNT = 5;

function longDuration(seconds) {
  const s = Math.floor(seconds);
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  if (h > 0) return `${h}h ${m}m`;
  if (m > 0) return `${m}m ${s % 60}s`;
  return `${s}s`;
}

function entryToSong(entry) {
  return {
    videoId: entry.videoId,
    title: entry.title,
    channelTitle: entry.channelTitle,
    artists: entry.channelTitle ? [{ name: entry.channelTitle }] : [],
    thumbnail: entry.thumbnail,
    album: entry.album,
    duration: entry.duration,
  };
}

function StatCard({ icon: Icon, value, caption, gradient }) {
  return (
    <div className={`relative overflow-hidden rounded-2xl p-4 min-w-0 flex-1 text-white shadow-lg ${gradient}`}>
      <div className="text-[28px] font-bold leading-none truncate">{value}</div>
      <div className="text-[11px] mt-1 opacity-80 flex items-center gap-1">
        <Icon size={13} />
        {caption}
      </div>
    </div>
  );
}

export const Stats = () => {
  const [data, setData] = useState({ mostPlayed: [], topArtists: [], time: 0, plays: 0, songs: 0 });
  const [showAll, setShowAll] = useState({ most: false, artists: false });
  const { playSong } = usePlayer();

  const refresh = useCallback(() => {
    setData({
      mostPlayed: statsUtils.mostPlayed(),
      topArtists: statsUtils.topArtists(),
      time: statsUtils.totalTime(),
      plays: statsUtils.totalPlays(),
      songs: storage.getTotalSongs(),
    });
  }, []);

  useEffect(() => {
    refresh();
    window.addEventListener('stats-changed', refresh);
    window.addEventListener('history-changed', refresh);
    return () => {
      window.removeEventListener('stats-changed', refresh);
      window.removeEventListener('history-changed', refresh);
    };
  }, [refresh]);

  const handlePlay = (entry) => {
    playSong(entryToSong(entry), [entryToSong(entry)]);
  };

  const mostPlayed = showAll.most ? data.mostPlayed : data.mostPlayed.slice(0, TOP_COUNT);
  const topArtists = showAll.artists ? data.topArtists : data.topArtists.slice(0, TOP_COUNT);

  return (
    <div className="p-6 animate-fadeIn">
      <h2 className="text-2xl font-bold text-on-surface mb-6 flex items-center gap-2">
        <BarChart3 size={24} />
        Listening Stats
      </h2>

      {/* Stat cards */}
      <div className="flex flex-wrap gap-4 mb-8">
        <StatCard
          icon={Clock}
          value={longDuration(data.time)}
          caption="Time Listened"
          gradient="bg-gradient-to-br from-primary via-primary-container to-secondary-container"
        />
        <StatCard
          icon={Music}
          value={String(data.songs)}
          caption="Unique Songs"
          gradient="bg-gradient-to-br from-secondary-container to-tertiary-container"
        />
        <StatCard
          icon={TrendingUp}
          value={String(data.plays)}
          caption="Plays"
          gradient="bg-gradient-to-br from-surface-container-high to-surface-container"
        />
      </div>

      {/* Most Played */}
      <div className="mb-8">
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-xl font-bold text-on-surface flex items-center gap-2">
            <Play size={20} className="text-primary" />
            Most Played
          </h3>
          {data.mostPlayed.length > TOP_COUNT && (
            <button
              onClick={() => setShowAll(s => ({ ...s, most: !s.most }))}
              className="flex items-center gap-1 text-sm text-primary hover:text-primary/80 transition-colors"
            >
              {showAll.most ? <><ChevronUp size={16} /> Show less</> : <><ChevronDown size={16} /> See All</>}
            </button>
          )}
        </div>
        {mostPlayed.length === 0 ? (
          <p className="text-on-surface-variant text-sm">Play some music to see your most played songs.</p>
        ) : (
          <div className="bg-surface-container/30 rounded-2xl divide-y divide-outline-variant/20 overflow-hidden">
            {mostPlayed.map((entry, index) => (
              <button
                key={entry.videoId}
                onClick={() => handlePlay(entry)}
                className="w-full flex items-center gap-3 p-2.5 hover:bg-surface-container-high/50 transition-all text-left group"
                title={entry.title}
              >
                <span className="w-6 text-sm font-semibold text-on-surface-variant shrink-0">{index + 1}</span>
                <ArtImage
                  src={entry.thumbnail}
                  alt={entry.title}
                  className="w-12 h-12 rounded-xl object-cover shadow-md shrink-0"
                />
                <div className="flex-1 min-w-0">
                  <p className="text-on-surface font-medium truncate">{entry.title || 'Unknown Song'}</p>
                  <p className="text-xs text-on-surface-variant truncate">
                    {entry.plays} play{entry.plays === 1 ? '' : 's'}  •  {longDuration(entry.seconds)}
                  </p>
                </div>
                <span className="p-2.5 rounded-full bg-primary text-on-primary opacity-0 group-hover:opacity-100 transition-opacity">
                  <Play size={16} fill="currentColor" />
                </span>
              </button>
            ))}
          </div>
        )}
      </div>

      {/* Top Artists */}
      <div className="mb-4">
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-xl font-bold text-on-surface flex items-center gap-2">
            <MicVocal size={20} className="text-primary" />
            Top Artists
          </h3>
          {data.topArtists.length > TOP_COUNT && (
            <button
              onClick={() => setShowAll(s => ({ ...s, artists: !s.artists }))}
              className="flex items-center gap-1 text-sm text-primary hover:text-primary/80 transition-colors"
            >
              {showAll.artists ? <><ChevronUp size={16} /> Show less</> : <><ChevronDown size={16} /> See All</>}
            </button>
          )}
        </div>
        {topArtists.length === 0 ? (
          <p className="text-on-surface-variant text-sm">Play some music to see your top artists.</p>
        ) : (
          <div className="bg-surface-container/30 rounded-2xl divide-y divide-outline-variant/20 overflow-hidden">
            {topArtists.map((artist, index) => (
              <div key={artist.name} className="flex items-center gap-3 p-2.5">
                <span className="w-6 text-sm font-semibold text-on-surface-variant shrink-0">{index + 1}</span>
                <ArtistAvatar name={artist.name} fallbackThumb="" className="w-12 h-12 rounded-full object-cover shadow-md shrink-0" />
                <div className="flex-1 min-w-0">
                  <p className="text-on-surface font-medium truncate">{artist.name}</p>
                  <p className="text-xs text-on-surface-variant truncate">
                    {longDuration(artist.seconds)}  •  {artist.plays} play{artist.plays === 1 ? '' : 's'}
                  </p>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
};