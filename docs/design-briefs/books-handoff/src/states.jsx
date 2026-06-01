// states.jsx — Edge cases for the Books tab.
// Built on Direction B (Mission Deck) — the recommended direction.

// ═══════════════════════════════════════════════════════
// EMPTY / ZERO DATA  — per the design system, the number shows but is zero.
// No "no jobs yet!" copy. Just $0 / 0% / — and a tactical label.
// ═══════════════════════════════════════════════════════
const ZERO_SEED = {
  pl: { payments: 0, expenses: 0, netCash: 0, marginPct: 0, outstanding: 0, outstandingCount: 0, forecast: 0, forecastCount: 0 },
};

function EmptyPLCard() {
  return (
    <div style={{ padding: '20px 20px 0' }}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
        <span style={{
          fontFamily: T.mono, fontSize: 10, color: T.text3,
          letterSpacing: '0.20em', textTransform: 'uppercase',
        }}>NET CASH</span>
        <span style={{
          fontFamily: T.mohave, fontWeight: 300, fontSize: 60,
          color: T.text3, ...tnum, letterSpacing: '-0.025em', lineHeight: 0.95,
        }}>$0</span>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 4 }}>
          <span style={{
            fontFamily: T.mono, fontSize: 11, color: T.textMute,
            letterSpacing: '0.18em', textTransform: 'uppercase',
          }}>// NO ACTIVITY THIS PERIOD</span>
        </div>
      </div>

      <div style={{ marginTop: 22 }}>
        <div style={{
          height: 6, background: T.fillNeutralDim, borderRadius: T.rBar,
        }}/>
        <div style={{
          marginTop: 10, display: 'flex', justifyContent: 'space-between',
        }}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
            <span style={{
              fontFamily: T.mono, fontSize: 9.5, color: T.text3,
              letterSpacing: '0.18em', textTransform: 'uppercase',
            }}>PAYMENTS IN</span>
            <span style={{
              fontFamily: T.mono, fontSize: 14, fontWeight: 500, color: T.textMute, ...tnum,
            }}>—</span>
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 2, alignItems: 'flex-end' }}>
            <span style={{
              fontFamily: T.mono, fontSize: 9.5, color: T.text3,
              letterSpacing: '0.18em', textTransform: 'uppercase',
            }}>EXPENSES OUT</span>
            <span style={{
              fontFamily: T.mono, fontSize: 14, fontWeight: 500, color: T.textMute, ...tnum,
            }}>—</span>
          </div>
        </div>
      </div>

      <div style={{ marginTop: 24, display: 'flex', gap: 8 }}>
        <BTile label="OUTSTANDING" value="$0" sub="0 ITEMS" color={T.text3}/>
        <BTile label="FORECAST"    value="$0" sub="0 ITEMS" color={T.text3}/>
      </div>
    </div>
  );
}

function BooksScreenEmpty() {
  return (
    <div style={{ position: 'absolute', inset: 0, background: T.bg, overflow: 'hidden' }}>
      <StatusBar/>
      <AppHeader actions={['search', 'flag']}/>
      <div style={{ position: 'absolute', top: 100, left: 0, right: 0, bottom: 83 }}>
        <BHeader label="P&L" period={SEED.period}/>
        <EmptyPLCard/>
        <BDots index={0} total={5}/>
        <div style={{ marginTop: 22 }}><BSegments active="INVOICES"/></div>
        {/* Empty list state */}
        <div style={{ padding: '40px 20px 0', textAlign: 'center' }}>
          <span style={{
            display: 'block',
            fontFamily: T.mohave, fontWeight: 300, fontSize: 32, color: T.text3, ...tnum,
          }}>$0</span>
          <span style={{
            display: 'block', marginTop: 8,
            fontFamily: T.mono, fontSize: 10, color: T.textMute,
            letterSpacing: '0.20em', textTransform: 'uppercase',
          }}>// NO INVOICES</span>
        </div>
      </div>
      <TabBar active="books"/>
    </div>
  );
}

