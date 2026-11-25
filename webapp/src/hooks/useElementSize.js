import { useState, useEffect, useCallback } from 'react';

// Measures an element with a ResizeObserver. The now-playing overlay is
// positioned with `left: sidebarWidth`, so its usable width depends on the
// resizable sidebar rather than on window.innerWidth - it has to be measured.
export function useElementSize(ref) {
  const [size, setSize] = useState({ width: 0, height: 0 });

  const measure = useCallback(() => {
    const el = ref.current;
    if (!el) return;
    const { width, height } = el.getBoundingClientRect();
    setSize(prev => (prev.width === width && prev.height === height ? prev : { width, height }));
  }, [ref]);

  useEffect(() => {
    measure();
    const el = ref.current;
    if (!el || typeof ResizeObserver === 'undefined') return;
    const ro = new ResizeObserver(measure);
    ro.observe(el);
    return () => ro.disconnect();
  }, [ref, measure]);

  return size;
}