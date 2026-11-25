import { useState, useEffect, useRef, useCallback } from 'react';
import { Music } from 'lucide-react';

export const RetryImage = ({ src, alt, className, fallbackSrc, onError, ...props }) => {
  const [retryCount, setRetryCount] = useState(0);
  const [fallbackIndex, setFallbackIndex] = useState(-1);
  const timerRef = useRef(null);
  const mountedRef = useRef(true);

  const fallbacks = Array.isArray(fallbackSrc)
    ? fallbackSrc.filter(Boolean)
    : fallbackSrc
      ? [fallbackSrc]
      : [];

  const currentSrc = fallbackIndex >= 0 ? fallbacks[fallbackIndex] : src;

  useEffect(() => {
    mountedRef.current = true;
    setRetryCount(0);
    setFallbackIndex(-1);
    return () => {
      mountedRef.current = false;
      if (timerRef.current) clearTimeout(timerRef.current);
    };
  }, [src, fallbackSrc]);

  const handleError = useCallback(() => {
    if (!mountedRef.current) return;
    const maxRetries = 10;
    if (retryCount < maxRetries) {
      const delay = 2000 + retryCount * 1000;
      timerRef.current = setTimeout(() => {
        if (mountedRef.current) setRetryCount(c => c + 1);
      }, delay);
    } else if (fallbackIndex + 1 < fallbacks.length) {
      setFallbackIndex(i => i + 1);
      setRetryCount(0);
    } else {
      onError?.();
    }
  }, [retryCount, onError, fallbackIndex, fallbacks.length]);

  if (!currentSrc) {
    return (
      <div className={className}>
        <Music size={24} className="w-full h-full opacity-30 text-on-surface-variant" />
      </div>
    );
  }

  const cacheBust = retryCount > 0 && !currentSrc.startsWith('data:') ? `?rb=${retryCount}_${Date.now()}` : '';
  const actualSrc = retryCount > 0 && !currentSrc.startsWith('data:') ? `${currentSrc}${cacheBust}` : currentSrc;

  return (
    <img
      key={`fb${fallbackIndex}-${retryCount}`}
      src={actualSrc}
      alt={alt}
      className={className}
      onError={handleError}
      {...props}
    />
  );
};
