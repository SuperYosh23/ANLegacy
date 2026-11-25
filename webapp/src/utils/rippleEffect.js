const SELECTOR = 'button, a, [role="button"], label, input:not([type="range"]), select, textarea, .cursor-pointer';

export function initGlobalRipple() {
  document.addEventListener('mousedown', (e) => {
    const target = e.target.closest(SELECTOR);
    if (!target) return;
    if (target.closest('[data-ripple-container]')) return;
    if (target.closest('.no-ripple')) return;

    const rect = target.getBoundingClientRect();
    const size = Math.max(rect.width, rect.height);
    const x = e.clientX - rect.left - size / 2;
    const y = e.clientY - rect.top - size / 2;
    const color = getComputedStyle(target).color;

    const duration = target.classList.contains('cursor-pointer') ? '0.6s' : '0.4s';
    const ripple = document.createElement('span');
    ripple.className = 'pointer-events-none';
    ripple.style.cssText = `
      position: absolute;
      border-radius: 50%;
      width: ${size}px;
      height: ${size}px;
      left: ${x}px;
      top: ${y}px;
      background-color: ${color};
      opacity: 0.2;
      transform: scale(0);
      animation: ripple ${duration} ease-out forwards;
    `;

    const origPos = target.style.position;
    if (!origPos || origPos === 'static') {
      target.style.position = 'relative';
    }

    if (!target.dataset.rippleOrigOverflow) {
      target.dataset.rippleOrigOverflow = target.style.overflow || '';
    }
    target.style.overflow = 'hidden';

    const count = (parseInt(target.dataset.rippleCount) || 0) + 1;
    target.dataset.rippleCount = count;

    target.appendChild(ripple);

    ripple.addEventListener('animationend', () => {
      ripple.remove();
      const remaining = parseInt(target.dataset.rippleCount) - 1;
      target.dataset.rippleCount = remaining;
      if (remaining <= 0) {
        const origOverflow = target.dataset.rippleOrigOverflow;
        delete target.dataset.rippleOrigOverflow;
        target.style.overflow = origOverflow;
      }
    });
  });
}
