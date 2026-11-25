import { SlidersHorizontal, RotateCcw, Plus, Minus, Save, X, Check } from 'lucide-react';
import { useState, useRef, useEffect } from 'react';
import { usePlayer } from '../context/PlayerContext';
import { EQ_BANDS_POOL, EQ_GAIN_MIN, EQ_GAIN_MAX, EQ_PRESETS, getActiveBands } from '../utils/eqEngine';
import { AudioVisualizer } from './AudioVisualizer';

export const EQPanel = () => {
  const { eqEnabled, eqIndices, eqGains, userPresets, saveCurrentPreset, deleteUserPreset, setEqBand, addEqBand, removeEqBand, toggleEq, resetEq, applyPreset } = usePlayer();

  const [showSaveInput, setShowSaveInput] = useState(false);
  const [presetName, setPresetName] = useState('');
  const [saveMessage, setSaveMessage] = useState('');
  const saveInputRef = useRef(null);

  const activeBands = getActiveBands(eqIndices, eqGains);

  const currentBuiltinPreset = EQ_PRESETS.find(p =>
    eqIndices.every((idx, i) => p.gains[idx] === eqGains[i])
  );

  const currentUserPreset = userPresets.find(p =>
    p.indices.length === eqIndices.length &&
    p.gains.length === eqGains.length &&
    p.indices.every((idx, i) => idx === eqIndices[i]) &&
    p.gains.every((g, i) => g === eqGains[i])
  );

  const currentPresetName = currentBuiltinPreset?.name || currentUserPreset?.name || null;

  useEffect(() => {
    if (showSaveInput && saveInputRef.current) {
      saveInputRef.current.focus();
    }
  }, [showSaveInput]);

  const handleSave = () => {
    const name = presetName.trim();
    if (!name) return;
    saveCurrentPreset(name);
    setPresetName('');
    setShowSaveInput(false);
    setSaveMessage(`Saved "${name}"`);
    setTimeout(() => setSaveMessage(''), 2000);
  };

  const canAdd = eqIndices.length < EQ_BANDS_POOL.length;
  const canRemove = eqIndices.length > 10;

  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center gap-2">
          <SlidersHorizontal size={18} className="text-primary" />
          <h3 className="text-base font-semibold text-on-surface">Equalizer</h3>
        </div>
        <div className="flex items-center gap-2">
          {saveMessage && (
            <span className="text-[11px] text-primary mr-1">{saveMessage}</span>
          )}
          <button
            onClick={resetEq}
            className="p-1.5 text-on-surface-variant hover:text-on-surface rounded-lg hover:bg-surface-container-high transition-colors"
            title="Reset EQ"
          >
            <RotateCcw size={14} />
          </button>
          <button
            onClick={toggleEq}
            className={`relative w-10 h-5 rounded-full transition-all ${
              eqEnabled ? 'bg-primary' : 'bg-surface-container-high'
            }`}
          >
            <div
              className={`w-4 h-4 bg-white rounded-full shadow-sm transition-all ${
                eqEnabled ? 'translate-x-[22px]' : 'translate-x-[2px]'
              }`}
            />
          </button>
        </div>
      </div>

      <div className="flex items-center gap-2 mb-3">
        <div className="relative flex-1">
          <select
            value={currentPresetName || '__custom__'}
            onChange={(e) => {
              const val = e.target.value;
              if (val === '__custom__') return;
              const builtin = EQ_PRESETS.find(p => p.name === val);
              if (builtin) { applyPreset(builtin.gains); return; }
              const user = userPresets.find(p => p.name === val);
              if (user) applyPreset(user.gains, user.indices);
            }}
            className="w-full appearance-none px-3 py-1.5 pr-8 rounded-lg text-xs font-medium bg-surface-container-high text-on-surface border border-outline-variant focus:outline-none focus:border-primary cursor-pointer"
          >
            {currentPresetName ? null : (
              <option value="__custom__">Custom</option>
            )}
            <optgroup label="Built-in">
              {EQ_PRESETS.map(preset => (
                <option key={preset.name} value={preset.name}>{preset.name}</option>
              ))}
            </optgroup>
            {userPresets.length > 0 && (
              <optgroup label="My Presets">
                {userPresets.map(preset => (
                  <option key={preset.name} value={preset.name}>{preset.name}</option>
                ))}
              </optgroup>
            )}
          </select>
          <div className="pointer-events-none absolute right-2 top-1/2 -translate-y-1/2 text-on-surface-variant">
            <svg width="12" height="12" viewBox="0 0 12 12" fill="none"><path d="M3 4.5L6 7.5L9 4.5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"/></svg>
          </div>
        </div>

        {showSaveInput ? (
          <div className="flex items-center gap-1">
            <input
              ref={saveInputRef}
              type="text"
              value={presetName}
              onChange={(e) => setPresetName(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') handleSave();
                if (e.key === 'Escape') { setShowSaveInput(false); setPresetName(''); }
              }}
              placeholder="Name..."
              className="w-24 px-2 py-1.5 rounded-lg text-xs bg-surface-container-high text-on-surface border border-outline-variant focus:outline-none focus:border-primary placeholder:text-outline"
            />
            <button
              onClick={handleSave}
              disabled={!presetName.trim()}
              className="p-1.5 rounded-lg text-primary hover:bg-primary/10 transition-colors disabled:opacity-30 disabled:cursor-not-allowed"
            >
              <Check size={14} />
            </button>
          </div>
        ) : (
          <button
            onClick={() => setShowSaveInput(true)}
            className="p-1.5 rounded-lg text-on-surface-variant hover:text-on-surface hover:bg-surface-container-high transition-colors"
            title="Save current EQ as preset"
          >
            <Save size={14} />
          </button>
        )}

        {currentPresetName && userPresets.some(p => p.name === currentPresetName) && (
          <button
            onClick={() => deleteUserPreset(currentPresetName)}
            className="p-1.5 rounded-lg text-on-surface-variant hover:text-red-400 hover:bg-surface-container-high transition-colors"
            title={`Delete "${currentPresetName}"`}
          >
            <X size={14} />
          </button>
        )}
      </div>

      <div className="mb-3">
        <AudioVisualizer />
      </div>

      <div className="relative pt-1 pb-0.5">
        <div className="flex justify-between text-[9px] text-outline mb-1 px-1.5">
          <span>+12</span>
          <span>-12</span>
        </div>

        <div className="flex items-end justify-between gap-1.5 px-1">
          {activeBands.map((band, i) => {
            const gain = eqGains[i] ?? 0;
            const pctFromCenter = (Math.abs(gain) / EQ_GAIN_MAX) * 50;

            return (
              <div key={band.freq} className="flex flex-col items-center gap-0.5 flex-1 min-w-0">
                <span
                  className={`text-[9px] font-mono tabular-nums leading-none transition-colors ${
                    eqEnabled
                      ? gain > 1
                        ? 'text-indigo-400'
                        : gain < -1
                          ? 'text-orange-400'
                          : 'text-on-surface-variant'
                      : 'text-on-surface-variant/50'
                  }`}
                >
                  {gain > 0 ? '+' : ''}{gain.toFixed(1)}
                </span>

                <div className="relative h-28 w-full max-w-[24px]">
                  <div className="absolute inset-0 rounded-full bg-surface-container-high" />

                  <div className="absolute left-[3px] right-[3px] top-0 bottom-0 rounded-full overflow-hidden">
                    <div
                      className={`absolute left-0 right-0 rounded-full transition-all duration-100 ${
                        gain >= 0 ? 'bottom-1/2' : 'top-1/2'
                      }`}
                      style={{
                        height: `${pctFromCenter}%`,
                        background: eqEnabled
                          ? gain > 0
                            ? 'linear-gradient(to top, #6366f1, #818cf8)'
                            : gain < 0
                              ? 'linear-gradient(to top, #f97316, #fb923c)'
                              : '#374151'
                          : '#374151',
                        opacity: eqEnabled ? (gain !== 0 ? 1 : 0.3) : 0.15,
                      }}
                    />
                  </div>

                  <div className="absolute left-1 right-1 top-1/2 h-[1px] bg-outline-variant/40" />

                  <input
                    type="range"
                    min={EQ_GAIN_MIN}
                    max={EQ_GAIN_MAX}
                    step="0.5"
                    value={gain}
                    onChange={(e) => setEqBand(i, parseFloat(e.target.value))}
                    className="absolute inset-0 w-full h-full cursor-pointer appearance-none bg-transparent opacity-0 [writing-mode:vertical-lr] [direction:rtl]"
                    style={{ zIndex: 2 }}
                  />
                </div>

                <span className={`text-[9px] leading-none mt-0.5 ${
                  eqEnabled ? 'text-on-surface-variant' : 'text-on-surface-variant/50'
                }`}>
                  {band.label}
                </span>
              </div>
            );
          })}
        </div>

        <div className="flex items-center justify-center gap-3 mt-3">
          <button
            onClick={removeEqBand}
            disabled={!canRemove}
            className={`flex items-center gap-1 px-2 py-1 rounded-lg text-xs font-medium transition-all ${
              canRemove
                ? 'text-on-surface-variant hover:text-on-surface hover:bg-surface-container-high'
                : 'text-on-surface-variant/30 cursor-not-allowed'
            }`}
          >
            <Minus size={12} />
            <span>Remove band</span>
          </button>
          <span className="text-[10px] text-outline font-mono">
            {eqIndices.length} / {EQ_BANDS_POOL.length}
          </span>
          <button
            onClick={addEqBand}
            disabled={!canAdd}
            className={`flex items-center gap-1 px-2 py-1 rounded-lg text-xs font-medium transition-all ${
              canAdd
                ? 'text-on-surface-variant hover:text-on-surface hover:bg-surface-container-high'
                : 'text-on-surface-variant/30 cursor-not-allowed'
            }`}
          >
            <Plus size={12} />
            <span>Add band</span>
          </button>
        </div>
      </div>
    </div>
  );
};