// ═══════════════════════════════════════════════════════
// OVERFLOW — large numbers, long client names
// ═══════════════════════════════════════════════════════
const BIG_SEED = {
  ar: {
    total: 1284600, openCount: 47, overdueCount: 38,
    buckets: [
      { range: '0–30D',  amount: 184800, color: 'olive' },
      { range: '31–60D', amount: 232400, color: 'fin-r' },
      { range: '61–90D', amount: 487200, color: 'tan' },
      { range: '90D+',   amount: 380200, color: 'brick' },
    ],
    topChase: { client: 'Westbridge Commercial Construction Inc.', invoice: 'INV-00284', amount: 187400, daysOverdue: 142 },
  },
};

function BooksScreenOverflow() {
  return (
    <div style={{ position: 'absolute', inset: 0, background: T.bg, overflow: 'hidden' }}>
      <div aria-hidden style={{
        position: 'absolute', inset: 0, pointerEvents: 'none',
        background: 'radial-gradient(500px 360px at 88% 10%, rgba(181,130,137,0.07), transparent 65%)',
      }}/>
      <StatusBar/>
      <AppHeader actions={['search', 'flag']}/>
      <div style={{ position: 'absolute', top: 100, left: 0, right: 0, bottom: 83 }}>
        <BHeader label="A/R AGING" scopeHint="ALL OPEN" scopeColor={T.rose} period={SEED.period}/>
        <BCard_AR data={BIG_SEED.ar}/>
        <BDots index={2} total={5}/>
        <div style={{ marginTop: 22 }}><BSegments active="INVOICES"/></div>
        <BListPreview segment="INVOICES" filter="OVERDUE · 90D+"/>
      </div>
      <TabBar active="books"/>
    </div>
  );
}

// ═══════════════════════════════════════════════════════
// COLLAPSED HERO STRIP — on vertical scroll, the hero compresses to a single line
// ═══════════════════════════════════════════════════════
function CollapsedStrip({ activeIndex = 0, total = 5, primary, arValue }) {
  const labels = ['NET · 6M', 'FLOW · 6M', 'A/R OPEN', 'FORECAST', 'JOBS NET'];
  return (
    <div style={{
      padding: '10px 20px', borderBottom: `1px solid ${T.line}`,
      display: 'flex', alignItems: 'center', gap: 14,
      background: 'rgba(10,10,10,0.85)',
      backdropFilter: 'blur(28px) saturate(1.3)',
      WebkitBackdropFilter: 'blur(28px) saturate(1.3)',
    }}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
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
          }}/>
        ))}
      </div>
    </div>
  );
}

