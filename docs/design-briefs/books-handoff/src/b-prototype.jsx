// b-prototype.jsx — Direction B as a fully interactive prototype.
// Real horizontal swipe carousel, working period menu, segment switching,
// scroll-to-collapse, tile drills, A/R sheet rise. Reduced-motion aware.
//
// Reuses BCard_PL/Flow/AR/Forecast/Jobs, BTile, ATag, etc. from earlier files.

const { useState, useRef, useEffect, useCallback } = React;

// Reduced motion hook
function useReducedMotion() {
  const [r, setR] = useState(() =>
    typeof window !== 'undefined' && window.matchMedia?.('(prefers-reduced-motion: reduce)').matches
  );
  useEffect(() => {
    const mq = window.matchMedia?.('(prefers-reduced-motion: reduce)');
    if (!mq) return;
    const h = e => setR(e.matches);
    mq.addEventListener?.('change', h);
    return () => mq.removeEventListener?.('change', h);
  }, []);
  return r;
}

// ─── Interactive period pill ─────────────────────────────
function PeriodPillLive({ period, onOpen, open }) {
  return (
    <button
      onClick={onOpen}
      style={{
        display: 'inline-flex', alignItems: 'center', gap: 8,
        padding: '10px 14px', minHeight: 44, borderRadius: T.rPill,
        border: `1px solid ${open ? 'rgba(255,255,255,0.20)' : T.line}`,
        background: open ? T.surfaceActive : T.surfaceInput,
        fontFamily: T.mono, fontSize: 11, fontWeight: 500, color: T.text,
        letterSpacing: '0.14em', textTransform: 'uppercase', ...tnum,
        cursor: 'pointer',
        transition: `background ${T.dHover}ms ${T.ease}, border-color ${T.dHover}ms ${T.ease}, transform 100ms ${T.ease}`,
      }}
      onTouchStart={e => e.currentTarget.style.transform = 'scale(0.97)'}
      onTouchEnd={e => e.currentTarget.style.transform = 'scale(1)'}
    >
      {period.label}
      <span style={{
        display: 'inline-block',
        transition: `transform ${T.dPanel}ms ${T.ease}`,
        transform: open ? 'rotate(180deg)' : 'rotate(0)',
      }}>
        <ChevronDown size={9}/>
      </span>
    </button>
  );
}

// ─── Inline header (live) ────────────────────────────────
function BHeaderLive({ label, scopeHint, scopeColor, period, onPeriodOpen, periodOpen }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      padding: '12px 20px 0', minHeight: 44,
    }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
        <span style={{
          fontFamily: T.mono, fontSize: 11, fontWeight: 600, color: T.text,
          letterSpacing: '0.16em', textTransform: 'uppercase',
          transition: `color ${T.dPanel}ms ${T.ease}`,
        }}>{label}</span>
        {scopeHint && (
          <span style={{
            display: 'inline-flex', alignItems: 'center',
            padding: '3px 7px', borderRadius: T.rChip,
            background: scopeColor === T.rose ? 'rgba(181,130,137,0.32)' : T.accentMuted,
            border: `1px solid ${scopeColor === T.rose ? 'rgba(181,130,137,0.88)' : 'rgba(111,148,176,0.45)'}`,
            fontFamily: T.mono, fontSize: 9, color: scopeColor === T.rose ? T.roseM : T.accent,
            letterSpacing: '0.16em', textTransform: 'uppercase', fontWeight: 600,
          }}>{scopeHint}</span>
        )}
      </div>
      <PeriodPillLive period={period} onOpen={onPeriodOpen} open={periodOpen}/>
    </div>
  );
}

// ─── Interactive dots ────────────────────────────────────
function BDotsLive({ index, total, onTap }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6,
      padding: '20px 20px 0', minHeight: 40,
    }}>
      {Array.from({ length: total }).map((_, i) => (
        <button key={i}
          onClick={() => onTap(i)}
          aria-label={`Card ${i + 1} of ${total}`}
          style={{
            width: i === index ? 22 : 6, height: 6, borderRadius: 99,
            background: i === index ? T.text : T.textMute,
            opacity: i === index ? 1 : 0.5,
            transition: `width ${T.dPanel}ms ${T.ease}, opacity ${T.dPanel}ms ${T.ease}`,
            border: 'none', padding: 0, cursor: 'pointer',
            outline: 'none', position: 'relative',
          }}
        >
          {/* 44pt touch target via invisible inset */}
          <span style={{ position: 'absolute', inset: '-19px -8px', borderRadius: 99 }}/>
        </button>
      ))}
    </div>
  );
}

