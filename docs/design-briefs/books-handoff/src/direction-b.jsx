// direction-b.jsx — "MISSION DECK"
// Hero-led. Big numbers (60px). Generous whitespace. Sparklines + soft ramps.
// Drill tiles are L2 nested cards with breathing room.
// Period pill is a softer 12px rounded rectangle.
// Dot pagination: capsule-grow active.

// ─── Period pill (Mission Deck: soft 12px rounded — 44pt touch target) ─────
function BPill({ label, short }) {
  return (
    <div style={{
      display: 'inline-flex', alignItems: 'center', gap: 8,
      padding: '10px 14px', minHeight: 44, borderRadius: T.rPill,
      border: `1px solid ${T.line}`, background: T.surfaceInput,
      fontFamily: T.mono, fontSize: 11, fontWeight: 500, color: T.text,
      letterSpacing: '0.14em', textTransform: 'uppercase', ...tnum,
    }}>
      {label}
      <ChevronDown size={9}/>
    </div>
  );
}

// ─── Carousel header row — spec: JetBrains Mono 11px / 0.16em ──
function BHeader({ label, scopeHint, scopeColor, period }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      padding: '12px 20px 0', minHeight: 44,
    }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
        <span style={{
          fontFamily: T.mono, fontSize: 11, fontWeight: 600, color: T.text,
          letterSpacing: '0.16em', textTransform: 'uppercase',
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
      <BPill label={period.label} short={period.short}/>
    </div>
  );
}

// ─── Dot pagination (Mission Deck: capsule grows) ───────
function BDots({ index, total }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6,
      padding: '20px 20px 0',
    }}>
      {Array.from({ length: total }).map((_, i) => (
        <div key={i} style={{
          width: i === index ? 22 : 6, height: 6, borderRadius: 99,
          background: i === index ? T.text : T.textMute,
          opacity: i === index ? 1 : 0.5,
          transition: `width ${T.dPanel}ms ${T.ease}`,
        }}/>
      ))}
    </div>
  );
}

// ─── L2 drill tile (Mission Deck: nested card surface — tappable) ──
function BTile({ label, value, sub, color = T.text, accent = false, onClick }) {
  const Tag = onClick ? 'button' : 'div';
  return (
    <Tag
      onClick={onClick}
      style={{
        flex: 1, padding: '14px 14px', minHeight: 80,
        background: accent ? T.accentMuted : T.nested,
        border: `1px solid ${accent ? 'rgba(111,148,176,0.25)' : T.nestedBorder}`,
        borderRadius: T.rL2,
        display: 'flex', flexDirection: 'column', gap: 8, minWidth: 0,
        cursor: onClick ? 'pointer' : 'default', textAlign: 'left',
        transition: `background ${T.dHover}ms ${T.ease}, border-color ${T.dHover}ms ${T.ease}`,
        font: 'inherit',
      }}
      onMouseEnter={onClick ? e => { e.currentTarget.style.background = T.surfaceHover; } : undefined}
      onMouseLeave={onClick ? e => { e.currentTarget.style.background = accent ? T.accentMuted : T.nested; } : undefined}
      onTouchStart={onClick ? e => { e.currentTarget.style.background = T.surfaceActive; e.currentTarget.style.borderColor = 'rgba(255,255,255,0.18)'; } : undefined}
      onTouchEnd={onClick ? e => { e.currentTarget.style.background = accent ? T.accentMuted : T.nested; e.currentTarget.style.borderColor = accent ? 'rgba(111,148,176,0.25)' : T.nestedBorder; } : undefined}
    >
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      }}>
        <span style={{
          fontFamily: T.mono, fontSize: 9.5, color: T.text3,
          letterSpacing: '0.18em', textTransform: 'uppercase',
        }}>{label}</span>
        {onClick !== false && <span style={{ color: T.text3 }}><Arrow dir="right" size={9}/></span>}
      </div>
      <div style={{
        fontFamily: T.mono, fontSize: 18, fontWeight: 500, color, ...tnum,
        letterSpacing: '-0.01em',
      }}>{value}</div>
      {sub && <span style={{
        fontFamily: T.mono, fontSize: 9.5, color: T.textMute,
        letterSpacing: '0.14em', textTransform: 'uppercase', ...tnum,
        whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
      }}>{sub}</span>}
    </Tag>
  );
}

