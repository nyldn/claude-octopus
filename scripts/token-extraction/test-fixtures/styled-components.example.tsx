/**
 * Example Styled Components Theme
 * Demonstrates styled-components theme provider pattern
 */

import { ThemeProvider } from 'styled-components';

export const styledTheme = {
  colors: {
    primary: '#3b82f6',
    secondary: '#8b5cf6',
    accent: '#10b981',
    neutral: {
      50: '#f9fafb',
      100: '#f3f4f6',
      200: '#e5e7eb',
      300: '#d1d5db',
      400: '#9ca3af',
      500: '#6b7280',
      600: '#4b5563',
      700: '#374151',
      800: '#1f2937',
      900: '#111827',
    },
  },

  space: [0, 4, 8, 16, 24, 32, 48, 64, 96, 128],

  fonts: {
    body: 'Inter, system-ui, sans-serif',
    heading: 'Inter, system-ui, sans-serif',
    mono: 'Fira Code, monospace',
  },

  fontSizes: [12, 14, 16, 18, 20, 24, 28, 32, 40, 48],

  fontWeights: {
    light: 300,
    normal: 400,
    medium: 500,
    semibold: 600,
    bold: 700,
  },

  lineHeights: {
    solid: 1,
    title: 1.25,
    copy: 1.5,
  },

  radii: {
    none: 0,
    sm: 4,
    md: 8,
    lg: 16,
    full: 9999,
  },

  shadows: {
    sm: '0 1px 3px rgba(0, 0, 0, 0.12)',
    md: '0 4px 6px rgba(0, 0, 0, 0.1)',
    lg: '0 10px 20px rgba(0, 0, 0, 0.15)',
    xl: '0 20px 40px rgba(0, 0, 0, 0.2)',
  },

  zIndices: {
    hide: -1,
    auto: 'auto',
    base: 0,
    docked: 10,
    dropdown: 1000,
    sticky: 1100,
    banner: 1200,
    overlay: 1300,
    modal: 1400,
    popover: 1500,
    skipLink: 1600,
    toast: 1700,
    tooltip: 1800,
  },

  transitions: {
    fast: '0.1s',
    base: '0.2s',
    slow: '0.3s',
  },

  breakpoints: ['640px', '768px', '1024px', '1280px'],
};

export type StyledTheme = typeof styledTheme;

// Example component usage
export const App = () => {
  return (
    <ThemeProvider theme={styledTheme}>
      <div>Themed App</div>
    </ThemeProvider>
  );
};