// ─── Interactive segmented control ───────────────────────
function BSegmentsLive({ active, onChange, options = ['INVOICES', 'ESTIMATES', 'EXPENSES'] }) {
  return (
    <div style={{ padding: '0 20px' }}>
      <div style={{
        display: 'flex', padding: 3, borderRadius: T.rBtn,
        background: 'rgba(255,255,255,0.03)', border: `1px solid ${T.line}`,
        gap: 2, position: 'relative',
      }}>
        {options.map(opt => {
          const isActive = opt === active;
          return (
            <button key={opt}
              onClick={() => onChange(opt)}
              style={{
                flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center',
                padding: '10px 0', borderRadius: 3, minHeight: 44,
                background: isActive ? 'rgba(255,255,255,0.10)' : 'transparent',
                border: `1px solid ${isActive ? 'rgba(255,255,255,0.22)' : 'transparent'}`,
                boxShadow: isActive ? 'inset 0 1px 0 rgba(255,255,255,0.06)' : 'none',
                cursor: 'pointer',
                transition: `background ${T.dHover}ms ${T.ease}, border-color ${T.dHover}ms ${T.ease}`,
              }}
            >
              <span style={{
                fontFamily: T.mono, fontSize: 10.5, fontWeight: 500,
                color: isActive ? T.text : T.text3,
                letterSpacing: '0.16em', textTransform: 'uppercase',
                transition: `color ${T.dHover}ms ${T.ease}`,
              }}>{opt}</span>
            </button>
          );
        })}
      </div>
    </div>
  );
}

// ─── Card switcher (returns the card to render for an index) ──
function CardForIndex({ index, onDrillOutstanding, onDrillForecast, onDrillTopChase, onDrillDays, onDrillCloseRate, onDrillStale, onDrillProfitable, onDrillLosers }) {
  switch (index) {
    case 0: return <BCard_PL       data={SEED.pl}       onDrillOutstanding={onDrillOutstanding} onDrillForecast={onDrillForecast}/>;
    case 1: return <BCard_Flow     data={SEED.cashflow} onDrillDays={onDrillDays}/>;
    case 2: return <BCard_AR       data={SEED.ar}       onDrillTopChase={onDrillTopChase}/>;
    case 3: return <BCard_Forecast data={SEED.forecast} onDrillCloseRate={onDrillCloseRate} onDrillStale={onDrillStale}/>;
    case 4: return <BCard_Jobs     data={SEED.jobs}     onDrillProfitable={onDrillProfitable} onDrillLosers={onDrillLosers}/>;
  }
}

