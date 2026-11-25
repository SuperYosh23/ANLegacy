import { M3LoadingIndicator } from '@alerix/m3-loading-indicator/react';

function getPrimaryColor() {
  if (typeof document === 'undefined') return '#FF8A9B';
  const style = getComputedStyle(document.documentElement);
  // null on a browser without CSS custom property support, so the same guard
  // as the progress bar's.
  const raw = style.getPropertyValue('--color-primary');
  return (raw || '').trim() || '#FF8A9B';
}

export const LoadingIndicator = ({ size = 'md', className = '', color, contained = false }) => {
  const sizes = { sm: 24, md: 40, lg: 48 };
  const dim = sizes[size] || sizes.md;

  return (
    <M3LoadingIndicator
      size={dim}
      color={color || getPrimaryColor()}
      contained={contained}
      className={className}
    />
  );
};
