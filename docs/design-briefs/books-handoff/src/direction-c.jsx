// direction-c.jsx — "LEDGER"
// Editorial, typographic. Hairlines as primary structural element.
// Every number lives in a labeled row; charts are numeric tables with marks.
// Period pill is a minimalist hairline text-strip with chevron.
// Pagination is tick marks. The most "SpaceX readout" of the three.

// ─── Period pill (Ledger: hairline, no fill) ─────────────
function CPill({ label, short }) {
  return (
    <div style={{
      display: 'inline-flex', alignItems: 'center', gap: 8,
      padding: '6px 0 6px 12px',
      borderLeft: `1px solid ${T.line}`,
      fontFamily: T.mono, fontSize: 10.5, color: T.text, fontWeight: 500,
      letterSpacing: '0.18em', textTransform: 'uppercase', ...tnum,
    }}>
      <span style={{ color: T.textMute }}>SCOPE</span>
      <span>{label}</span>
      <ChevronDown size={9}/>
    </div>
  );
}

// ─── Carousel header (Ledger: editorial // SECTION) ─────
function CHeader({ label, scopeHint, scopeColor, period }) {
  return (
    <div style={{ padding: '14px 20px 0' }}>
      <div style={{
        display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between',
        paddingBottom: 12, borderBottom: `1px solid ${T.line}`,
      }}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
          <span style={{
            fontFamily: T.mono, fontSize: 9.5, color: T.textMute,
            letterSpacing: '0.20em', textTransform: 'uppercase',
          }}>// SECTION</span>
          <span style={{
            fontFamily: T.cake, fontWeight: 300, fontSize: 24, color: T.text,
            letterSpacing: '0.02em', textTransform: 'uppercase', lineHeight: 1,
          }}>{label}</span>
          {scopeHint && (
            <span style={{
              fontFamily: T.mono, fontSize: 9, color: scopeColor, fontWeight: 600,
              letterSpacing: '0.20em', textTransform: 'uppercase', marginTop: 2,
            }}>·· {scopeHint}</span>
          )}
        </div>
        <CPill label={period.label} short={period.short}/>
      </div>
    </div>
  );
}

// ─── Pagination (Ledger: tick marks at the bottom edge) ──
function CTicks({ index, total }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 14, justifyContent: 'space-between',
      padding: '22px 20px 0',
    }}>
      <span style={{
        fontFamily: T.mono, fontSize: 10, color: T.text,
        letterSpacing: '0.18em', ...tnum,
      }}>
        {String(index + 1).padStart(2, '0')}<span style={{ color: T.textMute }}> · {String(total).padStart(2, '0')}</span>
      </span>
      <div style={{
        display: 'flex', flex: 1, gap: 0, height: 12, alignItems: 'flex-end',
        marginLeft: 14,
      }}>
        {Array.from({ length: total }).map((_, i) => (
          <div key={i} style={{
            flex: 1, height: i === index ? 12 : 4,
            background: i === index ? T.text : T.textMute,
            marginRight: i < total - 1 ? 4 : 0,
            transition: `height ${T.dPanel}ms ${T.ease}`,
          }}/>
        ))}
      </div>
    </div>
  );
}

// ─── Stat row (Ledger: hairline-divided rows) ────────────
function CStat({ label, value, sub, color = T.text, drill }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'baseline', justifyContent: 'space-between',
      padding: '14px 0', borderBottom: `1px solid ${T.line}`,
    }}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
        <span style={{
          fontFamily: T.mono, fontSize: 10, color: T.text3,
          letterSpacing: '0.18em', textTransform: 'uppercase',
        }}>{label}</span>
        {sub && <span style={{
          fontFamily: T.mono, fontSize: 9.5, color: T.textMute,
          letterSpacing: '0.14em', textTransform: 'uppercase', ...tnum,
        }}>{sub}</span>}
      </div>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 8 }}>
        <span style={{
          fontFamily: T.mono, fontSize: 16, fontWeight: 500, color, ...tnum,
          letterSpacing: '-0.01em',
        }}>{value}</span>
        {drill && <span style={{ color: T.text3 }}><Arrow dir="right" size={9}/></span>}
      </div>
    </div>
  );
}