// ═══════════════════════════════════════════════════════
// CARD 1 — P&L (Mission Deck)
// ═══════════════════════════════════════════════════════
function BCard_PL({ data, onDrillOutstanding, onDrillForecast }) {
  return (
    <div style={{ padding: '20px 20px 0' }}>
      {/* Hero — net cash, BIG */}
      <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
        <span style={{
          fontFamily: T.mono, fontSize: 10, color: T.text3,
          letterSpacing: '0.20em', textTransform: 'uppercase',
        }}>NET CASH</span>
        <span style={{
          fontFamily: T.mohave, fontWeight: 300, fontSize: 60,
          color: T.text, ...tnum, letterSpacing: '-0.025em', lineHeight: 0.95,
        }}>{fmt$(data.netCash)}</span>
        {/* Margin caption */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 4 }}>
          <span style={{
            fontFamily: T.mono, fontSize: 11, color: T.olive, fontWeight: 500, ...tnum,
            letterSpacing: '0.04em',
          }}>{data.marginPct}% MARGIN</span>
          <span style={{
            fontFamily: T.mono, fontSize: 11, color: T.textMute,
          }}>·</span>
          <span style={{
            fontFamily: T.mono, fontSize: 11, color: T.text3, ...tnum,
            letterSpacing: '0.04em',
          }}>{fmt$(data.payments - data.expenses, { sign: true })} ON {fmt$(data.payments, { compact: true })}</span>
        </div>
      </div>

      {/* Margin meter */}
      <div style={{ marginTop: 22 }}>
        <div style={{
          height: 6, background: T.fillNeutralDim, borderRadius: T.rBar, overflow: 'hidden',
          position: 'relative',
        }}>
          <div style={{
            width: '100%', height: '100%', background: T.tanSoft, position: 'absolute',
          }}/>
          <div style={{
            width: `${data.marginPct}%`, height: '100%', background: T.olive, position: 'absolute',
          }}/>
        </div>
        <div style={{
          marginTop: 10, display: 'flex', justifyContent: 'space-between',
        }}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
            <span style={{
              fontFamily: T.mono, fontSize: 9.5, color: T.text3,
              letterSpacing: '0.18em', textTransform: 'uppercase',
            }}>PAYMENTS IN</span>
            <span style={{
              fontFamily: T.mono, fontSize: 14, fontWeight: 500, color: T.oliveM, ...tnum,
            }}>{fmt$(data.payments, { sign: true })}</span>
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 2, alignItems: 'flex-end' }}>
            <span style={{
              fontFamily: T.mono, fontSize: 9.5, color: T.text3,
              letterSpacing: '0.18em', textTransform: 'uppercase',
            }}>EXPENSES OUT</span>
            <span style={{
              fontFamily: T.mono, fontSize: 14, fontWeight: 500, color: T.tanM, ...tnum,
            }}>{fmt$(-data.expenses)}</span>
          </div>
        </div>
      </div>

      {/* Drill tiles */}
      <div style={{ marginTop: 24, display: 'flex', gap: 8 }}>
        <BTile label="OUTSTANDING" value={fmt$(data.outstanding)} sub={`${data.outstandingCount} ITEMS`} onClick={onDrillOutstanding}/>
        <BTile label="FORECAST"    value={fmt$(data.forecast)}    sub={`${data.forecastCount} ITEMS`}    onClick={onDrillForecast}/>
      </div>
    </div>
  );
}

