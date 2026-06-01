// frame.jsx — iOS device frame + status bar + nav bar (// BOOKS header) + tab bar
// Used by every direction. Pure presentational chrome, no state.

// ─── Lucide-style stroke icons (1.5px stroke) ───────────────────
const SearchIcon = ({ size = 18 }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none"
    stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
    <circle cx="11" cy="11" r="7"/><line x1="20" y1="20" x2="16.65" y2="16.65"/>
  </svg>
);
const FlagIcon = ({ size = 18 }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none"
    stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
    <path d="M4 21V4a1 1 0 0 1 1-1h13l-2 4 2 4H5"/>
  </svg>
);
const ChevronDown = ({ size = 10, w = 1.8 }) => (
  <svg width={size} height={size * 0.7} viewBox="0 0 10 7" fill="none"
    stroke="currentColor" strokeWidth={w} strokeLinecap="round" strokeLinejoin="round">
    <path d="M1 1.5l4 4 4-4"/>
  </svg>
);
const Check = ({ size = 12 }) => (
  <svg width={size} height={size} viewBox="0 0 12 12" fill="none"
    stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
    <path d="M2 6.5l2.5 2.5L10 3.5"/>
  </svg>
);
const HomeIcon = ({ size = 18 }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none"
    stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
    <path d="M3 11l9-8 9 8v10a1 1 0 0 1-1 1h-5v-7h-6v7H4a1 1 0 0 1-1-1V11z"/>
  </svg>
);
const BooksIcon = ({ size = 18 }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none"
    stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
    <path d="M4 4h5a3 3 0 0 1 3 3v13a2 2 0 0 0-2-2H4V4zM20 4h-5a3 3 0 0 0-3 3v13a2 2 0 0 1 2-2h6V4z"/>
  </svg>
);
const JobsIcon = ({ size = 18 }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none"
    stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
    <rect x="3" y="6" width="18" height="14" rx="1"/>
    <path d="M8 6V4a1 1 0 0 1 1-1h6a1 1 0 0 1 1 1v2"/>
    <line x1="3" y1="12" x2="21" y2="12"/>
  </svg>
);
const CalIcon = ({ size = 18 }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none"
    stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
    <rect x="3" y="5" width="18" height="16" rx="1"/>
    <line x1="3" y1="10" x2="21" y2="10"/>
    <line x1="8" y1="3" x2="8" y2="7"/>
    <line x1="16" y1="3" x2="16" y2="7"/>
  </svg>
);
const GearIcon = ({ size = 18 }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none"
    stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
    <circle cx="12" cy="12" r="3"/>
    <path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 0 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 0 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3 1.7 1.7 0 0 0 1-1.5V3a2 2 0 0 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8 1.7 1.7 0 0 0 1.5 1H21a2 2 0 0 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/>
  </svg>
);
const Arrow = ({ dir = 'right', size = 10 }) => {
  const d = dir === 'right' ? 'M1 5h8M6 1l3 4-3 4'
          : dir === 'down'  ? 'M5 1v8M1 6l4 3 4-3'
          : dir === 'up'    ? 'M5 9V1M1 4l4-3 4 3'
                            : 'M9 5H1M4 1L1 5l3 4';
  return (
    <svg width={size} height={size} viewBox="0 0 10 10" fill="none"
      stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round">
      <path d={d}/>
    </svg>
  );
};

// ─── iOS device frame ──────────────────────────────────
// At scale=1, outer container is (W+12) × (H+12) = 402 × 856 (bezel pad).
// DCArtboards should be sized to match.
function IOSFrame({ children, label, sublabel, scale = 1 }) {
  const W = T.W, H = T.H;
  return (
    <div style={{ position: 'relative', flexShrink: 0, color: T.text }}>
      {label && (
        <div style={{
          position: 'absolute', bottom: '100%', left: 0, paddingBottom: 14,
          fontFamily: T.mono, fontSize: 10, color: 'rgba(255,255,255,0.55)',
          letterSpacing: '0.18em', textTransform: 'uppercase', whiteSpace: 'nowrap',
        }}>
          <span style={{ color: T.textMute }}>// </span>{label}
          {sublabel && <span style={{ color: T.textMute, marginLeft: 10 }}>{sublabel}</span>}
        </div>
      )}
      <div style={{
        width: W * scale + 12, height: H * scale + 12,
        borderRadius: 56 * scale, background: '#0c0c0d', padding: 6,
        boxShadow: '0 0 0 1px #1f1f21, 0 30px 60px rgba(0,0,0,0.55)',
      }}>
        <div style={{
          width: W * scale, height: H * scale, borderRadius: 50 * scale,
          overflow: 'hidden', position: 'relative', background: '#000',
        }}>
          {/* Dynamic island */}
          <div style={{
            position: 'absolute', top: 11 * scale, left: '50%', transform: 'translateX(-50%)',
            width: 122 * scale, height: 36 * scale, borderRadius: 22 * scale,
            background: '#000', zIndex: 100,
          }}/>
          {/* Scaled content stage */}
          <div style={{
            position: 'absolute', inset: 0,
            transform: `scale(${scale})`, transformOrigin: 'top left',
            width: W, height: H,
          }}>
            {children}
          </div>
          {/* Home indicator */}
          <div style={{
            position: 'absolute', bottom: 7 * scale, left: 0, right: 0, zIndex: 110,
            display: 'flex', justifyContent: 'center', pointerEvents: 'none',
          }}>
            <div style={{ width: 134 * scale, height: 5 * scale, borderRadius: 100, background: 'rgba(255,255,255,0.35)' }}/>
          </div>
        </div>
      </div>
    </div>
  );
}

