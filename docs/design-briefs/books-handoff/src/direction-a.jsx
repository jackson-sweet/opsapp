// direction-a.jsx — "TERMINAL"
// Dense, mono-forward, Bloomberg-esque. Hero number is small (32px) — context dominates.
// Charts are hairline. Drill tiles are inline strips with `→` chevron, not L2 cards.
// Period pill is a sharp 5px rectangle with a colon prefix (terminal-style).
// Dot pagination becomes a numeric position indicator: 01/05.

// ─── Period pill (Terminal: sharp 5px, "PERIOD :: 6M" form) ─────
function APill({ label, short }) {
  return (
    <div style={{
      display: 'inline-flex', alignItems: 'center', gap: 8,
      padding: '6px 10px', borderRadius: T.rBtn,
      border: `1px solid ${T.line}`, background: 'rgba(255,255,255,0.03)',
      fontFamily: T.mono, fontSize: 11, color: T.text,
      letterSpacing: '0.14em', textTransform: 'uppercase',
      ...tnum,
    }}>
      <span style={{ color: T.textMute }}>PERIOD ::</span>
      <span>{label}</span>
      <ChevronDown size={9}/>
    </div>
  );
}

// ─── Carousel header row ────────────────────────────────
function AHeader({ label, scopeHint, scopeColor, period }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      padding: '8px 20px 0',
    }}>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 10 }}>
        <span style={{
          fontFamily: T.mono, fontSize: 11, color: T.text,
          letterSpacing: '0.18em', textTransform: 'uppercase',
        }}>{label}</span>
        {scopeHint && (
          <span style={{
            fontFamily: T.mono, fontSize: 10, color: scopeColor,
            letterSpacing: '0.18em', textTransform: 'uppercase',
          }}>
            <span style={{ color: T.textMute }}>·</span> {scopeHint}
          </span>
        )}
      </div>
      <APill label={period.label} short={period.short}/>
    </div>
  );
}

// ─── Numeric pagination 01/05 + tick marks ──────────────
function APagination({ index, total }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 12,
      padding: '14px 20px 0',
    }}>
      <span style={{
        fontFamily: T.mono, fontSize: 10, color: T.text, letterSpacing: '0.14em', ...tnum,
      }}>{String(index + 1).padStart(2, '0')}<span style={{ color: T.textMute }}>/{String(total).padStart(2, '0')}</span></span>
      <div style={{ display: 'flex', gap: 4 }}>
        {Array.from({ length: total }).map((_, i) => (
          <div key={i} style={{
            width: i === index ? 18 : 10, height: 1.5,
            background: i === index ? T.text : T.textMute,
            transition: `width ${T.dPanel}ms ${T.ease}`,
          }}/>
        ))}
      </div>
    </div>
  );
}

// ─── Drill strip (Terminal: inline horizontal row, hairline only) ──
function ADrillStrip({ items }) {
  return (
    <div style={{
      display: 'grid', gridTemplateColumns: `repeat(${items.length}, 1fr)`,
      borderTop: `1px solid ${T.line}`,
      marginTop: 4,
    }}>
      {items.map((it, i) => (
        <div key={i} style={{
          padding: '14px 16px',
          borderRight: i < items.length - 1 ? `1px solid ${T.line}` : 'none',
          display: 'flex', flexDirection: 'column', gap: 6,
        }}>
          <div style={{
            display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          }}>
            <span style={{
              fontFamily: T.mono, fontSize: 9.5, color: T.text3,
              letterSpacing: '0.18em', textTransform: 'uppercase',
            }}>{it.label}</span>
            <span style={{ color: T.text3 }}><Arrow dir="right" size={9}/></span>
          </div>
          <div style={{
            fontFamily: T.mono, fontSize: 15, fontWeight: 500, color: it.color || T.text,
            ...tnum, letterSpacing: '-0.01em',
          }}>{it.value}</div>
          <div style={{
            fontFamily: T.mono, fontSize: 9.5, color: T.textMute,
            letterSpacing: '0.14em', textTransform: 'uppercase', ...tnum,
          }}>{it.sub}</div>
        </div>
      ))}
    </div>
  );
}

