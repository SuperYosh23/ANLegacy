import { useRef, useEffect, useState } from 'react';

function resolveColor(variable, fallback) {
  if (typeof document === 'undefined') return fallback;
  // getComputedStyle().getPropertyValue() returns null for a custom property on
  // a browser without CSS variable support - iOS 9, which is what the phone
  // runs. Calling .trim() on that null threw while the player's progress bar
  // was rendering, which took the whole screen down the moment a song started.
  const raw = getComputedStyle(document.documentElement).getPropertyValue(variable);
  return (raw || '').trim() || fallback;
}

export const WavyProgressBar = ({ progress = 0, height, onSeek }) => {
  const canvasRef = useRef(null);
  const wrapRef = useRef(null);
  const progressRef = useRef(progress);
  const draggingRef = useRef(false);
  const [dragging, setDragging] = useState(false);
  progressRef.current = progress;

  useEffect(() => {
    const canvas = canvasRef.current;
    const wrap = wrapRef.current;
    if (!canvas || !wrap) return;

    const dpr = window.devicePixelRatio || 1;
    const colors = {
      track: resolveColor('--color-surface-container-high', '#2B2930'),
      primary: resolveColor('--color-primary', '#FF8A9B'),
    };

    let phase = 0;
    let rafId;

    const draw = () => {
      phase = (phase + 1.5) % 360;
      const rect = wrap.getBoundingClientRect();
      const w = rect.width;

      if (w === 0) {
        rafId = requestAnimationFrame(draw);
        return;
      }

      canvas.width = w * dpr;
      canvas.height = height * dpr;
      canvas.style.width = `${w}px`;
      canvas.style.height = `${height}px`;

      const smooth = Math.min(1, Math.max(0, progressRef.current));

      const ctx = canvas.getContext('2d');
      ctx.scale(dpr, dpr);

      const centerY = height / 2;
      const strokeW = height * 0.7;
      const amp = height * 0.15;
      const wl = 32;
      const phaseRad = phase * Math.PI / 180;
      const pw = Math.max(0, Math.min(w, smooth * w));

      // Track
      ctx.beginPath();
      ctx.moveTo(0, centerY);
      ctx.lineTo(w, centerY);
      ctx.strokeStyle = colors.track;
      ctx.lineWidth = strokeW;
      ctx.lineCap = 'round';
      ctx.stroke();

      // Active wavy indicator
      ctx.beginPath();
      for (let x = 0; x <= pw; x += 1) {
        const y = centerY + amp * Math.sin(2 * Math.PI * x / wl + phaseRad);
        if (x === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
      }
      ctx.strokeStyle = colors.primary;
      ctx.lineWidth = strokeW;
      ctx.lineCap = 'round';
      ctx.stroke();

      rafId = requestAnimationFrame(draw);
    };

    rafId = requestAnimationFrame(draw);
    return () => cancelAnimationFrame(rafId);
  }, [height]);

  const seekFromEvent = (e) => {
    if (!onSeek || !wrapRef.current) return;
    const rect = wrapRef.current.getBoundingClientRect();
    const fraction = (e.clientX - rect.left) / rect.width;
    onSeek(Math.max(0, Math.min(1, fraction)));
  };

  const pointerDownRef = useRef(null);

  const handlePointerDown = (e) => {
    pointerDownRef.current = { clientX: e.clientX, clientY: e.clientY };
    draggingRef.current = true;
    setDragging(true);
    e.currentTarget.setPointerCapture(e.pointerId);
    seekFromEvent(e);
  };

  const handlePointerMove = (e) => {
    if (!draggingRef.current) return;
    seekFromEvent(e);
  };

  const handlePointerUp = (e) => {
    if (!draggingRef.current) return;
    draggingRef.current = false;
    setDragging(false);
    e.currentTarget.releasePointerCapture(e.pointerId);
    seekFromEvent(e);
  };

  const handleClick = (e) => {
    const pd = pointerDownRef.current;
    if (pd && (Math.abs(e.clientX - pd.clientX) > 3 || Math.abs(e.clientY - pd.clientY) > 3)) return;
    pointerDownRef.current = null;
    seekFromEvent(e);
  };

  return (
    <div
      ref={wrapRef}
      onClick={handleClick}
      onPointerDown={handlePointerDown}
      onPointerMove={handlePointerMove}
      onPointerUp={handlePointerUp}
      style={{
        width: '100%',
        height,
        cursor: 'pointer',
        position: 'relative',
        touchAction: 'none',
      }}
      className={dragging ? 'opacity-80' : ''}
    >
      <canvas ref={canvasRef} style={{ display: 'block', width: '100%', height }} />
    </div>
  );
};
