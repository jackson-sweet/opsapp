// OPS mobile design tokens — JS mirror of tokens.css for inline-style use.
// Keep in sync with /tokens.css. Values match MOBILE.md.

window.T = {
  // Surfaces
  bg: '#000000',
  glass: 'rgba(18,18,20,0.58)',
  glassDense: 'rgba(18,18,20,0.78)',
  glassBorder: 'rgba(255,255,255,0.09)',
  nested: 'rgba(255,255,255,0.04)',
  nestedBorder: 'rgba(255,255,255,0.08)',
  surfaceHover: 'rgba(255,255,255,0.05)',
  surfaceActive: 'rgba(255,255,255,0.08)',
  surfaceInput: 'rgba(255,255,255,0.04)',
  line: 'rgba(255,255,255,0.10)',
  lineSoft: 'rgba(255,255,255,0.06)',
  fillNeutral: 'rgba(255,255,255,0.14)',
  fillNeutralDim: 'rgba(255,255,255,0.06)',

  // Text
  text: '#EDEDED',
  text2: '#B5B5B5',
  text3: '#8A8A8A',
  textMute: '#6A6A6A',

  // Accent (CTA + focus only — and card-4 forecast bars)
  accent: '#6F94B0',
  accentHover: '#7FA3BD',
  accentMuted: 'rgba(111,148,176,0.15)',

  // Earth tones
  olive: '#9DB582',
  tan: '#C4A868',
  rose: '#B58289',
  brick: '#93321A',
  oliveSoft: 'rgba(157,181,130,0.12)',
  oliveLine: 'rgba(157,181,130,0.30)',
  tanSoft: 'rgba(196,168,104,0.12)',
  tanLine: 'rgba(196,168,104,0.30)',
  roseSoft: 'rgba(181,130,137,0.12)',
  roseLine: 'rgba(181,130,137,0.30)',
  brickLine: 'rgba(147,50,26,0.50)',

  // Financial ramp
  finReceivables: '#D4A574',
  finOverdue: '#93321A',

  // Mobile brighter (status-tag outdoor-glare)
  oliveM: '#B5C998',
  tanM:   '#DBC07F',
  roseM:  '#C99AA1',

  // Fonts
  cake: '"Cake Mono", Mohave, system-ui, sans-serif',
  mono: '"JetBrains Mono", ui-monospace, "SF Mono", Menlo, monospace',
  mohave: 'Mohave, system-ui, sans-serif',

  // Radii (mobile)
  rL1: 10, rL2: 6, rBtn: 5, rChip: 4, rBar: 2, rPill: 12,

  // Spacing
  canvasX: 20, cardInset: 16, cardInsetTight: 12,
  sectionGap: 24, cardGap: 8,

  // Motion
  ease: 'cubic-bezier(0.22, 1, 0.36, 1)',
  dHover: 150, dPanel: 200, dPage: 250, dStag: 300, dCount: 800,

  // Viewport
  W: 390, H: 844,
};

// Mono number style helper
window.tnum = { fontFeatureSettings: '"tnum" 1, "zero" 1', fontVariantNumeric: 'tabular-nums slashed-zero' };