// ═══════════════════════════════════════════════════════
// CARD 2 — Cash flow (Mission Deck: sparkline + paired bars condensed)
// ═══════════════════════════════════════════════════════
function BCard_Flow({ data, onDrillDays }) {
  const maxAbs = Math.max(...data.weeks.map(w => Math.max(w[1], -w[2])));
  const chartW = 350, chartH = 84;
  const stepX = chartW / (data.weeks.length - 1);

  // build sparkline path
  const netPoints = data.weeks.map(([wk, inAmt, outAmt], i) => {
    const net = inAmt + outAmt;
    const x = i * stepX;
    const y = chartH / 2 - (net / maxAbs) * (chartH / 2 - 4);
    return [x, y];
  });
  const linePath = netPoints.map((p, i) => `${i === 0 ? 'M' : 'L'}${p[0]} ${p[1]}`).join(' ');
  const areaPath = `${linePath} L${chartW} ${chartH/2} L0 ${chartH/2} Z`;

  return (
    <div style={{ padding: '20px 20px 0' }}>
      {/* Hero */}
      <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
        <span style={{
          fontFamily: T.mono, fontSize: 10, color: T.text3,
          letterSpacing: '0.20em', textTransform: 'uppercase',
        }}>NET CASH · {data.weeks.length}W TRAILING</span>
        <span style={{
          fontFamily: T.mohave, fontWeight: 300, fontSize: 60,
          color: T.text, ...tnum, letterSpacing: '-0.025em', lineHeight: 0.95,
        }}>{fmt$(data.netCash)}</span>
      </div>

      {/* Sparkline */}
      <div style={{ marginTop: 22, position: 'relative' }}>
        <svg width="100%" height={chartH} viewBox={`0 0 ${chartW} ${chartH}`} preserveAspectRatio="none">
          {/* zero axis */}
          <line x1="0" y1={chartH/2} x2={chartW} y2={chartH/2} stroke={T.lineSoft} strokeWidth="1"/>
          {/* area fill */}
          <path d={areaPath} fill={T.oliveSoft}/>
          {/* line */}
          <path d={linePath} fill="none" stroke={T.olive} strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"/>
          {/* dots at each point */}
          {netPoints.map((p, i) => (
            <circle key={i} cx={p[0]} cy={p[1]} r="2.5" fill={T.bg} stroke={T.olive} strokeWidth="1.2"/>
          ))}
          {/* mark the bad week */}
          <circle cx={netPoints[2][0]} cy={netPoints[2][1]} r="3" fill={T.rose}/>
        </svg>
        <div style={{
          position: 'absolute', top: 0, left: 0, right: 0, padding: '0',
          display: 'flex', justifyContent: 'space-between',
          fontFamily: T.mono, fontSize: 8.5, color: T.textMute, letterSpacing: '0.10em',
        }}>
          <span>{data.weeks[0][0]}</span>
          <span>{data.weeks[data.weeks.length - 1][0]}</span>
        </div>
      </div>

      {/* Drill tiles */}
      <div style={{ marginTop: 24, display: 'flex', gap: 8 }}>
        <BTile label="SALES"   value={fmt$(data.salesTotal, { compact: true })} sub="TRAILING"/>
        <BTile label="AVG/WK"  value={fmt$(data.avgPerWeek, { compact: true })} sub="PER WEEK"/>
        <BTile label="DAYS"    value={data.daysToPay.toFixed(1)}                sub="TO PAY" onClick={onDrillDays}/>
      </div>
    </div>
  );
}