// ═══════════════════════════════════════════════════════
// CARD 1 — P&L (Terminal)
// ═══════════════════════════════════════════════════════
function ACard_PL({ data }) {
  return (
    <div style={{ padding: '24px 20px 0' }}>
      {/* Equation rows */}
      <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
        <ARow label="PAYMENTS IN"  value={fmt$(data.payments, { sign: true })} color={T.oliveM}/>
        <ARow label="EXPENSES OUT" value={fmt$(-data.expenses)}                color={T.tanM}/>
      </div>

      {/* Rule */}
      <div style={{ height: 1, background: T.line, margin: '14px 0 12px' }}/>

      {/* Net cash hero — small, right-aligned to match equation column */}
      <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between' }}>
        <span style={{
          fontFamily: T.mono, fontSize: 11, color: T.text,
          letterSpacing: '0.18em', textTransform: 'uppercase',
        }}>NET CASH</span>
        <span style={{
          fontFamily: T.mohave, fontWeight: 300, fontSize: 40,
          color: T.text, ...tnum, letterSpacing: '-0.02em', lineHeight: 1,
        }}>{fmt$(data.netCash)}</span>
      </div>

      {/* Margin meter */}
      <div style={{ marginTop: 16 }}>
        <div style={{
          height: 4, background: T.tanSoft, borderRadius: T.rBar, overflow: 'hidden',
          border: `1px solid ${T.tanLine}`,
        }}>
          <div style={{
            width: `${data.marginPct}%`, height: '100%',
            background: T.olive,
          }}/>
        </div>
        <div style={{
          marginTop: 8, display: 'flex', justifyContent: 'space-between',
          fontFamily: T.mono, fontSize: 10, letterSpacing: '0.18em', ...tnum,
        }}>
          <span style={{ color: T.text3 }}>MARGIN</span>
          <span style={{ color: T.olive }}>{data.marginPct}%</span>
        </div>
      </div>

      {/* Drill strip */}
      <div style={{ marginTop: 22 }}>
        <ADrillStrip items={[
          { label: 'OUTSTANDING', value: fmt$(data.outstanding), sub: `${data.outstandingCount} ITEMS`, color: T.text },
          { label: 'FORECAST',    value: fmt$(data.forecast),    sub: `${data.forecastCount} ITEMS`,    color: T.text },
        ]}/>
      </div>
    </div>
  );
}

function ARow({ label, value, color }) {
  return (
    <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between' }}>
      <span style={{
        fontFamily: T.mono, fontSize: 10.5, color: T.text3,
        letterSpacing: '0.18em', textTransform: 'uppercase',
      }}>{label}</span>
      <span style={{
        fontFamily: T.mono, fontSize: 14, fontWeight: 500, color, ...tnum,
        letterSpacing: '-0.01em',
      }}>{value}</span>
    </div>
  );
}

