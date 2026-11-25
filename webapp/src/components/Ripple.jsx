import { useState, useRef, useCallback } from 'react';

export const Ripple = ({ children, className = '', slow = false, ...props }) => {
  const [ripples, setRipples] = useState([]);
  const ref = useRef(null);
  const counter = useRef(0);

  const handleClick = useCallback((e) => {
    const el = ref.current;
    if (!el) return;
    const rect = el.getBoundingClientRect();
    const size = Math.max(rect.width, rect.height);
    const x = e.clientX - rect.left - size / 2;
    const y = e.clientY - rect.top - size / 2;
    const id = ++counter.current;

    setRipples(prev => [...prev, { id, x, y, size }]);
    setTimeout(() => {
      setRipples(prev => prev.filter(r => r.id !== id));
    }, 500);
  }, []);

  return (
    <div ref={ref} data-ripple-container className={`relative overflow-hidden ${className}`} onClick={handleClick} {...props}>
      {children}
      {ripples.map(r => (
        <span
          key={r.id}
          className={`absolute rounded-full bg-current/15 pointer-events-none ${slow ? 'animate-ripple-slow' : 'animate-ripple'}`}
          style={{
            left: r.x,
            top: r.y,
            width: r.size,
            height: r.size,
          }}
        />
      ))}
    </div>
  );
};