// ═══════════════════════════════════════════════════════
// CARD 3 — A/R Aging (Mission Deck: ramp meter)
// ═══════════════════════════════════════════════════════
function BCard_AR({ data, onDrillTopChase }) {
  const total = data.buckets.reduce((s, b) => s + b.amount, 0);
  const colorOf = (k) => k === 'olive' ? T.olive : k === 'fin-r' ? T.finReceivables : k === 'tan' ? T.tan : T.brick;

  return (
    <div style={{ padding: '20px 20px 0' }}>
      {/* Hero — outstanding in rose */}
      <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
        <span style={{
          fontFamily: T.mono, fontSize: 10, color: T.rose,
          letterSpacing: '0.20em', textTransform: 'uppercase',
        }}>TOTAL OUTSTANDING</span>
        <span style={{
          fontFamily: T.mohave, fontWeight: 300, fontSize: 60,
          color: T.rose, ...tnum, letterSpacing: '-0.025em', lineHeight: 0.95,
        }}>{fmt$(data.total)}</span>
        <span style={{
          fontFamily: T.mono, fontSize: 11, color: T.text2,
          letterSpacing: '0.12em', textTransform: 'uppercase', ...tnum, marginTop: 4,
        }}>{data.openCount} OPEN <span style={{ color: T.textMute }}>·</span> <span style={{ color: T.rose }}>{data.overdueCount} OVERDUE</span></span>
      </div>

      {/* Aging ramp — single continuous bar with bucket markers below */}
      <div style={{ marginTop: 24 }}>
        <div style={{
          display: 'flex', height: 10, gap: 2, borderRadius: T.rBar, overflow: 'hidden',
        }}>
          {data.buckets.map((b, i) => (
            <div key={i} style={{
              flex: b.amount / total, background: colorOf(b.color),
            }}/>
          ))}
        </div>
        <div style={{
          marginTop: 14, display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 6,
        }}>
          {data.buckets.map((b, i) => (
            <div key={i} style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
              <span style={{
                fontFamily: T.mono, fontSize: 9.5, color: colorOf(b.color), fontWeight: 600,
                letterSpacing: '0.16em', textTransform: 'uppercase',
              }}>{b.range}</span>
              <span style={{
                fontFamily: T.mono, fontSize: 13, fontWeight: 500, color: T.text, ...tnum,
                letterSpacing: '-0.01em',
              }}>{fmt$(b.amount)}</span>
            </div>
          ))}
        </div>
      </div>

      {/* Top chase tile (taller, single big tile) */}
      <div style={{ marginTop: 24 }}>
        <button
          onClick={onDrillTopChase}
          style={{
            width: '100%', minHeight: 80, padding: '16px',
            background: T.nested, border: `1px solid ${T.nestedBorder}`,
            borderRadius: T.rL2, display: 'flex', flexDirection: 'column', gap: 8,
            cursor: onDrillTopChase ? 'pointer' : 'default', textAlign: 'left',
            transition: `background ${T.dHover}ms ${T.ease}, border-color ${T.dHover}ms ${T.ease}`,
            font: 'inherit',
          }}
          onMouseEnter={onDrillTopChase ? e => { e.currentTarget.style.background = T.surfaceHover; } : undefined}
          onMouseLeave={onDrillTopChase ? e => { e.currentTarget.style.background = T.nested; } : undefined}
          onTouchStart={onDrillTopChase ? e => { e.currentTarget.style.background = T.surfaceActive; e.currentTarget.style.borderColor = 'rgba(255,255,255,0.18)'; } : undefined}
          onTouchEnd={onDrillTopChase ? e => { e.currentTarget.style.background = T.nested; e.currentTarget.style.borderColor = T.nestedBorder; } : undefined}
        >
          <div style={{
            display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          }}>
            <span style={{
              fontFamily: T.mono, fontSize: 9.5, color: T.text3,
              letterSpacing: '0.20em', textTransform: 'uppercase',
            }}>TOP CHASE</span>
            {onDrillTopChase !== false && <span style={{ color: T.text3 }}><Arrow dir="right" size={9}/></span>}
          </div>
          <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between' }}>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
              <span style={{
                fontFamily: T.mohave, fontSize: 15, fontWeight: 500, color: T.text,
              }}>{data.topChase.client}</span>
              <span style={{
                fontFamily: T.mono, fontSize: 10, color: T.text3,
                letterSpacing: '0.12em', textTransform: 'uppercase', ...tnum,
              }}>{data.topChase.invoice} · {data.topChase.daysOverdue}D OVERDUE</span>
            </div>
            <span style={{
              fontFamily: T.mono, fontSize: 20, fontWeight: 500, color: T.rose, ...tnum,
              letterSpacing: '-0.01em',
            }}>{fmt$(data.topChase.amount)}</span>
          </div>
        </button>
      </div>
    </div>
  );
}