// ═══════════════════════════════════════════════════════
// CARD 2 — Cash Flow (Terminal: paired bars, hairline gridlines)
// ═══════════════════════════════════════════════════════
function ACard_Flow({ data }) {
  const maxAbs = Math.max(...data.weeks.map(w => Math.max(w[1], -w[2])));
  const chartH = 140;
  const half = chartH / 2;

  return (
    <div style={{ padding: '24px 20px 0' }}>
      {/* Hero net cash + legend */}
      <div style={{ display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between' }}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
          <span style={{
            fontFamily: T.mono, fontSize: 10, color: T.text3,
            letterSpacing: '0.18em', textTransform: 'uppercase',
          }}>NET CASH · {data.weeks.length}W</span>
          <span style={{
            fontFamily: T.mohave, fontWeight: 300, fontSize: 40,
            color: T.text, ...tnum, letterSpacing: '-0.02em', lineHeight: 1,
          }}>{fmt$(data.netCash)}</span>
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 4, alignItems: 'flex-end' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            <div style={{ width: 8, height: 2, background: T.oliveM }}/>
            <span style={{ fontFamily: T.mono, fontSize: 9, color: T.text2, letterSpacing: '0.16em' }}>IN</span>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            <div style={{ width: 8, height: 2, background: T.tanM }}/>
            <span style={{ fontFamily: T.mono, fontSize: 9, color: T.text2, letterSpacing: '0.16em' }}>OUT</span>
          </div>
        </div>
      </div>

      {/* Paired bar chart */}
      <div style={{ marginTop: 24, position: 'relative', height: chartH }}>
        {/* zero axis */}
        <div style={{ position: 'absolute', top: half, left: 0, right: 0, height: 1, background: T.line }}/>
        {/* hairline gridlines */}
        {[0.5, 1].map(f => (
          <React.Fragment key={f}>
            <div style={{ position: 'absolute', top: half - half * f, left: 0, right: 0, height: 1, background: T.lineSoft }}/>
            <div style={{ position: 'absolute', top: half + half * f, left: 0, right: 0, height: 1, background: T.lineSoft }}/>
          </React.Fragment>
        ))}
        {/* bars */}
        <div style={{
          position: 'absolute', inset: 0, display: 'grid',
          gridTemplateColumns: `repeat(${data.weeks.length}, 1fr)`,
          gap: 4, alignItems: 'center',
        }}>
          {data.weeks.map(([wk, inAmt, outAmt], i) => {
            const inH  = (inAmt  / maxAbs) * half;
            const outH = (-outAmt / maxAbs) * half;
            return (
              <div key={i} style={{
                position: 'relative', height: chartH,
                display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center',
              }}>
                <div style={{
                  position: 'absolute', bottom: half, width: '70%',
                  height: inH, background: T.oliveM,
                }}/>
                <div style={{
                  position: 'absolute', top: half, width: '70%',
                  height: outH, background: T.tanM,
                }}/>
              </div>
            );
          })}
        </div>
      </div>

      {/* Week labels under chart */}
      <div style={{
        marginTop: 8, display: 'grid',
        gridTemplateColumns: `repeat(${data.weeks.length}, 1fr)`, gap: 4,
      }}>
        {data.weeks.map(([wk], i) => (
          <span key={i} style={{
            fontFamily: T.mono, fontSize: 9, color: T.textMute, textAlign: 'center',
            letterSpacing: '0.10em', ...tnum,
          }}>{wk}</span>
        ))}
      </div>

      {/* Drill strip — sales / avg / days */}
      <div style={{ marginTop: 22 }}>
        <ADrillStrip items={[
          { label: 'SALES',  value: fmt$(data.salesTotal, { compact: true }), sub: 'TRAILING' },
          { label: 'AVG/WK', value: fmt$(data.avgPerWeek, { compact: true }), sub: 'PER WEEK' },
          { label: 'DAYS',   value: data.daysToPay.toFixed(1),               sub: 'TO PAY' },
        ]}/>
      </div>
    </div>
  );
}

// ═══════════════════════════════════════════════════════
// CARD 3 — A/R Aging (Terminal: aging buckets as a 4-segment stacked bar + per-bucket rows)
// ═══════════════════════════════════════════════════════
function ACard_AR({ data }) {
  const total = data.buckets.reduce((s, b) => s + b.amount, 0);
  const colorOf = (k) => k === 'olive' ? T.olive : k === 'fin-r' ? T.finReceivables : k === 'tan' ? T.tan : T.brick;

  return (
    <div style={{ padding: '24px 20px 0' }}>
      {/* Hero */}
      <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between' }}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
          <span style={{
            fontFamily: T.mono, fontSize: 10, color: T.rose,
            letterSpacing: '0.18em', textTransform: 'uppercase',
          }}>TOTAL OUTSTANDING</span>
          <span style={{
            fontFamily: T.mohave, fontWeight: 300, fontSize: 40,
            color: T.rose, ...tnum, letterSpacing: '-0.02em', lineHeight: 1,
          }}>{fmt$(data.total)}</span>
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 4, alignItems: 'flex-end' }}>
          <span style={{
            fontFamily: T.mono, fontSize: 11, fontWeight: 500, color: T.text, ...tnum,
            letterSpacing: '0.12em',
          }}>{data.openCount} <span style={{ color: T.textMute }}>OPEN</span></span>
          <span style={{
            fontFamily: T.mono, fontSize: 11, fontWeight: 500, color: T.rose, ...tnum,
            letterSpacing: '0.12em',
          }}>{data.overdueCount} <span style={{ color: T.textMute }}>OVERDUE</span></span>
        </div>
      </div>

      {/* Stacked composition bar */}
      <div style={{ marginTop: 24 }}>
        <span style={{
          fontFamily: T.mono, fontSize: 10, color: T.text3,
          letterSpacing: '0.18em', textTransform: 'uppercase',
        }}>COMPOSITION</span>
        <div style={{ display: 'flex', height: 6, marginTop: 8, gap: 2 }}>
          {data.buckets.map((b, i) => (
            <div key={i} style={{
              flex: b.amount / total, background: colorOf(b.color), height: '100%',
            }}/>
          ))}
        </div>
      </div>

      {/* Bucket rows */}
      <div style={{ marginTop: 18, display: 'flex', flexDirection: 'column', gap: 10 }}>
        {data.buckets.map((b, i) => (
          <div key={i} style={{
            display: 'grid', gridTemplateColumns: '64px 1fr 70px', gap: 12, alignItems: 'center',
          }}>
            <span style={{
              fontFamily: T.mono, fontSize: 10.5, color: T.text2,
              letterSpacing: '0.14em', ...tnum,
            }}>{b.range}</span>
            <div style={{
              height: 4, background: T.fillNeutralDim, borderRadius: T.rBar, overflow: 'hidden',
            }}>
              <div style={{
                width: `${(b.amount / Math.max(...data.buckets.map(x => x.amount))) * 100}%`,
                height: '100%', background: colorOf(b.color),
              }}/>
            </div>
            <span style={{
              fontFamily: T.mono, fontSize: 12, fontWeight: 500, color: T.text, ...tnum,
              textAlign: 'right', letterSpacing: '-0.01em',
            }}>{fmt$(b.amount)}</span>
          </div>
        ))}
      </div>

      {/* Top chase strip */}
      <div style={{ marginTop: 22 }}>
        <ADrillStrip items={[
          { label: 'TOP CHASE', value: fmt$(data.topChase.amount),
            sub: `${data.topChase.client.toUpperCase()} · ${data.topChase.daysOverdue}D`, color: T.rose },
        ]}/>
      </div>
    </div>
  );
}