// ─── List rows for a segment (with optional filter) ──────
function listRowsForSegment(segment, filter) {
  let rows = segment === 'INVOICES' ? [
    { primary: 'Verity Projects',    secondary: 'INV-00284 · 71D OVERDUE', amount: '$6,400',  tag: 'OVERDUE', tone: 'rose',    state: 'overdue' },
    { primary: 'Halcyon Builders',   secondary: 'INV-00301 · 94D OVERDUE', amount: '$3,400',  tag: 'OVERDUE', tone: 'rose',    state: 'overdue' },
    { primary: 'Mara Lin',           secondary: 'INV-00298 · 42D OVERDUE', amount: '$3,200',  tag: 'OVERDUE', tone: 'rose',    state: 'overdue' },
    { primary: 'Joel Lioudakis',     secondary: 'INV-00276 · DUE IN 6D',   amount: '$2,200',  tag: 'OPEN',    tone: 'neutral', state: 'open' },
    { primary: 'Dave Bernard',       secondary: 'INV-00292 · 24D OVERDUE', amount: '$600',    tag: 'OVERDUE', tone: 'rose',    state: 'overdue' },
    { primary: 'Scagliati Homes',    secondary: 'INV-00271 · PAID',        amount: '$8,400',  tag: 'PAID',    tone: 'olive',   state: 'paid' },
  ] : segment === 'ESTIMATES' ? [
    { primary: 'Scagliati Homes',    secondary: 'EST-00112 · SENT 3D AGO', amount: '$12,800', tag: 'SENT',    tone: 'tan',     state: 'sent' },
    { primary: 'Citygate Residence', secondary: 'EST-00109 · VIEWED',      amount: '$18,400', tag: 'VIEWED',  tone: 'olive',   state: 'viewed' },
    { primary: 'Dave Bernard',       secondary: 'EST-00108 · DRAFT',       amount: '$4,200',  tag: 'DRAFT',   tone: 'neutral', state: 'draft' },
    { primary: 'M Free',             secondary: 'EST-00107 · EXPIRED',     amount: '$3,500',  tag: 'EXPIRED', tone: 'rose',    state: 'expired' },
    { primary: 'Halcyon Builders',   secondary: 'EST-00106 · SENT 8D AGO', amount: '$22,400', tag: 'SENT',    tone: 'tan',     state: 'sent' },
  ] : [
    { primary: 'Fuel — Esso',           secondary: '2026-05-14 · TRUCK 03',   amount: '$84',    tag: 'OK',       tone: 'neutral', state: 'ok' },
    { primary: 'Materials — Home Depot', secondary: '2026-05-13 · OAK GROVE', amount: '$412',   tag: 'OK',       tone: 'neutral', state: 'ok' },
    { primary: 'Subcontractor — Lin',   secondary: '2026-05-12 · PERRY ST',   amount: '$1,840', tag: 'PENDING',  tone: 'tan',     state: 'pending' },
    { primary: 'Equipment — rent',      secondary: '2026-05-11 · SHARED',     amount: '$220',   tag: 'OK',       tone: 'neutral', state: 'ok' },
    { primary: 'Sub — Patel',           secondary: '2026-05-10 · MILL POND',  amount: '$680',   tag: 'PENDING',  tone: 'tan',     state: 'pending' },
  ];

  if (filter === 'OVERDUE')  rows = rows.filter(r => r.state === 'overdue');
  if (filter === 'SENT')     rows = rows.filter(r => r.state === 'sent' || r.state === 'viewed');
  if (filter === 'PENDING')  rows = rows.filter(r => r.state === 'pending');

  return rows;
}