// ═══════════════════════════════════════════════════════
// CARD 1 — P&L (Ledger: hero left-aligned with delta caption, equation as hairline rows)
// ═══════════════════════════════════════════════════════
function CCard_PL({ data }) {
  return (
    <div style={{ padding: '24px 20px 0' }}>
      {/* Hero with stacked label/value */}
      <div style={{
        display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', gap: 12,
      }}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
          <span style={{
            fontFamily: T.mono, fontSize: 10, color: T.text3,
            letterSpacing: '0.20em', textTransform: 'uppercase',
          }}>NET CASH</span>
          <span style={{
            fontFamily: T.mohave, fontWeight: 300, fontSize: 52,
            color: T.text, ...tnum, letterSpacing: '-0.025em', lineHeight: 1,
          }}>{fmt$(data.netCash)}</span>
        </div>
        <div style={{
          display: 'flex', flexDirection: 'column', gap: 2, alignItems: 'flex-end',
          paddingBottom: 4,
        }}>
          <span style={{
            fontFamily: T.mono, fontSize: 9.5, color: T.text3,
            letterSpacing: '0.18em', textTransform: 'uppercase',
          }}>MARGIN</span>
          <span style={{
            fontFamily: T.mohave, fontWeight: 300, fontSize: 28, color: T.olive,
            ...tnum, letterSpacing: '-0.01em', lineHeight: 1,
          }}>{data.marginPct}%</span>
        </div>
      </div>

      {/* Hairline equation */}
      <div style={{ marginTop: 20 }}>
        <CStat label="PAYMENTS IN"  value={fmt$(data.payments, { sign: true })} color={T.oliveM}/>
        <CStat label="EXPENSES OUT" value={fmt$(-data.expenses)}                 color={T.tanM}/>
        <CStat label="OUTSTANDING"  value={fmt$(data.outstanding)} sub={`${data.outstandingCount} INVOICES`} drill/>
        <CStat label="FORECAST"     value={fmt$(data.forecast)}    sub={`${data.forecastCount} ESTIMATES`}    drill/>
      </div>
    </div>
  );
}