// ═══════════════════════════════════════════════════════
// CARD 4 — Forecast (Terminal: stage-by-stage with weight %)
// ═══════════════════════════════════════════════════════
function ACard_Forecast({ data }) {
  const maxAmt = Math.max(...data.stages.map(s => s.amount));
  return (
    <div style={{ padding: '24px 20px 0' }}>
      {/* Hero */}
      <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between' }}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
          <span style={{
            fontFamily: T.mono, fontSize: 10, color: T.accent,
            letterSpacing: '0.18em', textTransform: 'uppercase',
          }}>WEIGHTED FORECAST</span>
          <span style={{
            fontFamily: T.mohave, fontWeight: 300, fontSize: 40,
            color: T.accent, ...tnum, letterSpacing: '-0.02em', lineHeight: 1,
          }}>{fmt$(data.weighted)}</span>
        </div>
        <span style={{
          fontFamily: T.mono, fontSize: 11, fontWeight: 500, color: T.text, ...tnum,
          letterSpacing: '0.12em',
        }}>{data.activeCount} <span style={{ color: T.textMute }}>ACTIVE</span></span>
      </div>

      {/* Stage rows */}
      <div style={{ marginTop: 22, display: 'flex', flexDirection: 'column', gap: 10 }}>
        {data.stages.map((s, i) => (
          <div key={i} style={{
            display: 'grid', gridTemplateColumns: '108px 1fr 70px', gap: 12, alignItems: 'center',
          }}>
            <span style={{
              fontFamily: T.mono, fontSize: 10, color: T.text2,
              letterSpacing: '0.14em', textTransform: 'uppercase',
            }}>{s.name}</span>
            <div style={{
              height: 4, background: T.accentMuted, borderRadius: T.rBar, overflow: 'hidden',
            }}>
              <div style={{
                width: `${(s.amount / maxAmt) * 100}%`, height: '100%', background: T.accent,
              }}/>
            </div>
            <span style={{
              fontFamily: T.mono, fontSize: 12, fontWeight: 500, color: T.text, ...tnum,
              textAlign: 'right', letterSpacing: '-0.01em',
            }}>{fmt$(s.amount)}</span>
          </div>
        ))}
      </div>

      {/* Drill strip */}
      <div style={{ marginTop: 22 }}>
        <ADrillStrip items={[
          { label: 'CLOSE RATE', value: `${data.closeRate}%`,     sub: 'LAST 90D', color: T.olive },
          { label: 'STALE',      value: String(data.staleCount),  sub: '> 14D IDLE', color: T.tan },
        ]}/>
      </div>
    </div>
  );
}

