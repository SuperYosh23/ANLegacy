import { useEffect, useRef } from 'react';
import { createPortal } from 'react-dom';

export const ContextMenu = ({ items, position, onClose }) => {
  const menuRef = useRef(null);

  useEffect(() => {
    const handleKey = (e) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', handleKey);
    return () => window.removeEventListener('keydown', handleKey);
  }, [onClose]);

  const adjustedX = Math.min(position.x, window.innerWidth - 160);
  const adjustedY = Math.min(position.y, window.innerHeight - items.length * 36 - 16);

  return createPortal(
    <div className="fixed inset-0 z-[9999]" onMouseDown={onClose}>
      <div
        ref={menuRef}
        onMouseDown={(e) => e.stopPropagation()}
        style={{ left: adjustedX, top: adjustedY }}
        className="absolute min-w-[140px] bg-surface-container-high border border-outline-variant rounded-xl shadow-2xl py-1 animate-fadeIn"
      >
        {items.map((item, i) => (
          item.separator ? (
            <div key={i} className="h-px bg-outline-variant my-1 mx-2" />
          ) : (
            <button
              key={i}
              onClick={() => { item.onClick?.(); onClose(); }}
              className={`w-full flex items-center gap-2 px-3 py-1.5 text-sm text-left transition-colors ${
                item.danger
                  ? 'text-red-400 hover:bg-red-400/10'
                  : 'text-on-surface hover:bg-surface-container'
              }`}
            >
              {item.icon && <span className="w-4 h-4">{item.icon}</span>}
              {item.label}
            </button>
          )
        ))}
      </div>
    </div>,
    document.body
  );
};
