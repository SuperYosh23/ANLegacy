import { useRef, useEffect } from 'react';
import { usePlayer } from '../context/PlayerContext';
import { EQ_GAIN_MIN, EQ_GAIN_MAX, computeEqCurve, getActiveBands } from '../utils/eqEngine';

const BAR_COUNT = 64;

export const AudioVisualizer = () => {
  const { eqAnalyserRef, eqEnabled, eqIndices, eqGains, isPlaying } = usePlayer();
  const canvasRef = useRef(null);
  const gainsRef = useRef(eqGains);
  const indicesRef = useRef(eqIndices);
  const enabledRef = useRef(eqEnabled);
  const playingRef = useRef(isPlaying);
  const curveCacheRef = useRef(null);

  gainsRef.current = eqGains;
  indicesRef.current = eqIndices;
  enabledRef.current = eqEnabled;
  playingRef.current = isPlaying;

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext('2d');
    let rafId = null;

    const resize = () => {
      const rect = canvas.parentElement.getBoundingClientRect();
      canvas.width = rect.width * devicePixelRatio;
      canvas.height = rect.height * devicePixelRatio;
      canvas.style.width = `${rect.width}px`;
      canvas.style.height = `${rect.height}px`;
    };

    resize();
    const ro = new ResizeObserver(resize);
    ro.observe(canvas.parentElement);

    const draw = () => {
      rafId = requestAnimationFrame(draw);
      const w = canvas.width;
      const h = canvas.height;
      const dpr = devicePixelRatio;

      ctx.clearRect(0, 0, w, h);

      const analyser = eqAnalyserRef?.current;
      const hasAudio = analyser && playingRef.current;

      let freqData = null;
      if (hasAudio) {
        const buffer = new Uint8Array(analyser.frequencyBinCount);
        analyser.getByteFrequencyData(buffer);

        const step = Math.max(1, Math.floor(buffer.length / BAR_COUNT));
        freqData = [];
        for (let i = 0; i < BAR_COUNT; i++) {
          let sum = 0, count = 0;
          for (let j = 0; j < step && i * step + j < buffer.length; j++) {
            sum += buffer[i * step + j];
            count++;
          }
          freqData.push(count > 0 ? sum / count : 0);
        }
      }

      const barW = (w - 8) / BAR_COUNT;
      const gap = 0.5 * dpr;
      const usableH = h - 2;
      const bottomY = h - 1;

      if (freqData) {
        for (let i = 0; i < BAR_COUNT; i++) {
          const norm = freqData[i] / 255;
          const barH = norm * usableH;
          const x = 4 + i * barW + gap / 2;
          const bw = barW - gap;

          if (bw <= 0) continue;

          const gradient = ctx.createLinearGradient(x, bottomY - barH, x, bottomY);
          gradient.addColorStop(0, 'rgba(99, 102, 241, 0.7)');
          gradient.addColorStop(0.5, 'rgba(129, 140, 248, 0.5)');
          gradient.addColorStop(1, 'rgba(129, 140, 248, 0.15)');

          ctx.fillStyle = gradient;
          ctx.beginPath();
          ctx.roundRect(x, bottomY - barH, bw, barH, [1 * dpr, 1 * dpr, 0, 0]);
          ctx.fill();
        }
      }

      const currentIndices = indicesRef.current;
      const currentGains = gainsRef.current;
      const currentEnabled = enabledRef.current;
      const cacheKey = currentEnabled + ':' + currentIndices.join(',') + ':' + currentGains.join(',');

      if (curveCacheRef.current?.key !== cacheKey) {
        if (currentEnabled) {
          const activeBands = getActiveBands(currentIndices, currentGains);
          curveCacheRef.current = { key: cacheKey, curve: computeEqCurve(activeBands, BAR_COUNT) };
        } else {
          curveCacheRef.current = { key: cacheKey, curve: null };
        }
      }

      const curve = curveCacheRef.current?.curve;

      if (curve) {
        const range = EQ_GAIN_MAX - EQ_GAIN_MIN;

        ctx.beginPath();
        for (let i = 0; i < curve.length; i++) {
          const x = 4 + (i / (curve.length - 1)) * (w - 8);
          const y = bottomY - ((curve[i] - EQ_GAIN_MIN) / range) * usableH;
          if (i === 0) ctx.moveTo(x, y);
          else ctx.lineTo(x, y);
        }
        ctx.strokeStyle = 'rgba(255, 255, 255, 0.5)';
        ctx.lineWidth = 1.5 * dpr;
        ctx.stroke();
      }


    };

    draw();

    return () => {
      if (rafId) cancelAnimationFrame(rafId);
      ro.disconnect();
    };
  }, [eqAnalyserRef]);

  return (
    <canvas
      ref={canvasRef}
      className="w-full h-[72px] outline-none"
    />
  );
};