// ═══════════════════════════════════════════════════════
// CARD 5 — Jobs (Terminal: diverging bars centered on zero axis)
// ═══════════════════════════════════════════════════════
function ACard_Jobs({ data }) {
  const maxAbs = Math.max(...data.list.map(j => Math.abs(j.net)));
  return (
    <div style={{ padding: '24px 20px 0' }}>
      <span style={{
        fontFamily: T.mono, fontSize: 10, color: T.text3,
        letterSpacing: '0.18em', textTransform: 'uppercase',
      }}>TOP 5 BY NET · DIVERGING</span>

      <div style={{ marginTop: 14, display: 'flex', flexDirection: 'column', gap: 8 }}>
        {data.list.map((j, i) => {
          const positive = j.net >= 0;
          const widthPct = (Math.abs(j.net) / maxAbs) * 50; // half-width per side
          return (
            <div key={i} style={{
              display: 'grid', gridTemplateColumns: '110px 1fr 78px', gap: 12, alignItems: 'center',
            }}>
              <span style={{
                fontFamily: T.mohave, fontWeight: 500, fontSize: 12, color: T.text,
                whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
              }}>{j.name}</span>
              {/* diverging chart cell */}
              <div style={{ position: 'relative', height: 4 }}>
                {/* zero axis */}
                <div style={{
                  position: 'absolute', top: 0, bottom: 0, left: '50%', width: 1,
                  background: T.line,
                }}/>
                {/* bar */}
                <div style={{
                  position: 'absolute', top: 0, bottom: 0,
                  left: positive ? '50%' : `${50 - widthPct}%`,
                  width: `${widthPct}%`,
                  background: positive ? T.olive : T.rose,
                }}/>
              </div>
              <span style={{
                fontFamily: T.mono, fontSize: 12, fontWeight: 500,
                color: positive ? T.olive : T.rose, ...tnum,
                textAlign: 'right', letterSpacing: '-0.01em',
              }}>{fmt$(j.net, { sign: positive })}</span>
            </div>
          );
        })}
      </div>

      {/* Drill strip — 3 tiles */}
      <div style={{ marginTop: 22 }}>
        <ADrillStrip items={[
          { label: 'PROFITABLE',  value: String(data.profitableCount), sub: 'JOBS',  color: T.olive },
          { label: 'AVG MARGIN', value: `${data.avgMarginPct}%`,       sub: 'MEAN',   color: T.text },
          { label: 'LOSERS',      value: String(data.losersCount),     sub: 'JOBS',   color: T.rose },
        ]}/>
      </div>
    </div>
  );
}