// ═══════════════════════════════════════════════════════
// CARD 4 — Forecast (Mission Deck: stage rings or pyramid)
// ═══════════════════════════════════════════════════════
function BCard_Forecast({ data, onDrillCloseRate, onDrillStale }) {
  const maxAmt = Math.max(...data.stages.map(s => s.amount));
  return (
    <div style={{ padding: '20px 20px 0' }}>
      {/* Hero */}
      <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
        <span style={{
          fontFamily: T.mono, fontSize: 10, color: T.accent,
          letterSpacing: '0.20em', textTransform: 'uppercase',
        }}>WEIGHTED FORECAST</span>
        <span style={{
          fontFamily: T.mohave, fontWeight: 300, fontSize: 60,
          color: T.accent, ...tnum, letterSpacing: '-0.025em', lineHeight: 0.95,
        }}>{fmt$(data.weighted)}</span>
        <span style={{
          fontFamily: T.mono, fontSize: 11, color: T.text2,
          letterSpacing: '0.12em', textTransform: 'uppercase', ...tnum, marginTop: 4,
        }}>{data.activeCount} ACTIVE OPPORTUNITIES</span>
      </div>

      {/* Stage bars — taller, accent-only, with weight indicator */}
      <div style={{ marginTop: 24, display: 'flex', flexDirection: 'column', gap: 12 }}>
        {data.stages.map((s, i) => (
          <div key={i} style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
            <div style={{
              display: 'flex', alignItems: 'baseline', justifyContent: 'space-between',
            }}>
              <span style={{
                fontFamily: T.mono, fontSize: 10, color: T.text2,
                letterSpacing: '0.16em', textTransform: 'uppercase', fontWeight: 500,
              }}>{s.name}</span>
              <div style={{ display: 'flex', alignItems: 'baseline', gap: 6 }}>
                <span style={{
                  fontFamily: T.mono, fontSize: 9, color: T.textMute,
                  letterSpacing: '0.10em', ...tnum,
                }}>×{Math.round(s.pct * 100)}%</span>
                <span style={{
                  fontFamily: T.mono, fontSize: 13, fontWeight: 500, color: T.text, ...tnum,
                }}>{fmt$(s.amount)}</span>
              </div>
            </div>
            <div style={{
              height: 5, background: T.accentMuted, borderRadius: T.rBar, overflow: 'hidden',
            }}>
              <div style={{
                width: `${(s.amount / maxAmt) * 100}%`, height: '100%', background: T.accent,
              }}/>
            </div>
          </div>
        ))}
      </div>

      {/* Drill tiles */}
      <div style={{ marginTop: 22, display: 'flex', gap: 8 }}>
        <BTile label="CLOSE RATE" value={`${data.closeRate}%`}    sub="LAST 90D"  color={T.olive} onClick={onDrillCloseRate}/>
        <BTile label="STALE"      value={String(data.staleCount)} sub="> 14D IDLE" color={T.tan}   onClick={onDrillStale}/>
      </div>
    </div>
  );
}