function BooksScreenCollapsed() {
  // Simulates scrolled state: app header is in scrolled mode + collapsed strip + sticky segments
  return (
    <div style={{ position: 'absolute', inset: 0, background: T.bg, overflow: 'hidden' }}>
      <StatusBar/>
      <AppHeader actions={['search', 'flag']} scrolled compact/>

      <div style={{ position: 'absolute', top: 88, left: 0, right: 0, bottom: 83 }}>
        <CollapsedStrip activeIndex={0} total={5} primary="$42,180" arValue="$17.8K"/>
        <div style={{ position: 'sticky', top: 0, background: T.bg, zIndex: 2 }}>
          <BSegments active="INVOICES"/>
        </div>

        <BListPreview segment="INVOICES"/>
        {/* extra rows to make it look mid-scroll */}
        <div style={{ padding: '0 20px' }}>
          <div style={{
            background: T.glass, backdropFilter: 'blur(28px) saturate(1.3)',
            WebkitBackdropFilter: 'blur(28px) saturate(1.3)',
            border: `1px solid ${T.glassBorder}`, borderRadius: T.rL1, overflow: 'hidden',
            marginTop: 8,
          }}>
            {[
              { primary: 'Halcyon Builders', secondary: 'INV-00276 · DUE 6D',  amount: '$2,200', tag: 'OPEN', tone: 'neutral' },
              { primary: 'Dave Bernard',     secondary: 'INV-00292 · 24D OVERDUE', amount: '$600', tag: 'OVERDUE', tone: 'rose' },
              { primary: 'Scagliati Homes',  secondary: 'INV-00271 · PAID',   amount: '$8,400', tag: 'PAID', tone: 'olive' },
            ].map((r, i, arr) => (
              <div key={i} style={{
                display: 'flex', alignItems: 'center', justifyContent: 'space-between',
                padding: '14px 16px',
                borderBottom: i < arr.length - 1 ? `1px solid ${T.lineSoft}` : 'none',
              }}>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
                  <span style={{ fontFamily: T.mohave, fontSize: 15, fontWeight: 500, color: T.text }}>{r.primary}</span>
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
        </div>
      </div>

      <TabBar active="books"/>
    </div>
  );
}

// ═══════════════════════════════════════════════════════
// PERIOD MENU OPEN — all 8 options visible
// ═══════════════════════════════════════════════════════
function BooksScreenPeriodMenu() {
  return (
    <div style={{ position: 'absolute', inset: 0, background: T.bg, overflow: 'hidden' }}>
      <div aria-hidden style={{
        position: 'absolute', inset: 0, pointerEvents: 'none',
        background: 'radial-gradient(500px 360px at 88% 10%, rgba(111,148,176,0.07), transparent 65%)',
      }}/>
      <StatusBar/>
      <AppHeader actions={['search', 'flag']}/>

      <div style={{ position: 'absolute', top: 100, left: 0, right: 0, bottom: 83 }}>
        <BHeader label="P&L" period={SEED.period}/>
        <BCard_PL data={SEED.pl}/>
        <BDots index={0} total={5}/>
        <div style={{ marginTop: 22 }}><BSegments active="INVOICES"/></div>
      </div>

      {/* Dim overlay */}
      <div style={{
        position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.50)', zIndex: 60,
      }}/>

      {/* Menu — anchored to where the period pill is */}
      <div style={{
        position: 'absolute', top: 132, right: 20, zIndex: 70,
        minWidth: 180,
        background: T.glassDense, backdropFilter: 'blur(28px) saturate(1.3)',
        WebkitBackdropFilter: 'blur(28px) saturate(1.3)',
        border: `1px solid ${T.glassBorder}`, borderRadius: T.rL1, overflow: 'hidden',
      }}>
        <div style={{
          position: 'absolute', inset: 0, pointerEvents: 'none', borderRadius: 'inherit',
          background: 'linear-gradient(180deg, rgba(255,255,255,0.03), transparent 35%)',
        }}/>
        {SEED.periods.map((p, i) => {
          const isActive = p.token === SEED.period.token;
          return (
            <div key={p.token} style={{
              padding: '12px 14px', position: 'relative',
              borderBottom: i < SEED.periods.length - 1 ? `1px solid ${T.lineSoft}` : 'none',
              display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 12,
              background: isActive ? T.surfaceHover : 'transparent',
            }}>
              <span style={{
                fontFamily: T.mono, fontSize: 12, fontWeight: isActive ? 600 : 500,
                color: isActive ? T.text : T.text2,
                letterSpacing: '0.14em', textTransform: 'uppercase',
              }}>{p.label}</span>
              {isActive && <span style={{ color: T.text }}><Check size={14}/></span>}
            </div>
          );
        })}
      </div>

      <TabBar active="books"/>
    </div>
  );
}

// ═══════════════════════════════════════════════════════
// SEGMENT ACTIVE STATES — three variations
// ═══════════════════════════════════════════════════════
function BooksScreenSegment({ segment = 'INVOICES' }) {
  return (
    <div style={{ position: 'absolute', inset: 0, background: T.bg, overflow: 'hidden' }}>
      <StatusBar/>
      <AppHeader actions={['search', 'flag']} scrolled compact/>
      <div style={{ position: 'absolute', top: 88, left: 0, right: 0, bottom: 83 }}>
        <CollapsedStrip activeIndex={0} total={5} primary="$42,180" arValue="$17.8K"/>
        <BSegments active={segment}/>
        <BListPreview segment={segment}/>
      </div>
      <TabBar active="books"/>
    </div>
  );
}

// ═══════════════════════════════════════════════════════
// TILE DRILL — Outstanding tap → Invoices segment with overdue filter applied
// ═══════════════════════════════════════════════════════
function BooksScreenDrillOutstanding() {
  return (
    <div style={{ position: 'absolute', inset: 0, background: T.bg, overflow: 'hidden' }}>
      <StatusBar/>
      <AppHeader actions={['search', 'flag']}/>
      <div style={{ position: 'absolute', top: 100, left: 0, right: 0, bottom: 83 }}>
        <BHeader label="P&L" period={SEED.period}/>
        <BCard_PL data={SEED.pl}/>
        <BDots index={0} total={5}/>

        <div style={{ marginTop: 22 }}><BSegments active="INVOICES"/></div>

        {/* Filter applied */}
        <div style={{
          padding: '14px 20px 0',
          display: 'flex', alignItems: 'center', gap: 8,
        }}>
          <span style={{
            fontFamily: T.mono, fontSize: 9.5, color: T.text3,
            letterSpacing: '0.18em', textTransform: 'uppercase',
          }}>// FILTER</span>
          <span style={{
            display: 'inline-flex', alignItems: 'center', gap: 6,
            padding: '4px 10px', borderRadius: T.rChip,
            border: `1px solid ${T.rose}`, background: T.roseSoft,
            fontFamily: T.mono, fontSize: 10, color: T.roseM, fontWeight: 600,
            letterSpacing: '0.14em', textTransform: 'uppercase',
          }}>
            OVERDUE <span style={{ color: T.rose, opacity: 0.6 }}>×</span>
          </span>
          <span style={{ marginLeft: 'auto', fontFamily: T.mono, fontSize: 10, color: T.text3, ...tnum, letterSpacing: '0.12em' }}>4 RESULTS</span>
        </div>

        <BListPreview segment="INVOICES"/>
      </div>
      <TabBar active="books"/>
    </div>
  );
}

// ═══════════════════════════════════════════════════════
// AR DETAIL SHEET — TopChase tap → opens half-sheet with chase list
// ═══════════════════════════════════════════════════════
function BooksScreenARSheet() {
  return (
    <div style={{ position: 'absolute', inset: 0, background: T.bg, overflow: 'hidden' }}>
      <StatusBar/>
      <AppHeader actions={['search', 'flag']}/>
      <div style={{ position: 'absolute', top: 100, left: 0, right: 0, bottom: 83 }}>
        <BHeader label="A/R AGING" scopeHint="ALL OPEN" scopeColor={T.rose} period={SEED.period}/>
        <BCard_AR data={SEED.ar}/>
        <BDots index={2} total={5}/>
      </div>

      {/* Scrim */}
      <div style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.50)', zIndex: 60 }}/>

      {/* Half-sheet */}
      <div style={{
        position: 'absolute', bottom: 0, left: 0, right: 0, zIndex: 70,
        height: '62%',
        background: 'rgba(10,10,10,0.95)',
        backdropFilter: 'blur(28px) saturate(1.3)',
        WebkitBackdropFilter: 'blur(28px) saturate(1.3)',
        borderTopLeftRadius: 12, borderTopRightRadius: 12,
        borderTop: `1px solid ${T.line}`,
        display: 'flex', flexDirection: 'column',
      }}>
        {/* Handle */}
        <div style={{ display: 'flex', justifyContent: 'center', paddingTop: 8 }}>
          <div style={{ width: 36, height: 5, borderRadius: 99, background: 'rgba(255,255,255,0.30)' }}/>
        </div>
        {/* Sheet title */}
        <div style={{ padding: '20px 20px 12px', borderBottom: `1px solid ${T.line}` }}>
          <div style={{ display: 'flex', alignItems: 'baseline', gap: 8 }}>
            <span style={{
              fontFamily: T.mono, fontSize: 11, color: T.textMute,
              letterSpacing: '0.18em', textTransform: 'uppercase',
            }}>// CHASE LIST</span>
          </div>
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
        {/* Chase rows */}
        <div style={{ flex: 1, overflow: 'auto' }}>
          {SEED.ar.chaseList.map((r, i, arr) => (
            <div key={i} style={{
              display: 'flex', alignItems: 'center', justifyContent: 'space-between',
              padding: '14px 20px',
              borderBottom: i < arr.length - 1 ? `1px solid ${T.lineSoft}` : 'none',
            }}>
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

      <TabBar active="books"/>
    </div>
  );
}

// ═══════════════════════════════════════════════════════
// OFFLINE — cached data renders without spinner, banner shows sync state
// ═══════════════════════════════════════════════════════
function BooksScreenOffline() {
  return (
    <div style={{ position: 'absolute', inset: 0, background: T.bg, overflow: 'hidden' }}>
      <StatusBar/>
      <AppHeader actions={['search', 'flag']}/>

      {/* Sync banner */}
      <div style={{
        margin: '0 20px 12px',
        padding: '10px 12px', borderRadius: T.rL2,
        background: T.tanSoft, border: `1px solid ${T.tanLine}`,
        display: 'flex', alignItems: 'center', gap: 10,
      }}>
        {/* circular pulse dot */}
        <div style={{ width: 8, height: 8, borderRadius: 99, background: T.tan, flexShrink: 0 }}/>
        <span style={{
          fontFamily: T.mono, fontSize: 10.5, color: T.tanM, fontWeight: 600,
          letterSpacing: '0.16em', textTransform: 'uppercase',
        }}>SYS :: OFFLINE · CACHED 08:42</span>
        <span style={{ marginLeft: 'auto', fontFamily: T.mono, fontSize: 10, color: T.tan }}>RETRY →</span>
      </div>

      <div style={{ position: 'absolute', top: 144, left: 0, right: 0, bottom: 83 }}>
        <BHeader label="P&L" period={SEED.period}/>
        <BCard_PL data={SEED.pl}/>
        <BDots index={0} total={5}/>
        <div style={{ marginTop: 22 }}><BSegments active="INVOICES"/></div>
        <BListPreview segment="INVOICES"/>
      </div>

      <TabBar active="books"/>
    </div>
  );
}

// ═══════════════════════════════════════════════════════
// OPERATOR ROLE — carousel hidden, only ESTIMATES + EXPENSES segments
// ═══════════════════════════════════════════════════════
function BooksScreenOperator() {
  return (
    <div style={{ position: 'absolute', inset: 0, background: T.bg, overflow: 'hidden' }}>
      <StatusBar/>
      <AppHeader actions={['search']}/>
      <div style={{ position: 'absolute', top: 100, left: 0, right: 0, bottom: 83 }}>
        <div style={{ padding: '12px 20px 24px' }}>
          <span style={{
            fontFamily: T.mono, fontSize: 10, color: T.text3,
            letterSpacing: '0.20em', textTransform: 'uppercase',
          }}>// OPERATOR · NO FINANCE ACCESS</span>
        </div>
        <BSegments active="ESTIMATES" options={['ESTIMATES', 'EXPENSES']}/>
        <BListPreview segment="ESTIMATES"/>
      </div>
      <TabBar active="books"/>
    </div>
  );
}

Object.assign(window, {
  BooksScreenEmpty, BooksScreenOverflow, BooksScreenCollapsed,
  BooksScreenPeriodMenu, BooksScreenSegment,
  BooksScreenDrillOutstanding, BooksScreenARSheet, BooksScreenOffline,
  BooksScreenOperator, CollapsedStrip,
  BooksScreenSkeleton, BooksScreenError, BooksScreenPTR,
});

// ═══════════════════════════════════════════════════════
// SKELETON — first paint while data hydrates from cache, or while sync runs
// Per design system: pulsing rectangles, bg 0.06 → 0.03, radius matches element
// ═══════════════════════════════════════════════════════
function Skeleton({ w, h, radius = T.rL2, style = {} }) {
  return (
    <div style={{
      width: w, height: h, borderRadius: radius,
      background: T.fillNeutralDim,
      animation: 'sk-pulse 1.5s ease-in-out infinite',
      ...style,
    }}/>
  );
}

function SkeletonPLCard() {
  return (
    <div style={{ padding: '20px 20px 0' }}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
        <Skeleton w={80} h={10} radius={2}/>
        <Skeleton w={220} h={52} radius={4}/>
        <Skeleton w={180} h={11} radius={2} style={{ marginTop: 4 }}/>
      </div>
      <div style={{ marginTop: 22 }}>
        <Skeleton w="100%" h={6} radius={T.rBar}/>
        <div style={{ marginTop: 10, display: 'flex', justifyContent: 'space-between' }}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
            <Skeleton w={70} h={9} radius={2}/>
            <Skeleton w={90} h={14} radius={2}/>
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 4, alignItems: 'flex-end' }}>
            <Skeleton w={70} h={9} radius={2}/>
            <Skeleton w={90} h={14} radius={2}/>
          </div>
        </div>
      </div>
      <div style={{ marginTop: 24, display: 'flex', gap: 8 }}>
        <SkeletonTile/>
        <SkeletonTile/>
      </div>
    </div>
  );
}

function SkeletonTile() {
  return (
    <div style={{
      flex: 1, padding: '14px', minHeight: 80,
      background: T.nested, border: `1px solid ${T.nestedBorder}`,
      borderRadius: T.rL2,
      display: 'flex', flexDirection: 'column', gap: 8,
    }}>
      <Skeleton w={70} h={9} radius={2}/>
      <Skeleton w={90} h={18} radius={2}/>
      <Skeleton w={60} h={9} radius={2}/>
    </div>
  );
}

function BooksScreenSkeleton() {
  return (
    <div style={{ position: 'absolute', inset: 0, background: T.bg, overflow: 'hidden' }}>
      <style>{`
        @keyframes sk-pulse {
          0%, 100% { background: rgba(255,255,255,0.03); }
          50%      { background: rgba(255,255,255,0.08); }
        }
        @media (prefers-reduced-motion: reduce) {
          [style*="sk-pulse"] { animation: none !important; }
        }
      `}</style>
      <StatusBar/>
      <AppHeader actions={['search', 'flag']}/>

      {/* Sync indicator banner — slim, top */}
      <div style={{
        margin: '0 20px 8px', padding: '6px 12px',
        borderRadius: T.rChip,
        background: T.surfaceInput, border: `1px solid ${T.line}`,
        display: 'flex', alignItems: 'center', gap: 8,
      }}>
        <div style={{
          width: 6, height: 6, borderRadius: 99, background: T.text3,
          animation: 'sk-pulse 1.5s ease-in-out infinite',
        }}/>
        <span style={{
          fontFamily: T.mono, fontSize: 10, color: T.text3, fontWeight: 500,
          letterSpacing: '0.16em', textTransform: 'uppercase',
        }}>SYS :: SYNC \u00b7 08:42</span>
      </div>

      <div style={{ position: 'absolute', top: 110, left: 0, right: 0, bottom: 83 }}>
        {/* Header */}
        <div style={{
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          padding: '12px 20px 0', minHeight: 44,
        }}>
          <Skeleton w={50} h={11} radius={2}/>
          <Skeleton w={120} h={36} radius={T.rPill}/>
        </div>
        {/* Card body skeleton — uses real Mohave-300 ghost: shows it's a number not a generic block */}
        <SkeletonPLCard/>
        {/* Dots */}
        <div style={{
          display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6,
          padding: '20px 20px 0',
        }}>
          <Skeleton w={22} h={6} radius={99}/>
          {Array.from({ length: 4 }).map((_, i) => <Skeleton key={i} w={6} h={6} radius={99}/>)}
        </div>
        {/* Segmented control */}
        <div style={{ padding: '22px 20px 0' }}>
          <Skeleton w="100%" h={44} radius={T.rBtn}/>
        </div>
        {/* List rows */}
        <div style={{ padding: '12px 20px 0' }}>
          <div style={{
            background: T.glass, backdropFilter: 'blur(28px) saturate(1.3)',
            WebkitBackdropFilter: 'blur(28px) saturate(1.3)',
            border: `1px solid ${T.glassBorder}`, borderRadius: T.rL1, overflow: 'hidden',
          }}>
            {[0,1,2].map(i => (
              <div key={i} style={{
                padding: '14px 16px', borderBottom: i < 2 ? `1px solid ${T.line}` : 'none',
                display: 'flex', alignItems: 'center', justifyContent: 'space-between',
              }}>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
                  <Skeleton w={140} h={15} radius={2}/>
                  <Skeleton w={180} h={10} radius={2}/>
                </div>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 6, alignItems: 'flex-end' }}>
                  <Skeleton w={56} h={13} radius={2}/>
                  <Skeleton w={48} h={16} radius={T.rChip}/>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>

      <TabBar active="books"/>
    </div>
  );
}

// ═══════════════════════════════════════════════════════
// ERROR — card-level load failure. Spec: // ERROR \u2014 LOAD FAILED · [RETRY]
// ═══════════════════════════════════════════════════════
function ErrorCard() {
  return (
    <div style={{
      padding: '40px 20px 0',
      display: 'flex', flexDirection: 'column', alignItems: 'center', textAlign: 'center', gap: 12,
    }}>
      <span style={{
        display: 'block', fontFamily: T.mohave, fontWeight: 300, fontSize: 48, color: T.rose, ...tnum,
        lineHeight: 1,
      }}>\u2014</span>
      <span style={{
        fontFamily: T.mono, fontSize: 10.5, color: T.rose, fontWeight: 600,
        letterSpacing: '0.18em', textTransform: 'uppercase',
      }}>// ERROR \u2014 LOAD FAILED</span>
      <span style={{
        fontFamily: T.mohave, fontSize: 13, color: T.text2, lineHeight: 1.5,
        maxWidth: 260,
      }}>Couldn't fetch this period. Showing cached data above the fold; tap retry to try again.</span>
      <button style={{
        marginTop: 4,
        padding: '10px 16px', minHeight: 44, borderRadius: T.rBtn,
        background: T.roseSoft, border: `1px solid ${T.roseLine}`,
        fontFamily: T.cake, fontWeight: 300, fontSize: 13, color: T.rose,
        letterSpacing: '0.02em', textTransform: 'uppercase', cursor: 'pointer',
        display: 'inline-flex', alignItems: 'center', gap: 8,
      }}>
        RETRY <Arrow dir="right" size={9}/>
      </button>
    </div>
  );
}

function BooksScreenError() {
  return (
    <div style={{ position: 'absolute', inset: 0, background: T.bg, overflow: 'hidden' }}>
      <StatusBar/>
      <AppHeader actions={['search', 'flag']}/>
      <div style={{ position: 'absolute', top: 100, left: 0, right: 0, bottom: 83 }}>
        <BHeader label="P&L" period={SEED.period}/>
        <ErrorCard/>
        <BDots index={0} total={5}/>
        <div style={{ marginTop: 22 }}><BSegments active="INVOICES"/></div>
        <BListPreview segment="INVOICES"/>
      </div>
      <TabBar active="books"/>
    </div>
  );
}

// ═══════════════════════════════════════════════════════
// PULL-TO-REFRESH — mid-pull indicator visible at the top
// Per design system: OPS mark (16px, text-3) + circular progress arc
// ═══════════════════════════════════════════════════════
function BooksScreenPTR() {
  return (
    <div style={{ position: 'absolute', inset: 0, background: T.bg, overflow: 'hidden' }}>
      <StatusBar/>
      <AppHeader actions={['search', 'flag']}/>
      <div style={{ position: 'absolute', top: 100, left: 0, right: 0, bottom: 83 }}>
        {/* PTR indicator zone, simulating a 48pt pull */}
        <div style={{
          height: 48, display: 'flex', alignItems: 'center', justifyContent: 'center',
          gap: 10, color: T.text3,
        }}>
          {/* OPS mark glyph approximation \u2014 two chamfered brackets */}
          <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
            <path d="M3 3L7 3L7 7M3 3L3 7L7 7M13 13L9 13L9 9M13 13L13 9L9 9"
              stroke="currentColor" strokeWidth="1.5" strokeLinecap="square"/>
          </svg>
          {/* Progress arc */}
          <svg width="18" height="18" viewBox="0 0 18 18" fill="none" style={{
            animation: 'ptr-spin 0.9s linear infinite',
          }}>
            <circle cx="9" cy="9" r="7" stroke={T.line} strokeWidth="1.5"/>
            <path d="M9 2A7 7 0 0 1 16 9" stroke={T.text2} strokeWidth="1.5" strokeLinecap="round"/>
          </svg>
          <span style={{
            fontFamily: T.mono, fontSize: 10, color: T.text3, fontWeight: 500,
            letterSpacing: '0.18em', textTransform: 'uppercase',
          }}>SYNCING</span>
        </div>
        <style>{`
          @keyframes ptr-spin { from { transform: rotate(0); } to { transform: rotate(360deg); } }
          @media (prefers-reduced-motion: reduce) {
            [style*="ptr-spin"] { animation: none !important; }
          }
        `}</style>

        <BHeader label="P&L" period={SEED.period}/>
        <BCard_PL data={SEED.pl}/>
        <BDots index={0} total={5}/>
        <div style={{ marginTop: 22 }}><BSegments active="INVOICES"/></div>
      </div>
      <TabBar active="books"/>
    </div>
  );
}