// ─── List preview (live, filters reactive) ───────────────
function BListLive({ segment, filter, onClearFilter }) {
  const rows = listRowsForSegment(segment, filter);
  return (
    <div style={{ padding: '12px 20px 16px' }}>
      {filter && (
        <div style={{ marginBottom: 10, display: 'flex', alignItems: 'center', gap: 8 }}>
          <button
            onClick={onClearFilter}
            style={{
              display: 'inline-flex', alignItems: 'center', gap: 6,
              padding: '6px 10px', borderRadius: T.rChip,
              border: `1px solid ${filter === 'OVERDUE' ? T.rose : T.line}`,
              background: filter === 'OVERDUE' ? T.roseSoft : T.surfaceActive,
              fontFamily: T.mono, fontSize: 10,
              color: filter === 'OVERDUE' ? T.roseM : T.text, fontWeight: 600,
              letterSpacing: '0.14em', textTransform: 'uppercase',
              cursor: 'pointer', minHeight: 32,
              transition: `background ${T.dHover}ms ${T.ease}`,
            }}
          >
            {filter}
            <span style={{ color: filter === 'OVERDUE' ? T.rose : T.textMute, opacity: 0.7 }}>×</span>
          </button>
          <span style={{ marginLeft: 'auto',
            fontFamily: T.mono, fontSize: 10, color: T.text3, ...tnum, letterSpacing: '0.12em',
          }}>{rows.length} {rows.length === 1 ? 'RESULT' : 'RESULTS'}</span>
        </div>
      )}

      {rows.length === 0 ? (
        <div style={{ padding: '32px 0', textAlign: 'center' }}>
          <span style={{
            display: 'block', fontFamily: T.mohave, fontWeight: 300, fontSize: 28, color: T.text3, ...tnum,
          }}>—</span>
          <span style={{
            display: 'block', marginTop: 6,
            fontFamily: T.mono, fontSize: 10, color: T.textMute,
            letterSpacing: '0.20em', textTransform: 'uppercase',
          }}>// NO MATCH</span>
        </div>
      ) : (
        <div style={{
          background: T.glass, backdropFilter: 'blur(28px) saturate(1.3)',
          WebkitBackdropFilter: 'blur(28px) saturate(1.3)',
          border: `1px solid ${T.glassBorder}`, borderRadius: T.rL1, overflow: 'hidden',
          position: 'relative',
        }}>
          <div style={{
            position: 'absolute', inset: 0, pointerEvents: 'none', borderRadius: 'inherit',
            background: 'linear-gradient(180deg, rgba(255,255,255,0.04), transparent 40%)',
          }}/>
          {rows.map((r, i) => (
            <div key={i} style={{
              display: 'flex', alignItems: 'center', justifyContent: 'space-between',
              padding: '14px 16px', borderBottom: i < rows.length - 1 ? `1px solid ${T.line}` : 'none',
              position: 'relative', cursor: 'pointer', minHeight: 56,
              transition: `background ${T.dHover}ms ${T.ease}`,
            }}
            onTouchStart={e => e.currentTarget.style.background = T.surfaceHover}
            onTouchEnd={e => e.currentTarget.style.background = 'transparent'}
            onMouseEnter={e => e.currentTarget.style.background = T.surfaceHover}
            onMouseLeave={e => e.currentTarget.style.background = 'transparent'}
            >
              <div style={{ display: 'flex', flexDirection: 'column', gap: 4, minWidth: 0, flex: 1 }}>
                <span style={{
                  fontFamily: T.mohave, fontSize: 15, fontWeight: 500, color: T.text,
                  whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
                }}>{r.primary}</span>
                <span style={{
                  fontFamily: T.mono, fontSize: 10, color: T.text3,
                  letterSpacing: '0.10em', textTransform: 'uppercase',
                }}>{r.secondary}</span>
              </div>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 4, alignItems: 'flex-end' }}>
                <span style={{
                  fontFamily: T.mono, fontSize: 13, fontWeight: 500, color: T.text, ...tnum,
                }}>{r.amount}</span>
                <ATag tone={r.tone}>{r.tag}</ATag>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

// ─── Drill-tile interceptors. We monkey-patch BTile clicks by wrapping. ──
// Simpler: pass click handlers into card-aware wrappers.
// (Click handlers are now passed natively via card props — see direction-b.jsx tiles.)
// CardWithDrills/DrillOverlay/DrillZone removed; CardForIndex is enough.

// ─── Period menu (modal, with backdrop) ─────────────────
function PeriodMenu({ current, options, onSelect, onDismiss }) {
  const reduce = useReducedMotion();
  return (
    <>
      <div
        onClick={onDismiss}
        style={{
          position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.50)', zIndex: 60,
          animation: reduce ? 'none' : `bp-fade ${T.dPanel}ms ${T.ease}`,
        }}
      />
      <div style={{
        position: 'absolute', top: 138, right: 20, zIndex: 70,
        minWidth: 200,
        background: T.glassDense, backdropFilter: 'blur(28px) saturate(1.3)',
        WebkitBackdropFilter: 'blur(28px) saturate(1.3)',
        border: `1px solid ${T.glassBorder}`, borderRadius: T.rL1, overflow: 'hidden',
        animation: reduce ? 'none' : `bp-menu-in ${T.dPanel}ms ${T.ease}`,
        transformOrigin: 'top right',
      }}>
        <div style={{
          position: 'absolute', inset: 0, pointerEvents: 'none', borderRadius: 'inherit',
          background: 'linear-gradient(180deg, rgba(255,255,255,0.03), transparent 35%)',
        }}/>
        {options.map((p, i) => {
          const isActive = p.token === current.token;
          return (
            <button key={p.token}
              onClick={() => onSelect(p)}
              style={{
                width: '100%', padding: '14px 16px', position: 'relative',
                borderBottom: i < options.length - 1 ? `1px solid ${T.line}` : 'none',
                display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 12,
                background: isActive ? T.surfaceHover : 'transparent',
                border: 'none', borderRadius: 0, cursor: 'pointer', minHeight: 44,
                transition: `background ${T.dHover}ms ${T.ease}`,
              }}
              onTouchStart={e => e.currentTarget.style.background = T.surfaceActive}
              onTouchEnd={e => e.currentTarget.style.background = isActive ? T.surfaceHover : 'transparent'}
            >
              <span style={{
                fontFamily: T.mono, fontSize: 12, fontWeight: isActive ? 600 : 500,
                color: isActive ? T.text : T.text2,
                letterSpacing: '0.14em', textTransform: 'uppercase',
              }}>{p.label}</span>
              {isActive && <span style={{ color: T.text }}><Check size={14}/></span>}
            </button>
          );
        })}
      </div>
    </>
  );
}

// ─── A/R sheet (bottom-rise) ────────────────────────────
function ARSheet({ onDismiss }) {
  const reduce = useReducedMotion();
  return (
    <>
      <div
        onClick={onDismiss}
        style={{
          position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.50)', zIndex: 60,
          animation: reduce ? 'none' : `bp-fade ${T.dPanel}ms ${T.ease}`,
        }}
      />
      <div style={{
        position: 'absolute', bottom: 0, left: 0, right: 0, zIndex: 70,
        height: '62%',
        background: 'rgba(10,10,10,0.95)',
        backdropFilter: 'blur(28px) saturate(1.3)',
        WebkitBackdropFilter: 'blur(28px) saturate(1.3)',
        borderTopLeftRadius: 12, borderTopRightRadius: 12,
        borderTop: `1px solid ${T.line}`,
        display: 'flex', flexDirection: 'column',
        animation: reduce ? 'none' : `bp-rise ${T.dPage}ms ${T.ease}`,
      }}>
        <div style={{ display: 'flex', justifyContent: 'center', paddingTop: 8 }}>
          <button
            onClick={onDismiss}
            aria-label="Dismiss"
            style={{
              width: 60, height: 16, display: 'flex', alignItems: 'center', justifyContent: 'center',
              background: 'transparent', border: 'none', cursor: 'pointer',
            }}>
            <div style={{ width: 36, height: 5, borderRadius: 99, background: 'rgba(255,255,255,0.30)' }}/>
          </button>
        </div>
        <div style={{ padding: '20px 20px 12px', borderBottom: `1px solid ${T.line}` }}>
          <span style={{
            fontFamily: T.mono, fontSize: 11, color: T.textMute,
            letterSpacing: '0.18em', textTransform: 'uppercase',
          }}>// CHASE LIST</span>
          <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', marginTop: 4 }}>
            <span style={{
              fontFamily: T.cake, fontWeight: 300, fontSize: 22, color: T.text,
              letterSpacing: '0.02em', textTransform: 'uppercase',
            }}>OPEN INVOICES</span>
            <span style={{
              fontFamily: T.mono, fontSize: 12, fontWeight: 600, color: T.rose, ...tnum,
              letterSpacing: '0.12em',
            }}>{fmt$(SEED.ar.total)}</span>
          </div>
        </div>
        <div style={{ flex: 1, overflowY: 'auto', overflowX: 'hidden' }}>
          {SEED.ar.chaseList.map((r, i, arr) => (
            <div key={i} style={{
              display: 'flex', alignItems: 'center', justifyContent: 'space-between',
              padding: '14px 20px', minHeight: 56,
              borderBottom: i < arr.length - 1 ? `1px solid ${T.line}` : 'none',
              cursor: 'pointer',
              transition: `background ${T.dHover}ms ${T.ease}`,
            }}
            onMouseEnter={e => e.currentTarget.style.background = T.surfaceHover}
            onMouseLeave={e => e.currentTarget.style.background = 'transparent'}
            >
              <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
                <span style={{ fontFamily: T.mohave, fontSize: 15, fontWeight: 500, color: T.text }}>{r.client}</span>
                <span style={{
                  fontFamily: T.mono, fontSize: 10, color: T.text3,
                  letterSpacing: '0.10em', textTransform: 'uppercase', ...tnum,
                }}>{r.invoice} · {r.days}D{r.days > 30 ? ' OVERDUE' : ''}</span>
              </div>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 4, alignItems: 'flex-end' }}>
                <span style={{
                  fontFamily: T.mono, fontSize: 14, fontWeight: 500, ...tnum,
                  color: r.days > 60 ? T.rose : T.text,
                }}>{fmt$(r.amount)}</span>
                {r.days > 60 ? <ATag tone="rose">OVERDUE</ATag>
                  : r.days > 30 ? <ATag tone="tan">DUE</ATag>
                  : <ATag tone="neutral">OPEN</ATag>}
              </div>
            </div>
          ))}
        </div>
      </div>
    </>
  );
}

// ─── Collapsed strip (live, follows activeCard + period) ──
function CollapsedStripLive({ activeIndex, total, primary, arValue }) {
  const labels = ['NET · 6M', 'FLOW · 6M', 'A/R OPEN', 'FORECAST', 'JOBS NET'];
  return (
    <div style={{
      padding: '10px 20px', borderBottom: `1px solid ${T.line}`,
      display: 'flex', alignItems: 'center', gap: 14,
      background: 'rgba(10,10,10,0.85)',
      backdropFilter: 'blur(28px) saturate(1.3)',
      WebkitBackdropFilter: 'blur(28px) saturate(1.3)',
    }}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0 }}>
        <span style={{
          fontFamily: T.mono, fontSize: 9, color: T.text3,
          letterSpacing: '0.18em', textTransform: 'uppercase',
        }}>{labels[activeIndex]}</span>
        <span style={{
          fontFamily: T.mono, fontSize: 15, fontWeight: 600, color: T.text, ...tnum,
          letterSpacing: '-0.01em',
        }}>{primary}</span>
      </div>
      <div style={{ flex: 1 }}/>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 2, alignItems: 'flex-end' }}>
        <span style={{
          fontFamily: T.mono, fontSize: 9, color: T.text3,
          letterSpacing: '0.18em', textTransform: 'uppercase',
        }}>A/R</span>
        <span style={{
          fontFamily: T.mono, fontSize: 15, fontWeight: 600, color: T.rose, ...tnum,
        }}>{arValue}</span>
      </div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 4, marginLeft: 8 }}>
        {Array.from({ length: total }).map((_, i) => (
          <div key={i} style={{
            width: i === activeIndex ? 12 : 4, height: 4, borderRadius: 99,
            background: i === activeIndex ? T.text : T.textMute,
            transition: `width ${T.dPanel}ms ${T.ease}`,
          }}/>
        ))}
      </div>
    </div>
  );
}