// ═══════════════════════════════════════════════════════
// CARD 5 — Jobs (Mission Deck: large diverging chart, names prominent)
// ═══════════════════════════════════════════════════════
function BCard_Jobs({ data, onDrillProfitable, onDrillLosers }) {
  const maxAbs = Math.max(...data.list.map(j => Math.abs(j.net)));
  return (
    <div style={{ padding: '20px 20px 0' }}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
        <span style={{
          fontFamily: T.mono, fontSize: 10, color: T.text3,
          letterSpacing: '0.20em', textTransform: 'uppercase',
        }}>TOP 5 JOBS BY NET</span>
      </div>

      <div style={{ marginTop: 18, display: 'flex', flexDirection: 'column', gap: 14 }}>
        {data.list.map((j, i) => {
          const positive = j.net >= 0;
          const widthPct = (Math.abs(j.net) / maxAbs) * 50;
          return (
            <div key={i} style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
              <div style={{
                display: 'flex', alignItems: 'baseline', justifyContent: 'space-between',
              }}>
                <span style={{
                  fontFamily: T.mohave, fontWeight: 500, fontSize: 14, color: T.text,
                  letterSpacing: '0.04em',
                }}>{j.name}</span>
                <div style={{ display: 'flex', alignItems: 'baseline', gap: 8 }}>
                  <span style={{
                    fontFamily: T.mono, fontSize: 9.5, color: T.text3, ...tnum,
                    letterSpacing: '0.10em',
                  }}>{j.margin > 0 ? '+' : ''}{j.margin}%</span>
                  <span style={{
                    fontFamily: T.mono, fontSize: 14, fontWeight: 500,
                    color: positive ? T.oliveM : T.roseM, ...tnum,
                    letterSpacing: '-0.01em',
                  }}>{fmt$(j.net, { sign: positive })}</span>
                </div>
              </div>
              <div style={{ position: 'relative', height: 5 }}>
                <div style={{
                  position: 'absolute', top: 0, bottom: 0, left: '50%', width: 1, background: T.line,
                }}/>
                <div style={{
                  position: 'absolute', top: 0, bottom: 0,
                  left: positive ? '50%' : `${50 - widthPct}%`,
                  width: `${widthPct}%`,
                  background: positive ? T.olive : T.rose,
                  borderRadius: T.rBar,
                }}/>
              </div>
            </div>
          );
        })}
      </div>

      <div style={{ marginTop: 22, display: 'flex', gap: 8 }}>
        <BTile label="PROFITABLE" value={String(data.profitableCount)} sub="JOBS" color={T.olive} onClick={onDrillProfitable}/>
        <BTile label="AVG MARGIN" value={`${data.avgMarginPct}%`}      sub="MEAN" color={T.text}/>
        <BTile label="LOSERS"     value={String(data.losersCount)}     sub="JOBS" color={T.rose}  onClick={onDrillLosers}/>
      </div>
    </div>
  );
}

// ═══════════════════════════════════════════════════════
// SEGMENTED CONTROL (Mission Deck: pill-style segments with subtle bg)
// ═══════════════════════════════════════════════════════
function BSegments({ active = 'INVOICES', options = ['INVOICES', 'ESTIMATES', 'EXPENSES'] }) {
  return (
    <div style={{ padding: '0 20px' }}>
      <div style={{
        display: 'flex', padding: 3, borderRadius: T.rBtn,
        background: 'rgba(255,255,255,0.03)', border: `1px solid ${T.line}`,
        gap: 2,
      }}>
        {options.map(opt => {
          const isActive = opt === active;
          return (
            <div key={opt} style={{
              flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center',
              padding: '10px 0', borderRadius: 3,
              background: isActive ? 'rgba(255,255,255,0.10)' : 'transparent',
              border: `1px solid ${isActive ? 'rgba(255,255,255,0.22)' : 'transparent'}`,
              boxShadow: isActive ? 'inset 0 1px 0 rgba(255,255,255,0.06)' : 'none',
            }}>
              <span style={{
                fontFamily: T.mono, fontSize: 10.5, fontWeight: 500,
                color: isActive ? T.text : T.text3,
                letterSpacing: '0.16em', textTransform: 'uppercase',
              }}>{opt}</span>
            </div>
          );
        })}
      </div>
    </div>
  );
}