// ═══════════════════════════════════════════════════════
// SEGMENTED CONTROL (Terminal: white underline, no accent)
// ═══════════════════════════════════════════════════════
function ASegments({ active = 'INVOICES', options = ['INVOICES', 'ESTIMATES', 'EXPENSES'] }) {
  return (
    <div style={{
      display: 'flex', borderBottom: `1px solid ${T.line}`,
      padding: '0 20px',
    }}>
      {options.map(opt => {
        const isActive = opt === active;
        return (
          <div key={opt} style={{
            flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 8,
            padding: '12px 0', position: 'relative',
          }}>
            <span style={{
              fontFamily: T.mono, fontSize: 11,
              color: isActive ? T.text : T.text3,
              letterSpacing: '0.16em', textTransform: 'uppercase',
            }}>{opt}</span>
            <div style={{
              position: 'absolute', left: '10%', right: '10%', bottom: -1,
              height: 2, background: isActive ? T.text : 'transparent',
              transition: `background ${T.dPanel}ms ${T.ease}`,
            }}/>
          </div>
        );
      })}
    </div>
  );
}

// ═══════════════════════════════════════════════════════
// LIST PREVIEW BELOW SEGMENTED (3 rows — gives sense of scale)
// ═══════════════════════════════════════════════════════
function AListPreview({ segment = 'INVOICES', filter = null }) {
  const rows = segment === 'INVOICES' ? [
    { primary: 'Verity Projects',    secondary: 'INV-00284 · 71D OVERDUE',  amount: '$6,400',  tag: 'OVERDUE', tone: 'rose' },
    { primary: 'Halcyon Builders',   secondary: 'INV-00301 · 94D OVERDUE',  amount: '$3,400',  tag: 'OVERDUE', tone: 'rose' },
    { primary: 'Mara Lin',           secondary: 'INV-00298 · 42D OVERDUE',  amount: '$3,200',  tag: 'OVERDUE', tone: 'rose' },
    { primary: 'Joel Lioudakis',     secondary: 'INV-00276 · DUE IN 6D',    amount: '$2,200',  tag: 'OPEN',    tone: 'neutral' },
  ] : segment === 'ESTIMATES' ? [
    { primary: 'Scagliati Homes',    secondary: 'EST-00112 · SENT 3D AGO',  amount: '$12,800', tag: 'SENT',    tone: 'tan' },
    { primary: 'Citygate Residence', secondary: 'EST-00109 · VIEWED',       amount: '$18,400', tag: 'VIEWED',  tone: 'olive' },
    { primary: 'Dave Bernard',       secondary: 'EST-00108 · DRAFT',        amount: '$4,200',  tag: 'DRAFT',   tone: 'neutral' },
    { primary: 'M Free',             secondary: 'EST-00107 · EXPIRED',      amount: '$3,500',  tag: 'EXPIRED', tone: 'rose' },
  ] : [
    { primary: 'Fuel — Esso',        secondary: '2026-05-14 · TRUCK 03',    amount: '$84',     tag: 'OK',      tone: 'neutral' },
    { primary: 'Materials — Home Depot', secondary: '2026-05-13 · OAK GROVE', amount: '$412',  tag: 'OK',      tone: 'neutral' },
    { primary: 'Subcontractor — Lin', secondary: '2026-05-12 · PERRY ST',  amount: '$1,840',  tag: 'PENDING', tone: 'tan' },
    { primary: 'Equipment — rent',   secondary: '2026-05-11 · SHARED',      amount: '$220',    tag: 'OK',      tone: 'neutral' },
  ];

  return (
    <div style={{ padding: '0 20px' }}>
      {filter && (
        <div style={{
          display: 'flex', alignItems: 'center', gap: 8,
          padding: '10px 0', borderBottom: `1px solid ${T.lineSoft}`,
        }}>
          <span style={{
            fontFamily: T.mono, fontSize: 10, color: T.text3,
            letterSpacing: '0.16em', textTransform: 'uppercase',
          }}>FILTER ::</span>
          <span style={{
            display: 'inline-flex', alignItems: 'center', gap: 6,
            padding: '4px 8px', borderRadius: T.rChip,
            border: `1px solid ${T.line}`, background: T.surfaceActive,
            fontFamily: T.mono, fontSize: 10, color: T.text,
            letterSpacing: '0.14em', textTransform: 'uppercase',
          }}>
            {filter} <span style={{ color: T.textMute }}>×</span>
          </span>
        </div>
      )}
      {rows.map((r, i) => (
        <div key={i} style={{
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          padding: '14px 0', borderBottom: i < rows.length - 1 ? `1px solid ${T.lineSoft}` : 'none',
        }}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 4, minWidth: 0, flex: 1 }}>
            <span style={{
              fontFamily: T.mohave, fontSize: 15, fontWeight: 400, color: T.text,
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
  );
}

function ATag({ children, tone = 'neutral' }) {
  const [c, bg, bd] =
    tone === 'olive' ? [T.oliveM, 'rgba(157,181,130,0.32)', 'rgba(157,181,130,0.88)']
  : tone === 'tan'   ? [T.tanM,   'rgba(196,168,104,0.32)', 'rgba(196,168,104,0.88)']
  : tone === 'rose'  ? [T.roseM,  'rgba(181,130,137,0.32)', 'rgba(181,130,137,0.88)']
  :                    [T.text2,  'rgba(255,255,255,0.05)', T.line];
  return (
    <span style={{
      fontFamily: T.mono, fontSize: 9.5, fontWeight: 600,
      letterSpacing: '0.14em', textTransform: 'uppercase',
      padding: '2px 6px', borderRadius: T.rChip,
      border: `1px solid ${bd}`, background: bg, color: c,
    }}>{children}</span>
  );
}

// ═══════════════════════════════════════════════════════
// FULL BOOKS SCREEN (Terminal) — composes all the pieces
// activeCard: 0..4   period: SEED period object   segment: 'INVOICES'|'ESTIMATES'|'EXPENSES'
// ═══════════════════════════════════════════════════════
function BooksScreenA({ activeCard = 0, period = SEED.period, segment = 'INVOICES', filter = null }) {
  const cardIds   = ['P&L', 'CASH FLOW', 'A/R', 'FORECAST', 'JOBS'];
  const scope     = activeCard === 2 ? { hint: 'ALL OPEN',  color: T.rose }
                  : activeCard === 3 ? { hint: 'ACTIVE',    color: T.accent }
                                     : null;
  const CardEl    = [ACard_PL, ACard_Flow, ACard_AR, ACard_Forecast, ACard_Jobs][activeCard];
  const cardData  = [SEED.pl, SEED.cashflow, SEED.ar, SEED.forecast, SEED.jobs][activeCard];

  return (
    <div style={{ position: 'absolute', inset: 0, background: T.bg, overflow: 'hidden' }}>
      {/* Atmosphere: single subtle glow */}
      <div aria-hidden style={{
        position: 'absolute', inset: 0, pointerEvents: 'none',
        background: 'radial-gradient(420px 320px at 90% 8%, rgba(111,148,176,0.06), transparent 65%)',
      }}/>
      <StatusBar/>
      <AppHeader actions={['search', 'flag']}/>

      <div style={{ position: 'absolute', top: 100, left: 0, right: 0, bottom: 83 }}>
        {/* Inline header */}
        <AHeader
          label={cardIds[activeCard]}
          scopeHint={scope?.hint}
          scopeColor={scope?.color}
          period={period}
        />

        {/* Active card */}
        <CardEl data={cardData}/>

        {/* Pagination */}
        <APagination index={activeCard} total={5}/>

        {/* Segmented control */}
        <div style={{ marginTop: 28 }}>
          <ASegments active={segment}/>
        </div>

        {/* List preview */}
        <div style={{ paddingTop: 8 }}>
          <AListPreview segment={segment} filter={filter}/>
        </div>
      </div>

      <TabBar active="books"/>
    </div>
  );
}

Object.assign(window, {
  BooksScreenA,
  ACard_PL, ACard_Flow, ACard_AR, ACard_Forecast, ACard_Jobs,
  ASegments, APill, APagination, AHeader, ATag, AListPreview, ADrillStrip,
});