// ═══════════════════════════════════════════════════════
// MAIN PROTOTYPE
// ═══════════════════════════════════════════════════════
function BPrototype() {
  const [activeCard, setActiveCard] = useState(0);
  const [period, setPeriod] = useState(SEED.period);
  const [segment, setSegment] = useState('INVOICES');
  const [filter, setFilter] = useState(null);
  const [periodMenuOpen, setPeriodMenuOpen] = useState(false);
  const [arSheetOpen, setArSheetOpen] = useState(false);
  const [scrolled, setScrolled] = useState(false);

  const carouselRef = useRef(null);
  const scrollRef = useRef(null);
  const reduce = useReducedMotion();

  // Track carousel scroll position → update activeCard
  const onCarouselScroll = useCallback(() => {
    if (!carouselRef.current) return;
    const el = carouselRef.current;
    const cardWidth = el.clientWidth;
    if (cardWidth === 0) return;
    const idx = Math.round(el.scrollLeft / cardWidth);
    if (idx !== activeCard && idx >= 0 && idx < 5) setActiveCard(idx);
  }, [activeCard]);

  // Programmatic carousel snap when dot tapped
  const snapTo = useCallback((i) => {
    if (!carouselRef.current) return;
    const el = carouselRef.current;
    el.scrollTo({ left: i * el.clientWidth, behavior: reduce ? 'instant' : 'smooth' });
  }, [reduce]);

  // Track vertical scroll → collapse hero
  const onVerticalScroll = useCallback(() => {
    if (!scrollRef.current) return;
    const y = scrollRef.current.scrollTop;
    const shouldCollapse = y > 80;
    if (shouldCollapse !== scrolled) setScrolled(shouldCollapse);
  }, [scrolled]);

  // Card meta
  const cardIds = ['P&L', 'CASH FLOW', 'A/R AGING', 'FORECAST', 'JOBS'];
  const scope = activeCard === 2 ? { hint: 'ALL OPEN',  color: T.rose }
              : activeCard === 3 ? { hint: 'ACTIVE',    color: T.accent }
                                 : null;

  // Primary metric for the collapsed strip
  const primaryVal =
    activeCard === 0 ? fmt$(SEED.pl.netCash)
  : activeCard === 1 ? fmt$(SEED.cashflow.netCash)
  : activeCard === 2 ? fmt$(SEED.ar.total)
  : activeCard === 3 ? fmt$(SEED.forecast.weighted)
  :                    fmt$(SEED.jobs.list.reduce((s, j) => s + j.net, 0));

  // Drill handlers
  const drillOutstanding = () => { setSegment('INVOICES');  setFilter('OVERDUE');  };
  const drillForecast    = () => { setSegment('ESTIMATES'); setFilter('SENT');     };
  const drillTopChase    = () => { setArSheetOpen(true); };

  return (
    <div style={{ position: 'absolute', inset: 0, background: T.bg, overflow: 'hidden' }}>
      <style>{`
        @keyframes bp-fade { from { opacity: 0; } to { opacity: 1; } }
        @keyframes bp-menu-in {
          from { opacity: 0; transform: translateY(-8px) scale(0.96); }
          to   { opacity: 1; transform: translateY(0) scale(1); }
        }
        @keyframes bp-rise { from { transform: translateY(100%); } to { transform: translateY(0); } }
        .bp-carousel { scroll-snap-type: x mandatory; -webkit-overflow-scrolling: touch; }
        .bp-carousel::-webkit-scrollbar { display: none; }
        .bp-carousel { scrollbar-width: none; }
        .bp-card { scroll-snap-align: start; }
        .bp-scroll::-webkit-scrollbar { display: none; }
        .bp-scroll { scrollbar-width: none; }
        @media (prefers-reduced-motion: reduce) {
          * { animation-duration: 0.001s !important; transition-duration: 0.001s !important; }
        }
      `}</style>

      <div aria-hidden style={{
        position: 'absolute', inset: 0, pointerEvents: 'none',
        background: 'radial-gradient(500px 360px at 88% 10%, rgba(111,148,176,0.07), transparent 65%)',
      }}/>

      <StatusBar/>
      <AppHeader actions={['search', 'flag']} scrolled={scrolled} compact={scrolled}/>

      {/* Vertical scrolling region — everything below the header */}
      <div
        ref={scrollRef}
        onScroll={onVerticalScroll}
        className="bp-scroll"
        style={{
          position: 'absolute', top: scrolled ? 88 : 100, left: 0, right: 0, bottom: 83,
          overflowY: 'auto', overflowX: 'hidden',
          transition: `top ${T.dPanel}ms ${T.ease}`,
        }}>

        {/* Sticky-collapse zone: header + carousel, OR collapsed strip when scrolled */}
        {scrolled ? (
          <div style={{ position: 'sticky', top: 0, zIndex: 5 }}>
            <CollapsedStripLive
              activeIndex={activeCard} total={5}
              primary={primaryVal} arValue={fmt$(SEED.ar.total, { compact: true })}
            />
          </div>
        ) : (
          <>
            <BHeaderLive
              label={cardIds[activeCard]}
              scopeHint={scope?.hint}
              scopeColor={scope?.color}
              period={period}
              onPeriodOpen={() => setPeriodMenuOpen(true)}
              periodOpen={periodMenuOpen}
            />

            {/* Horizontal swipe carousel */}
            <div
              ref={carouselRef}
              onScroll={onCarouselScroll}
              className="bp-carousel"
              style={{
                marginTop: 8, display: 'flex', overflowX: 'auto', overflowY: 'hidden',
              }}>
              {[0,1,2,3,4].map(i => (
                <div key={i} className="bp-card" style={{
                  flex: '0 0 100%', width: T.W, minHeight: 360,
                }}>
                  <CardForIndex
                    index={i}
                    onDrillOutstanding={drillOutstanding}
                    onDrillForecast={drillForecast}
                    onDrillTopChase={drillTopChase}
                  />
                </div>
              ))}
            </div>

            <BDotsLive index={activeCard} total={5} onTap={snapTo}/>
          </>
        )}

        {/* Sticky segmented control */}
        <div style={{
          marginTop: scrolled ? 0 : 22,
          position: 'sticky', top: scrolled ? 60 : 0, zIndex: 4,
          background: T.bg,
          paddingTop: scrolled ? 4 : 0, paddingBottom: 4,
        }}>
          <BSegmentsLive active={segment} onChange={(s) => { setSegment(s); setFilter(null); }}/>
        </div>

        {/* List */}
        <BListLive segment={segment} filter={filter} onClearFilter={() => setFilter(null)}/>

        {/* Scroll padding so the last row clears the tab bar */}
        <div style={{ height: 40 }}/>
      </div>

      {/* Period menu */}
      {periodMenuOpen && (
        <PeriodMenu
          current={period}
          options={SEED.periods}
          onSelect={(p) => { setPeriod(p); setPeriodMenuOpen(false); }}
          onDismiss={() => setPeriodMenuOpen(false)}
        />
      )}

      {/* A/R sheet */}
      {arSheetOpen && <ARSheet onDismiss={() => setArSheetOpen(false)}/>}

      <TabBar active="books"/>
    </div>
  );
}

Object.assign(window, { BPrototype });