// ═══════════════════════════════════════════════════════
// LIST PREVIEW (Mission Deck: glass L1 wrapping the list)
// ═══════════════════════════════════════════════════════
function BListPreview({ segment = 'INVOICES', filter = null }) {
  const rows = segment === 'INVOICES' ? [
    { primary: 'Verity Projects',    secondary: 'INV-00284 · 71D OVERDUE', amount: '$6,400',  tag: 'OVERDUE', tone: 'rose' },
    { primary: 'Halcyon Builders',   secondary: 'INV-00301 · 94D OVERDUE', amount: '$3,400',  tag: 'OVERDUE', tone: 'rose' },
    { primary: 'Mara Lin',           secondary: 'INV-00298 · 42D OVERDUE', amount: '$3,200',  tag: 'OVERDUE', tone: 'rose' },
  ] : segment === 'ESTIMATES' ? [
    { primary: 'Scagliati Homes',    secondary: 'EST-00112 · SENT 3D AGO', amount: '$12,800', tag: 'SENT',    tone: 'tan' },
    { primary: 'Citygate Residence', secondary: 'EST-00109 · VIEWED',      amount: '$18,400', tag: 'VIEWED',  tone: 'olive' },
    { primary: 'Dave Bernard',       secondary: 'EST-00108 · DRAFT',       amount: '$4,200',  tag: 'DRAFT',   tone: 'neutral' },
  ] : [
    { primary: 'Fuel — Esso',        secondary: '2026-05-14 · TRUCK 03',   amount: '$84',     tag: 'OK',      tone: 'neutral' },
    { primary: 'Materials — HD',     secondary: '2026-05-13 · OAK GROVE',  amount: '$412',    tag: 'OK',      tone: 'neutral' },
    { primary: 'Sub — Lin',          secondary: '2026-05-12 · PERRY ST',   amount: '$1,840',  tag: 'PENDING', tone: 'tan' },
  ];

  return (
    <div style={{ padding: '12px 20px 0' }}>
      {filter && (
        <div style={{
          display: 'flex', alignItems: 'center', gap: 8, marginBottom: 8,
        }}>
          <span style={{
            display: 'inline-flex', alignItems: 'center', gap: 6,
            padding: '4px 10px', borderRadius: T.rChip,
            border: `1px solid ${T.line}`, background: T.surfaceActive,
            fontFamily: T.mono, fontSize: 10, color: T.text,
            letterSpacing: '0.14em', textTransform: 'uppercase', fontWeight: 500,
          }}>
            {filter} <span style={{ color: T.textMute }}>×</span>
          </span>
        </div>
      )}
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
            position: 'relative',
          }}>
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
    </div>
  );
}

// ═══════════════════════════════════════════════════════
// FULL BOOKS SCREEN (Mission Deck)
// ═══════════════════════════════════════════════════════
function BooksScreenB({ activeCard = 0, period = SEED.period, segment = 'INVOICES', filter = null }) {
  const cardIds = ['P&L', 'CASH FLOW', 'A/R AGING', 'FORECAST', 'JOBS'];
  const scope   = activeCard === 2 ? { hint: 'ALL OPEN',  color: T.rose }
                : activeCard === 3 ? { hint: 'ACTIVE',    color: T.accent }
                                   : null;
  const CardEl   = [BCard_PL, BCard_Flow, BCard_AR, BCard_Forecast, BCard_Jobs][activeCard];
  const cardData = [SEED.pl, SEED.cashflow, SEED.ar, SEED.forecast, SEED.jobs][activeCard];

  return (
    <div style={{ position: 'absolute', inset: 0, background: T.bg, overflow: 'hidden' }}>
      <div aria-hidden style={{
        position: 'absolute', inset: 0, pointerEvents: 'none',
        background: 'radial-gradient(500px 360px at 88% 10%, rgba(111,148,176,0.07), transparent 65%)',
      }}/>
      <StatusBar/>
      <AppHeader actions={['search', 'flag']}/>

      <div style={{ position: 'absolute', top: 100, left: 0, right: 0, bottom: 83 }}>
        <BHeader
          label={cardIds[activeCard]}
          scopeHint={scope?.hint}
          scopeColor={scope?.color}
          period={period}
        />
        <CardEl data={cardData}/>
        <BDots index={activeCard} total={5}/>

        <div style={{ marginTop: 22 }}>
          <BSegments active={segment}/>
        </div>
        <BListPreview segment={segment} filter={filter}/>
      </div>

      <TabBar active="books"/>
    </div>
  );
}

Object.assign(window, {
  BooksScreenB,
  BCard_PL, BCard_Flow, BCard_AR, BCard_Forecast, BCard_Jobs,
  BSegments, BPill, BDots, BHeader, BTile, BListPreview,
});