// ─── iOS status bar (top 59pt) ─────────────────────────
function StatusBar({ time = '9:41' }) {
  return (
    <div style={{
      position: 'relative', height: 59,
      display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between',
      padding: '0 28px 12px',
      fontFamily: '-apple-system, "SF Pro Text", system-ui',
      fontSize: 15, fontWeight: 600, color: T.text, letterSpacing: '-0.01em',
      zIndex: 50,
    }}>
      <span>{time}</span>
      <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
        {/* Signal */}
        <svg width="16" height="11" viewBox="0 0 16 11" fill="none">
          <rect x="0"  y="7" width="3" height="4" rx="0.6" fill={T.text}/>
          <rect x="4"  y="5" width="3" height="6" rx="0.6" fill={T.text}/>
          <rect x="8"  y="3" width="3" height="8" rx="0.6" fill={T.text}/>
          <rect x="12" y="0" width="3" height="11" rx="0.6" fill={T.text}/>
        </svg>
        {/* Wifi */}
        <svg width="15" height="11" viewBox="0 0 15 11" fill="none">
          <path d="M7.5 9.5a1 1 0 1 1 0 .01M2 5.6a8 8 0 0 1 11 0M4.4 8a4.7 4.7 0 0 1 6.2 0" stroke={T.text} strokeWidth="1.4" strokeLinecap="round"/>
        </svg>
        {/* Battery */}
        <svg width="25" height="11" viewBox="0 0 25 11" fill="none">
          <rect x="0.5" y="0.5" width="21" height="10" rx="2.5" stroke={T.text} strokeOpacity="0.4"/>
          <rect x="2" y="2" width="18" height="7" rx="1.2" fill={T.text}/>
          <rect x="22.5" y="3.5" width="1.5" height="4" rx="0.6" fill={T.text} fillOpacity="0.4"/>
        </svg>
      </div>
    </div>
  );
}

// ─── AppHeader: // BOOKS title + actions (stylized placeholder) ──
function AppHeader({ title = 'BOOKS', actions = ['search'], compact = false, scrolled = false }) {
  const titleSize = compact ? 22 : 28;
  return (
    <div style={{
      position: 'relative',
      padding: `${compact ? 4 : 6}px 20px ${compact ? 10 : 14}px`,
      background: scrolled ? 'rgba(10,10,10,0.80)' : 'transparent',
      backdropFilter: scrolled ? 'blur(28px) saturate(1.3)' : 'none',
      WebkitBackdropFilter: scrolled ? 'blur(28px) saturate(1.3)' : 'none',
      borderBottom: scrolled ? `1px solid ${T.line}` : '1px solid transparent',
      transition: `all ${T.dHover}ms ${T.ease}`,
      zIndex: 40,
    }}>
      <div style={{ display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between' }}>
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 8 }}>
          <span style={{
            fontFamily: T.mono, fontSize: 14, color: T.textMute,
            letterSpacing: '0.02em',
          }}>//</span>
          <h1 style={{
            margin: 0, fontFamily: T.cake, fontWeight: 300, fontSize: titleSize,
            color: T.text, textTransform: 'uppercase', letterSpacing: '0em',
            lineHeight: 1,
          }}>{title}</h1>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 14, color: T.text2 }}>
          {actions.includes('search') && <SearchIcon size={18}/>}
          {actions.includes('flag')   && <FlagIcon size={18}/>}
        </div>
      </div>
    </div>
  );
}

// ─── iOS Tab bar (49pt content + 34pt safe area = 83pt) ─────────
function TabBar({ active = 'books' }) {
  const tabs = [
    { id: 'home',     label: 'HOME',     Icon: HomeIcon  },
    { id: 'books',    label: 'BOOKS',    Icon: BooksIcon },
    { id: 'pipeline', label: 'PIPELINE', Icon: JobsIcon  },
    { id: 'jobs',     label: 'JOBS',     Icon: CalIcon   },
    { id: 'settings', label: 'SETTINGS', Icon: GearIcon  },
  ];
  return (
    <div style={{
      position: 'absolute', bottom: 0, left: 0, right: 0, zIndex: 50,
      paddingTop: 10, paddingBottom: 34, paddingLeft: 8, paddingRight: 8,
      background: 'rgba(10,10,10,0.80)',
      backdropFilter: 'blur(28px) saturate(1.3)',
      WebkitBackdropFilter: 'blur(28px) saturate(1.3)',
      borderTop: `1px solid rgba(255,255,255,0.08)`,
    }}>
      <div style={{ display: 'flex', justifyContent: 'space-between' }}>
        {tabs.map(t => {
          const isActive = t.id === active;
          const c = isActive ? T.text : T.textMute;
          return (
            <div key={t.id} style={{
              flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4,
              padding: '4px 0', color: c,
            }}>
              <t.Icon size={18}/>
              <span style={{
                fontFamily: T.mono, fontSize: 9, color: c,
                letterSpacing: '0.14em', textTransform: 'uppercase',
              }}>{t.label}</span>
            </div>
          );
        })}
      </div>
    </div>
  );
}

// Make components globally available for other Babel scripts
Object.assign(window, {
  IOSFrame, StatusBar, AppHeader, TabBar,
  SearchIcon, FlagIcon, ChevronDown, Check, Arrow,
  HomeIcon, BooksIcon, JobsIcon, CalIcon, GearIcon,
});