// ═══════════════════════════════════════════════════════
// CARD 2 — Cash flow (Ledger: tick-mark column chart, hairline gridlines)
// ═══════════════════════════════════════════════════════
function CCard_Flow({ data }) {
  const maxAbs = Math.max(...data.weeks.map(w => Math.max(w[1], -w[2])));
  const chartH = 110;
  const half = chartH / 2;

  return (
    <div style={{ padding: '24px 20px 0' }}>
      {/* Hero */}
      <div style={{ display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between' }}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
          <span style={{
            fontFamily: T.mono, fontSize: 10, color: T.text3,
            letterSpacing: '0.20em', textTransform: 'uppercase',
          }}>NET · {data.weeks.length}W</span>
          <span style={{
            fontFamily: T.mohave, fontWeight: 300, fontSize: 52,
            color: T.text, ...tnum, letterSpacing: '-0.025em', lineHeight: 1,
          }}>{fmt$(data.netCash)}</span>
        </div>
        <div style={{
          display: 'flex', flexDirection: 'column', gap: 6, alignItems: 'flex-end',
          paddingBottom: 4,
        }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <span style={{ width: 10, height: 2, background: T.oliveM }}/>
            <span style={{
              fontFamily: T.mono, fontSize: 9, color: T.text2, letterSpacing: '0.18em',
            }}>IN · {fmt$(data.weeks.reduce((s, w) => s + w[1], 0), { compact: true })}</span>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <span style={{ width: 10, height: 2, background: T.tanM }}/>
            <span style={{
              fontFamily: T.mono, fontSize: 9, color: T.text2, letterSpacing: '0.18em',
            }}>OUT · {fmt$(data.weeks.reduce((s, w) => s + w[2], 0), { compact: true })}</span>
          </div>
        </div>
      </div>

      {/* Chart — narrow columns, hairline */}
      <div style={{ marginTop: 20, position: 'relative', height: chartH }}>
        <div style={{ position: 'absolute', top: half, left: 0, right: 0, height: 1, background: T.line }}/>
        <div style={{
          position: 'absolute', inset: 0, display: 'grid',
          gridTemplateColumns: `repeat(${data.weeks.length}, 1fr)`,
          alignItems: 'center',
        }}>
          {data.weeks.map(([wk, inAmt, outAmt], i) => {
            const inH  = (inAmt  / maxAbs) * half;
            const outH = (-outAmt / maxAbs) * half;
            return (
              <div key={i} style={{
                position: 'relative', height: chartH,
              }}>
                <div style={{
                  position: 'absolute', bottom: half,
                  left: '50%', transform: 'translateX(-50%)',
                  width: 2, height: inH, background: T.oliveM,
                }}/>
                <div style={{
                  position: 'absolute', top: half,
                  left: '50%', transform: 'translateX(-50%)',
                  width: 2, height: outH, background: T.tanM,
                }}/>
                {/* tick at top of in-bar */}
                <div style={{
                  position: 'absolute', bottom: half + inH - 0.5,
                  left: '50%', transform: 'translateX(-50%)',
                  width: 8, height: 1, background: T.oliveM,
                }}/>
                <div style={{
                  position: 'absolute', top: half + outH - 0.5,
                  left: '50%', transform: 'translateX(-50%)',
                  width: 8, height: 1, background: T.tanM,
                }}/>
              </div>
            );
          })}
        </div>
      </div>

      {/* Week numeric strip */}
      <div style={{
        marginTop: 6, display: 'grid',
        gridTemplateColumns: `repeat(${data.weeks.length}, 1fr)`,
      }}>
        {data.weeks.map(([wk], i) => (
          <span key={i} style={{
            fontFamily: T.mono, fontSize: 8.5, color: T.textMute, textAlign: 'center',
            letterSpacing: '0.10em', ...tnum,
          }}>{wk}</span>
        ))}
      </div>

      {/* Stat rows */}
      <div style={{ marginTop: 14 }}>
        <CStat label="SALES"   value={fmt$(data.salesTotal, { compact: true })} sub="TRAILING"/>
        <CStat label="AVG/WK"  value={fmt$(data.avgPerWeek, { compact: true })} sub="PER WEEK"/>
        <CStat label="DAYS TO PAY" value={data.daysToPay.toFixed(1)}             sub="MEAN"     drill/>
      </div>
    </div>
  );
}

// ═══════════════════════════════════════════════════════
// CARD 3 — A/R Aging (Ledger: aging table with marks)
// ═══════════════════════════════════════════════════════
function CCard_AR({ data }) {
  const colorOf = (k) => k === 'olive' ? T.olive : k === 'fin-r' ? T.finReceivables : k === 'tan' ? T.tan : T.brick;
  const maxAmt = Math.max(...data.buckets.map(b => b.amount));

  return (
    <div style={{ padding: '24px 20px 0' }}>
      {/* Hero */}
      <div style={{ display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between' }}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
          <span style={{
            fontFamily: T.mono, fontSize: 10, color: T.rose,
            letterSpacing: '0.20em', textTransform: 'uppercase',
          }}>OUTSTANDING</span>
          <span style={{
            fontFamily: T.mohave, fontWeight: 300, fontSize: 52,
            color: T.rose, ...tnum, letterSpacing: '-0.025em', lineHeight: 1,
          }}>{fmt$(data.total)}</span>
        </div>
        <div style={{
          display: 'flex', flexDirection: 'column', gap: 4, alignItems: 'flex-end',
        }}>
          <span style={{
            fontFamily: T.mono, fontSize: 11, color: T.text, fontWeight: 500, ...tnum,
            letterSpacing: '0.12em',
          }}>{data.openCount} <span style={{ color: T.textMute }}>OPEN</span></span>
          <span style={{
            fontFamily: T.mono, fontSize: 11, color: T.rose, fontWeight: 500, ...tnum,
            letterSpacing: '0.12em',
          }}>{data.overdueCount} <span style={{ color: T.textMute }}>OVERDUE</span></span>
        </div>
      </div>

      {/* Aging table */}
      <div style={{ marginTop: 22 }}>
        <div style={{
          display: 'grid', gridTemplateColumns: '70px 1fr 80px',
          padding: '8px 0', borderBottom: `1px solid ${T.line}`,
          fontFamily: T.mono, fontSize: 9, color: T.textMute,
          letterSpacing: '0.18em', textTransform: 'uppercase',
        }}>
          <span>BUCKET</span>
          <span style={{ paddingLeft: 8 }}>SHARE</span>
          <span style={{ textAlign: 'right' }}>AMOUNT</span>
        </div>
        {data.buckets.map((b, i) => (
          <div key={i} style={{
            display: 'grid', gridTemplateColumns: '70px 1fr 80px',
            padding: '12px 0', borderBottom: `1px solid ${T.lineSoft}`,
            alignItems: 'center',
          }}>
            <span style={{
              fontFamily: T.mono, fontSize: 11, color: colorOf(b.color), fontWeight: 600,
              letterSpacing: '0.14em', ...tnum,
            }}>{b.range}</span>
            <div style={{ paddingLeft: 8, paddingRight: 12 }}>
              <div style={{
                height: 3, background: T.fillNeutralDim,
              }}>
                <div style={{
                  width: `${(b.amount / maxAmt) * 100}%`, height: '100%',
                  background: colorOf(b.color),
                }}/>
              </div>
            </div>
            <span style={{
              fontFamily: T.mono, fontSize: 13, fontWeight: 500, color: T.text, ...tnum,
              textAlign: 'right', letterSpacing: '-0.01em',
            }}>{fmt$(b.amount)}</span>
          </div>
        ))}
      </div>

      {/* Top chase as stat row */}
      <div style={{ marginTop: 6 }}>
        <CStat
          label="TOP CHASE"
          value={fmt$(data.topChase.amount)}
          sub={`${data.topChase.client.toUpperCase()} · ${data.topChase.daysOverdue}D`}
          color={T.rose}
          drill
        />
      </div>
    </div>
  );
}

// ═══════════════════════════════════════════════════════
// CARD 4 — Forecast (Ledger: stage table with weight column)
// ═══════════════════════════════════════════════════════
function CCard_Forecast({ data }) {
  const maxAmt = Math.max(...data.stages.map(s => s.amount));
  return (
    <div style={{ padding: '24px 20px 0' }}>
      {/* Hero */}
      <div style={{ display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between' }}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
          <span style={{
            fontFamily: T.mono, fontSize: 10, color: T.accent,
            letterSpacing: '0.20em', textTransform: 'uppercase',
          }}>WEIGHTED</span>
          <span style={{
            fontFamily: T.mohave, fontWeight: 300, fontSize: 52,
            color: T.accent, ...tnum, letterSpacing: '-0.025em', lineHeight: 1,
          }}>{fmt$(data.weighted)}</span>
        </div>
        <span style={{
          fontFamily: T.mono, fontSize: 11, color: T.text, fontWeight: 500, ...tnum,
          letterSpacing: '0.12em',
        }}>{data.activeCount} <span style={{ color: T.textMute }}>ACTIVE</span></span>
      </div>

      {/* Stage table */}
      <div style={{ marginTop: 22 }}>
        <div style={{
          display: 'grid', gridTemplateColumns: '110px 1fr 38px 76px',
          padding: '8px 0', borderBottom: `1px solid ${T.line}`,
          fontFamily: T.mono, fontSize: 9, color: T.textMute,
          letterSpacing: '0.18em', textTransform: 'uppercase',
        }}>
          <span>STAGE</span>
          <span style={{ paddingLeft: 8 }}>WEIGHT</span>
          <span style={{ textAlign: 'right' }}>P</span>
          <span style={{ textAlign: 'right' }}>VALUE</span>
        </div>
        {data.stages.map((s, i) => (
          <div key={i} style={{
            display: 'grid', gridTemplateColumns: '110px 1fr 38px 76px',
            padding: '11px 0', borderBottom: `1px solid ${T.lineSoft}`,
            alignItems: 'center',
          }}>
            <span style={{
              fontFamily: T.mono, fontSize: 10, color: T.text2, fontWeight: 500,
              letterSpacing: '0.14em', textTransform: 'uppercase',
            }}>{s.name}</span>
            <div style={{ paddingLeft: 8, paddingRight: 12 }}>
              <div style={{ height: 3, background: T.accentMuted }}>
                <div style={{
                  width: `${(s.amount / maxAmt) * 100}%`, height: '100%', background: T.accent,
                }}/>
              </div>
            </div>
            <span style={{
              fontFamily: T.mono, fontSize: 10, color: T.text3, ...tnum,
              textAlign: 'right', letterSpacing: '0.04em',
            }}>{Math.round(s.pct * 100)}%</span>
            <span style={{
              fontFamily: T.mono, fontSize: 12.5, fontWeight: 500, color: T.text, ...tnum,
              textAlign: 'right', letterSpacing: '-0.01em',
            }}>{fmt$(s.amount)}</span>
          </div>
        ))}
      </div>

      {/* Drill stats */}
      <div style={{ marginTop: 6 }}>
        <CStat label="CLOSE RATE" value={`${data.closeRate}%`}    sub="LAST 90D"   color={T.olive} drill/>
        <CStat label="STALE"      value={String(data.staleCount)} sub="> 14D IDLE"  color={T.tan}   drill/>
      </div>
    </div>
  );
}

// ═══════════════════════════════════════════════════════
// CARD 5 — Jobs (Ledger: rank table, diverging marks)
// ═══════════════════════════════════════════════════════
function CCard_Jobs({ data }) {
  const maxAbs = Math.max(...data.list.map(j => Math.abs(j.net)));
  return (
    <div style={{ padding: '24px 20px 0' }}>
      <div style={{
        display: 'flex', alignItems: 'baseline', justifyContent: 'space-between',
        paddingBottom: 12, borderBottom: `1px solid ${T.line}`,
      }}>
        <span style={{
          fontFamily: T.mono, fontSize: 10, color: T.text3,
          letterSpacing: '0.20em', textTransform: 'uppercase',
        }}>TOP 5 BY NET</span>
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 16 }}>
          <span style={{
            fontFamily: T.mono, fontSize: 11, color: T.olive, fontWeight: 600, ...tnum,
          }}>+{data.profitableCount}</span>
          <span style={{
            fontFamily: T.mono, fontSize: 11, color: T.rose, fontWeight: 600, ...tnum,
          }}>−{data.losersCount}</span>
        </div>
      </div>

      <div style={{ marginTop: 4 }}>
        {data.list.map((j, i) => {
          const positive = j.net >= 0;
          const widthPct = (Math.abs(j.net) / maxAbs) * 50;
          return (
            <div key={i} style={{
              display: 'grid', gridTemplateColumns: '22px 1fr 60px',
              padding: '14px 0 12px', borderBottom: i < data.list.length - 1 ? `1px solid ${T.lineSoft}` : 'none',
              alignItems: 'center', gap: 8,
            }}>
              <span style={{
                fontFamily: T.mono, fontSize: 10, color: T.textMute, ...tnum,
                letterSpacing: '0.10em',
              }}>{String(i + 1).padStart(2, '0')}</span>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 6, minWidth: 0 }}>
                <span style={{
                  fontFamily: T.mohave, fontSize: 14, fontWeight: 500, color: T.text,
                  whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
                }}>{j.name}</span>
                <div style={{ position: 'relative', height: 3 }}>
                  <div style={{
                    position: 'absolute', top: 0, bottom: 0, left: '50%', width: 1, background: T.line,
                  }}/>
                  <div style={{
                    position: 'absolute', top: 0, bottom: 0,
                    left: positive ? '50%' : `${50 - widthPct}%`,
                    width: `${widthPct}%`,
                    background: positive ? T.olive : T.rose,
                  }}/>
                </div>
              </div>
              <span style={{
                fontFamily: T.mono, fontSize: 13, fontWeight: 500,
                color: positive ? T.olive : T.rose, ...tnum,
                textAlign: 'right', letterSpacing: '-0.01em',
              }}>{fmt$(j.net, { sign: positive })}</span>
            </div>
          );
        })}
      </div>

      {/* Drill stat row */}
      <div style={{ marginTop: 6 }}>
        <CStat label="AVG MARGIN" value={`${data.avgMarginPct}%`} sub="ACROSS COMPLETE" color={T.text} drill/>
      </div>
    </div>
  );
}

// ═══════════════════════════════════════════════════════
// SEGMENTED CONTROL (Ledger: hairline tabs with bottom rule)
// ═══════════════════════════════════════════════════════
function CSegments({ active = 'INVOICES', options = ['INVOICES', 'ESTIMATES', 'EXPENSES'] }) {
  return (
    <div style={{
      display: 'grid', gridTemplateColumns: `repeat(${options.length}, 1fr)`,
      borderTop: `1px solid ${T.line}`,
      borderBottom: `1px solid ${T.line}`,
    }}>
      {options.map((opt, i) => {
        const isActive = opt === active;
        return (
          <div key={opt} style={{
            padding: '14px 0', position: 'relative',
            borderLeft: i > 0 ? `1px solid ${T.lineSoft}` : 'none',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            background: isActive ? T.surfaceHover : 'transparent',
          }}>
            <span style={{
              fontFamily: T.mono, fontSize: 11, fontWeight: isActive ? 600 : 500,
              color: isActive ? T.text : T.text3,
              letterSpacing: '0.16em', textTransform: 'uppercase',
            }}>{opt}</span>
            {isActive && (
              <div style={{
                position: 'absolute', top: -1, left: 0, right: 0,
                height: 2, background: T.text,
              }}/>
            )}
          </div>
        );
      })}
    </div>
  );
}

// ═══════════════════════════════════════════════════════
// LIST PREVIEW (Ledger: bare rows, hairline dividers, terminal-style)
// ═══════════════════════════════════════════════════════
function CListPreview({ segment = 'INVOICES', filter = null }) {
  const rows = segment === 'INVOICES' ? [
    { ref: 'INV-00284', name: 'Verity Projects',    meta: '71D OVERDUE', amount: '$6,400',  tag: 'OVERDUE', tone: 'rose' },
    { ref: 'INV-00301', name: 'Halcyon Builders',   meta: '94D OVERDUE', amount: '$3,400',  tag: 'OVERDUE', tone: 'rose' },
    { ref: 'INV-00298', name: 'Mara Lin',           meta: '42D OVERDUE', amount: '$3,200',  tag: 'OVERDUE', tone: 'rose' },
  ] : segment === 'ESTIMATES' ? [
    { ref: 'EST-00112', name: 'Scagliati Homes',    meta: 'SENT 3D',     amount: '$12,800', tag: 'SENT',    tone: 'tan' },
    { ref: 'EST-00109', name: 'Citygate Residence', meta: 'VIEWED',      amount: '$18,400', tag: 'VIEWED',  tone: 'olive' },
    { ref: 'EST-00108', name: 'Dave Bernard',       meta: 'DRAFT',       amount: '$4,200',  tag: 'DRAFT',   tone: 'neutral' },
  ] : [
    { ref: '2026-05-14', name: 'Fuel — Esso',       meta: 'TRUCK 03',    amount: '$84',     tag: 'OK',      tone: 'neutral' },
    { ref: '2026-05-13', name: 'Materials — HD',    meta: 'OAK GROVE',   amount: '$412',    tag: 'OK',      tone: 'neutral' },
    { ref: '2026-05-12', name: 'Sub — Lin',         meta: 'PERRY ST',    amount: '$1,840',  tag: 'PENDING', tone: 'tan' },
  ];

  return (
    <div>
      {filter && (
        <div style={{
          padding: '10px 20px', borderBottom: `1px solid ${T.lineSoft}`,
          display: 'flex', alignItems: 'center', gap: 8,
          background: T.surfaceInput,
        }}>
          <span style={{
            fontFamily: T.mono, fontSize: 9.5, color: T.text3,
            letterSpacing: '0.20em', textTransform: 'uppercase',
          }}>// FILTER</span>
          <span style={{
            fontFamily: T.mono, fontSize: 10, color: T.text, fontWeight: 600,
            letterSpacing: '0.14em', textTransform: 'uppercase',
          }}>{filter}</span>
          <span style={{ marginLeft: 'auto', color: T.text3,
            fontFamily: T.mono, fontSize: 10, letterSpacing: '0.10em',
          }}>×</span>
        </div>
      )}
      {rows.map((r, i) => (
        <div key={i} style={{
          padding: '14px 20px', borderBottom: `1px solid ${T.lineSoft}`,
          display: 'grid', gridTemplateColumns: '80px 1fr 70px 70px',
          gap: 10, alignItems: 'center',
        }}>
          <span style={{
            fontFamily: T.mono, fontSize: 9.5, color: T.text3,
            letterSpacing: '0.10em', ...tnum,
          }}>{r.ref}</span>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0 }}>
            <span style={{
              fontFamily: T.mohave, fontSize: 14, fontWeight: 500, color: T.text,
              whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
            }}>{r.name}</span>
            <span style={{
              fontFamily: T.mono, fontSize: 9, color: T.textMute,
              letterSpacing: '0.10em', textTransform: 'uppercase',
            }}>{r.meta}</span>
          </div>
          <ATag tone={r.tone}>{r.tag}</ATag>
          <span style={{
            fontFamily: T.mono, fontSize: 13, fontWeight: 500, color: T.text, ...tnum,
            textAlign: 'right',
          }}>{r.amount}</span>
        </div>
      ))}
    </div>
  );
}

// ═══════════════════════════════════════════════════════
// FULL BOOKS SCREEN (Ledger)
// ═══════════════════════════════════════════════════════
function BooksScreenC({ activeCard = 0, period = SEED.period, segment = 'INVOICES', filter = null }) {
  const cardIds = ['P&L', 'CASH FLOW', 'A/R', 'FORECAST', 'JOBS'];
  const scope   = activeCard === 2 ? { hint: 'ALL OPEN',  color: T.rose }
                : activeCard === 3 ? { hint: 'ACTIVE',    color: T.accent }
                                   : null;
  const CardEl   = [CCard_PL, CCard_Flow, CCard_AR, CCard_Forecast, CCard_Jobs][activeCard];
  const cardData = [SEED.pl, SEED.cashflow, SEED.ar, SEED.forecast, SEED.jobs][activeCard];

  return (
    <div style={{ position: 'absolute', inset: 0, background: T.bg, overflow: 'hidden' }}>
      <div aria-hidden style={{
        position: 'absolute', inset: 0, pointerEvents: 'none',
        background: 'radial-gradient(380px 280px at 10% 12%, rgba(196,168,104,0.04), transparent 65%)',
      }}/>
      <StatusBar/>
      <AppHeader actions={['search', 'flag']}/>

      <div style={{ position: 'absolute', top: 100, left: 0, right: 0, bottom: 83 }}>
        <CHeader
          label={cardIds[activeCard]}
          scopeHint={scope?.hint}
          scopeColor={scope?.color}
          period={period}
        />
        <CardEl data={cardData}/>
        <CTicks index={activeCard} total={5}/>

        <div style={{ marginTop: 24 }}>
          <CSegments active={segment}/>
        </div>
        <CListPreview segment={segment} filter={filter}/>
      </div>

      <TabBar active="books"/>
    </div>
  );
}

Object.assign(window, {
  BooksScreenC,
  CCard_PL, CCard_Flow, CCard_AR, CCard_Forecast, CCard_Jobs,
  CSegments, CPill, CTicks, CHeader, CStat, CListPreview,
});
