// handoff.jsx — Single-page handoff sheet: tokens, spacing, motion.
// Designed for export — every value engineers will need is on one frame.

function SwatchRow({ label, hex, alpha, use, sub }) {
  return (
    <div style={{
      display: 'grid', gridTemplateColumns: '48px 1fr 130px 1fr',
      gap: 14, alignItems: 'center',
      padding: '10px 0', borderBottom: `1px solid ${T.lineSoft}`,
    }}>
      <div style={{
        width: 48, height: 32, borderRadius: T.rL2,
        background: hex, border: `1px solid ${T.line}`,
      }}/>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
        <span style={{
          fontFamily: T.mono, fontSize: 11, fontWeight: 500, color: T.text,
          letterSpacing: '0.10em', textTransform: 'uppercase',
        }}>{label}</span>
        {sub && <span style={{
          fontFamily: T.mono, fontSize: 9.5, color: T.textMute,
          letterSpacing: '0.10em',
        }}>{sub}</span>}
      </div>
      <span style={{
        fontFamily: T.mono, fontSize: 11, color: T.text, ...tnum,
      }}>{hex}</span>
      <span style={{
        fontFamily: T.mohave, fontSize: 12, color: T.text2, lineHeight: 1.4,
      }}>{use}</span>
    </div>
  );
}

function TableRow({ cells, header = false }) {
  return (
    <div style={{
      display: 'grid', gridTemplateColumns: cells.cols || '1fr 110px 1fr',
      gap: 12, padding: '8px 0',
      borderBottom: `1px solid ${header ? T.line : T.lineSoft}`,
      fontFamily: T.mono, fontSize: header ? 9.5 : 11,
      color: header ? T.textMute : T.text,
      letterSpacing: header ? '0.18em' : '0',
      textTransform: header ? 'uppercase' : 'none',
      ...tnum,
    }}>
      {cells.values.map((v, i) => (
        <span key={i} style={{
          color: i === 0 ? (header ? T.textMute : T.text2) : T.text,
          fontWeight: i === 1 ? 500 : 400,
        }}>{v}</span>
      ))}
    </div>
  );
}

function HandoffSheet() {
  return (
    <div style={{
      width: 1280, padding: '48px 56px',
      background: T.bg, color: T.text,
      fontFamily: T.mohave,
    }}>
      {/* Header */}
      <div style={{
        borderBottom: `1px solid ${T.line}`, paddingBottom: 24, marginBottom: 36,
        display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between',
      }}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
          <span style={{
            fontFamily: T.mono, fontSize: 11, color: T.textMute,
            letterSpacing: '0.20em', textTransform: 'uppercase',
          }}>// BOOKS TAB · HANDOFF SHEET</span>
          <h1 style={{
            margin: 0, fontFamily: T.cake, fontWeight: 300, fontSize: 48,
            color: T.text, textTransform: 'uppercase', letterSpacing: '0.01em', lineHeight: 1,
          }}>TOKENS · SPACING · MOTION</h1>
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 4, alignItems: 'flex-end' }}>
          <span style={{
            fontFamily: T.mono, fontSize: 10, color: T.text3,
            letterSpacing: '0.18em', textTransform: 'uppercase',
          }}>V1 · 2026-05-19</span>
          <span style={{
            fontFamily: T.mono, fontSize: 10, color: T.textMute,
            letterSpacing: '0.18em', textTransform: 'uppercase',
          }}>iPhone 14/15 PRO · 390 × 844 PT</span>
        </div>
      </div>

      {/* Three columns of token tables */}
      <div style={{ display: 'grid', gridTemplateColumns: '1.2fr 1fr 1fr', gap: 40 }}>

        {/* ─── COLORS ─── */}
        <div>
          <Section title="// COLORS"/>

          <SubSection title="Canvas + Text">
            <SwatchRow label="--bg"      hex="#000000" use="The canvas. Pure black, the absence of material."/>
            <SwatchRow label="--text"    hex="#EDEDED" use="Primary text, hero numbers, active state."/>
            <SwatchRow label="--text-2"  hex="#B5B5B5" use="Secondary text, labels."/>
            <SwatchRow label="--text-3"  hex="#8A8A8A" use="Tertiary metadata, axis ticks."/>
            <SwatchRow label="--text-mute" hex="#6A6A6A" use="Decorative only — `//` slashes, separators."/>
          </SubSection>

          <SubSection title="Accent — Steel Blue">
            <SwatchRow label="--ops-accent"        hex="#6F94B0" use="Primary CTA fill, focus ring, Card 4 forecast bars. Nothing else."/>
            <SwatchRow label="--ops-accent-muted"  hex="rgba(111,148,176,0.15)" use="Card 4 bar tracks." sub="0.15 ALPHA"/>
          </SubSection>

          <SubSection title="Earth-tone Semantic">
            <SwatchRow label="--olive" hex="#9DB582" use="Success, positive delta, in-bars, profitable."/>
            <SwatchRow label="--tan"   hex="#C4A868" use="Attention, expenses, expiring."/>
            <SwatchRow label="--rose"  hex="#B58289" use="Error, overdue, cost, losers."/>
            <SwatchRow label="--brick" hex="#93321A" use="Destructive borders/dots, 90+ overdue bucket."/>
          </SubSection>

          <SubSection title="Financial Ramp (A/R aging buckets)">
            <SwatchRow label="0–30D"  hex="#9DB582" sub="--olive"          use="Healthy receivables."/>
            <SwatchRow label="31–60D" hex="#D4A574" sub="--fin-receivables" use="Approaching attention."/>
            <SwatchRow label="61–90D" hex="#C4A868" sub="--tan"             use="Past due, escalating."/>
            <SwatchRow label="90D+"   hex="#93321A" sub="--brick"           use="Critical, requires chase."/>
          </SubSection>

          <SubSection title="Surfaces">
            <SwatchRow label="--glass"       hex="rgba(18,18,20,0.58)" use="L1 section cards (list wrappers, sheets). 28px blur."/>
            <SwatchRow label="--glass-dense" hex="rgba(18,18,20,0.78)" use="L2 modals, dropdowns, period menu."/>
            <SwatchRow label="--nested"      hex="rgba(255,255,255,0.04)" use="L2 drill tiles inside carousel cards."/>
            <SwatchRow label="--line"        hex="rgba(255,255,255,0.10)" use="Standard hairline border."/>
            <SwatchRow label="--line-soft"   hex="rgba(255,255,255,0.06)" use="Internal row dividers."/>
          </SubSection>
        </div>

        {/* ─── TYPOGRAPHY ─── */}
        <div>
          <Section title="// TYPOGRAPHY"/>

          <SubSection title="Families · One job each">
            <TypeSample family={T.cake}   size={24} weight={300} caps>CAKE MONO 300 · DISPLAY VOICE</TypeSample>
            <TypeSample family={T.mohave} size={20} weight={300}>Mohave 300 · Body &amp; hero numbers</TypeSample>
            <TypeSample family={T.mono}   size={13} weight={500}>JetBrains Mono · 142,800.00</TypeSample>
          </SubSection>

          <SubSection title="Mobile Type Scale">
            <TypeRow role="HERO NUMBER"       family="Mohave 300"    size="40–60px" use="Net cash, total outstanding, weighted forecast"/>
            <TypeRow role="SCREEN TITLE"      family="Cake Mono 300" size="28px"    use="// BOOKS — AppHeader"/>
            <TypeRow role="CARD HEADER LABEL" family="Cake Mono 300" size="16px"    use="P&amp;L, CASH FLOW, etc. (Direction B)"/>
            <TypeRow role="CARD HEADER (Term)" family="JetBrains Mono" size="11px / 0.18em" use="// SECTION (Direction A)"/>
            <TypeRow role="TILE LABEL"        family="JetBrains Mono 500" size="9.5px / 0.18em" use="OUTSTANDING, FORECAST"/>
            <TypeRow role="TILE VALUE"        family="JetBrains Mono 500" size="14–18px" use="Tile numeric values"/>
            <TypeRow role="BODY / ROW PRIMARY" family="Mohave 400–500" size="14–15px" use="Client names, list rows"/>
            <TypeRow role="METADATA / META"   family="JetBrains Mono"      size="10–11px / 0.10em" use="Timestamps, refs, axis labels"/>
            <TypeRow role="TAG / BADGE"       family="JetBrains Mono 600"  size="9.5–10px / 0.14em" use="Status tags (mobile contrast)"/>
            <TypeRow role="BUTTON LABEL"      family="Cake Mono 300"       size="13–14px" use="Primary CTA"/>
            <TypeRow role="TAB BAR LABEL"     family="JetBrains Mono"      size="9px / 0.14em" use="Bottom tab bar"/>
          </SubSection>

          <SubSection title="Number Discipline">
            <p style={{
              margin: 0, fontFamily: T.mohave, fontSize: 13, color: T.text2, lineHeight: 1.6,
            }}>
              Numbers are <strong style={{ color: T.text }}>always</strong> JetBrains Mono.
              Always tabular-lining + slashed zero:
              <code style={{ marginLeft: 8, fontFamily: T.mono, fontSize: 12, color: T.text }}>font-feature-settings: "tnum" 1, "zero" 1</code>.
              Hero numbers in Mohave 300 also use tabular features. 11px floor — no exceptions.
            </p>
          </SubSection>
        </div>

        {/* ─── SPACING / RADII / MOTION ─── */}
        <div>
          <Section title="// SPACING · RADII · MOTION"/>

          <SubSection title="Spacing (8px grid)">
            <SpacingRow token="--m-canvas-x"           value="20px" use="Horizontal canvas padding"/>
            <SpacingRow token="--m-card-inset"         value="16px" use="Internal card padding"/>
            <SpacingRow token="--m-card-inset-tight"   value="12px" use="L2 nested card padding"/>
            <SpacingRow token="--m-section-gap"        value="24px" use="Between major sections"/>
            <SpacingRow token="--m-card-gap"           value="8px"  use="Between L2 tiles"/>
            <SpacingRow token="hero ↔ pagination"      value="20px" use="From card content to dot row"/>
            <SpacingRow token="pagination ↔ segments"  value="22px" use="From dots to segmented control"/>
          </SubSection>

          <SubSection title="Border Radius">
            <RadiusSample label="L1 panel"        value={10}/>
            <RadiusSample label="L2 nested tile"  value={6}/>
            <RadiusSample label="Period pill"     value={12}/>
            <RadiusSample label="Button / segment" value={5}/>
            <RadiusSample label="Tag / chip"      value={4}/>
            <RadiusSample label="Progress bar"    value={2}/>
          </SubSection>

          <SubSection title="Motion · One easing curve">
            <p style={{
              margin: '0 0 8px', fontFamily: T.mono, fontSize: 11, color: T.text,
              letterSpacing: '0.10em',
            }}>cubic-bezier(0.22, 1, 0.36, 1)</p>
            <p style={{
              margin: '0 0 16px', fontFamily: T.mohave, fontSize: 12, color: T.text3, lineHeight: 1.5,
            }}>No spring. No bounce. Things move with conviction and stop with conviction.</p>
            <MotionRow event="Card swap (carousel snap)"  duration="200ms" detail="containerRelativeFrame, paging"/>
            <MotionRow event="Hero collapse on scroll"    duration="200ms" detail="opacity + height crossfade"/>
            <MotionRow event="Dot pagination (B)"         duration="200ms" detail="width 6 → 22, capsule grow"/>
            <MotionRow event="Tab indicator (A,C)"        duration="200ms" detail="background + border opacity"/>
            <MotionRow event="Period menu open"           duration="200ms" detail="opacity + 8px translateY, scrim 200ms"/>
            <MotionRow event="Half-sheet rise"            duration="250ms" detail="translateY from 100% → 0"/>
            <MotionRow event="Half-sheet dismiss"         duration="200ms" detail="snappier exit"/>
            <MotionRow event="Tile press"                 duration="100ms / 150ms" detail="bg tint in / out"/>
            <MotionRow event="Hero count-up"              duration="800ms" detail="number ramps. Optional, skip on perf budget"/>
            <MotionRow event="Bar chart grow-in"          duration="400–600ms" detail="staggered + 50ms per bar"/>
            <MotionRow event="Reduced motion"             duration="150ms" detail="all → opacity crossfade. Final values, no animation"/>
          </SubSection>
        </div>
      </div>

      {/* Spacing diagram */}
      <div style={{ marginTop: 48, paddingTop: 24, borderTop: `1px solid ${T.line}` }}>
        <Section title="// SPACING DIAGRAM · CAROUSEL HERO"/>
        <div style={{
          display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 40, marginTop: 20,
        }}>
          {/* Diagram */}
          <div style={{ position: 'relative' }}>
            <IOSFrame scale={0.55}>
              <BooksScreenB activeCard={0}/>
            </IOSFrame>
            {/* Annotations overlay — coordinates approximate at scale 0.55 */}
            <SpacingAnnotation top={60}  left={235} text="59pt safe area"/>
            <SpacingAnnotation top={104} left={235} text="AppHeader · 14pt below"/>
            <SpacingAnnotation top={152} left={235} text="Inline header row · 12pt"/>
            <SpacingAnnotation top={184} left={235} text="Hero label · 6pt below"/>
            <SpacingAnnotation top={208} left={235} text="Hero number (60px Mohave 300)"/>
            <SpacingAnnotation top={272} left={235} text="Margin meter · 22pt below"/>
            <SpacingAnnotation top={344} left={235} text="L2 drill tiles · 8pt apart"/>
            <SpacingAnnotation top={400} left={235} text="Dot pagination · 20pt below"/>
            <SpacingAnnotation top={418} left={235} text="Segmented control · 22pt"/>
            <SpacingAnnotation top={464} left={235} text="List · 12pt below"/>
          </div>

          {/* Numeric callouts */}
          <div>
            <SubSection title="Vertical rhythm">
              <SpacingRow token="Status bar"                value="59pt"  use="Safe area + dynamic island"/>
              <SpacingRow token="AppHeader content"         value="52pt"  use="// BOOKS · Cake Mono 28px"/>
              <SpacingRow token="AppHeader → inline header" value="14pt"  use=""/>
              <SpacingRow token="Inline header → hero label" value="12pt" use=""/>
              <SpacingRow token="Hero label → hero number"  value="6pt"   use=""/>
              <SpacingRow token="Hero number → meter"       value="22pt"  use=""/>
              <SpacingRow token="Meter → L2 tile row"       value="24pt"  use=""/>
              <SpacingRow token="L2 tile gap"               value="8pt"   use="Between drill tiles"/>
              <SpacingRow token="Tile row → pagination"     value="20pt"  use=""/>
              <SpacingRow token="Pagination → segmented"    value="22pt"  use=""/>
              <SpacingRow token="Tab bar"                   value="83pt"  use="49pt content + 34pt home indicator"/>
            </SubSection>
            <SubSection title="Horizontal rhythm">
              <SpacingRow token="Canvas padding"          value="20pt"  use="Both sides, all content"/>
              <SpacingRow token="L1 card inset"           value="16pt"  use="Internal padding"/>
              <SpacingRow token="L2 tile inset"           value="14pt"  use="Internal padding"/>
              <SpacingRow token="Tag inset"               value="6–8pt" use="Within tag/chip"/>
              <SpacingRow token="Period pill inset"       value="14×8pt" use="Horizontal × vertical"/>
            </SubSection>
          </div>
        </div>
      </div>

      {/* Footer / direction summary */}
      <div style={{ marginTop: 48, paddingTop: 24, borderTop: `1px solid ${T.line}` }}>
        <Section title="// DIRECTIONS"/>
        <div style={{
          display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 24, marginTop: 16,
        }}>
          <DirectionSummary
            letter="A"
            name="TERMINAL"
            essence="Dense, mono-forward. The Bloomberg lineage."
            traits={['Hero 40px Mohave 300', 'Hairline charts, gridlines', 'Inline drill strip · no fill', 'Period pill: 5px sharp', 'Pagination: 01/05 + ticks', 'Segmented: white underline']}
          />
          <DirectionSummary
            letter="B"
            name="MISSION DECK"
            essence="Hero-led. 60px numbers, sparklines, breathing whitespace."
            traits={['Hero 60px Mohave 300', 'Soft ramps + sparklines', 'L2 nested drill tiles', 'Period pill: 12px soft', 'Pagination: capsule-grow', 'Segmented: filled pill']}
            recommended
          />
          <DirectionSummary
            letter="C"
            name="LEDGER"
            essence="Editorial, hairline-structural. SpaceX readout."
            traits={['Hero 52px Mohave 300', 'Numeric tables + ticks', 'Hairline stat rows · drill', 'Period pill: borderless', 'Pagination: ascending ticks', 'Segmented: top-line indicator']}
          />
        </div>
      </div>

      {/* Anti-pattern reminders */}
      <div style={{ marginTop: 36, padding: '20px 24px', border: `1px solid ${T.brickLine}`, borderRadius: T.rL2, background: T.roseSoft }}>
        <span style={{
          fontFamily: T.mono, fontSize: 10, color: T.rose, fontWeight: 600,
          letterSpacing: '0.20em', textTransform: 'uppercase',
        }}>// ANTI-PATTERNS · BANNED</span>
        <div style={{
          marginTop: 12, display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 14,
          fontFamily: T.mohave, fontSize: 12, color: T.text2, lineHeight: 1.5,
        }}>
          <span>No drop shadows on dark · No accent on toggles, links, nav, segmented</span>
          <span>No emoji. No exclamation points. No "Welcome back!"</span>
          <span>No spring physics · No bouncing · No coach marks</span>
          <span>No 999px pills (avatars excepted) · No filled icons on active tab</span>
          <span>No raw unformatted numbers · No NaN · No "Are you sure?"</span>
          <span>No illustrations · No mascots · No hero photography</span>
        </div>
      </div>
    </div>
  );
}

// ─── helpers ────────────────────────────────────────────
function Section({ title }) {
  return (
    <h2 style={{
      margin: '0 0 16px', fontFamily: T.cake, fontWeight: 300, fontSize: 22,
      color: T.text, textTransform: 'uppercase', letterSpacing: '0.04em',
    }}>{title}</h2>
  );
}

function SubSection({ title, children }) {
  return (
    <div style={{ marginBottom: 28 }}>
      <h3 style={{
        margin: '0 0 8px',
        fontFamily: T.mono, fontSize: 10, fontWeight: 500, color: T.text3,
        letterSpacing: '0.18em', textTransform: 'uppercase',
      }}>{title}</h3>
      {children}
    </div>
  );
}

function TypeSample({ children, family, size, weight, caps }) {
  return (
    <div style={{ padding: '12px 0', borderBottom: `1px solid ${T.lineSoft}` }}>
      <div style={{
        fontFamily: family, fontSize: size, fontWeight: weight,
        color: T.text, textTransform: caps ? 'uppercase' : 'none',
        letterSpacing: caps ? '0.02em' : 'normal', lineHeight: 1.1,
      }}>{children}</div>
    </div>
  );
}

function TypeRow({ role, family, size, use }) {
  return (
    <div style={{
      display: 'grid', gridTemplateColumns: '120px 130px 90px 1fr', gap: 12,
      padding: '6px 0', borderBottom: `1px solid ${T.lineSoft}`,
      alignItems: 'baseline',
    }}>
      <span style={{ fontFamily: T.mono, fontSize: 10, color: T.text2, letterSpacing: '0.10em' }}>{role}</span>
      <span style={{ fontFamily: T.mono, fontSize: 10, color: T.text3 }}>{family}</span>
      <span style={{ fontFamily: T.mono, fontSize: 10, color: T.text, ...tnum }}>{size}</span>
      <span style={{ fontFamily: T.mohave, fontSize: 11, color: T.text2 }}>{use}</span>
    </div>
  );
}

function SpacingRow({ token, value, use }) {
  return (
    <div style={{
      display: 'grid', gridTemplateColumns: '1fr 70px 1.4fr', gap: 12,
      padding: '6px 0', borderBottom: `1px solid ${T.lineSoft}`,
      alignItems: 'baseline',
    }}>
      <span style={{ fontFamily: T.mono, fontSize: 11, color: T.text, letterSpacing: '0.04em' }}>{token}</span>
      <span style={{ fontFamily: T.mono, fontSize: 11, color: T.text, ...tnum, fontWeight: 500, textAlign: 'right' }}>{value}</span>
      <span style={{ fontFamily: T.mohave, fontSize: 11, color: T.text3 }}>{use}</span>
    </div>
  );
}

function MotionRow({ event, duration, detail }) {
  return (
    <div style={{
      display: 'grid', gridTemplateColumns: '1.2fr 100px 1fr', gap: 10,
      padding: '6px 0', borderBottom: `1px solid ${T.lineSoft}`,
      alignItems: 'baseline',
    }}>
      <span style={{ fontFamily: T.mohave, fontSize: 12, color: T.text2 }}>{event}</span>
      <span style={{ fontFamily: T.mono, fontSize: 11, color: T.text, ...tnum, fontWeight: 500, letterSpacing: '0.04em' }}>{duration}</span>
      <span style={{ fontFamily: T.mono, fontSize: 10, color: T.text3, letterSpacing: '0.02em' }}>{detail}</span>
    </div>
  );
}

function RadiusSample({ label, value }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 14,
      padding: '8px 0', borderBottom: `1px solid ${T.lineSoft}`,
    }}>
      <div style={{
        width: 28, height: 28, border: `1.5px solid ${T.text2}`, borderRadius: value,
      }}/>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 2, flex: 1 }}>
        <span style={{ fontFamily: T.mono, fontSize: 11, color: T.text, letterSpacing: '0.04em' }}>{label}</span>
      </div>
      <span style={{ fontFamily: T.mono, fontSize: 11, color: T.text, ...tnum, fontWeight: 500 }}>{value}px</span>
    </div>
  );
}

function SpacingAnnotation({ top, left, text }) {
  return (
    <div style={{
      position: 'absolute', top, left,
      fontFamily: T.mono, fontSize: 9, color: T.text3,
      letterSpacing: '0.12em', textTransform: 'uppercase',
      whiteSpace: 'nowrap',
    }}>
      <span style={{ color: T.textMute, marginRight: 6 }}>← ··</span>{text}
    </div>
  );
}

function DirectionSummary({ letter, name, essence, traits, recommended }) {
  return (
    <div style={{
      padding: 20, border: `1px solid ${recommended ? T.accent : T.line}`,
      borderRadius: T.rL2,
      background: recommended ? T.accentMuted : 'transparent',
      display: 'flex', flexDirection: 'column', gap: 12,
    }}>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 10 }}>
        <span style={{
          fontFamily: T.cake, fontWeight: 300, fontSize: 40,
          color: recommended ? T.accent : T.text, lineHeight: 1,
        }}>{letter}</span>
        <span style={{
          fontFamily: T.cake, fontWeight: 300, fontSize: 16,
          color: T.text, textTransform: 'uppercase', letterSpacing: '0.04em',
        }}>{name}</span>
        {recommended && <span style={{
          marginLeft: 'auto',
          fontFamily: T.mono, fontSize: 9, color: T.accent, fontWeight: 600,
          letterSpacing: '0.18em', textTransform: 'uppercase',
          padding: '2px 6px', borderRadius: T.rChip,
          border: `1px solid ${T.accent}`, background: T.accentMuted,
        }}>RECOMMENDED</span>}
      </div>
      <span style={{ fontFamily: T.mohave, fontSize: 12, color: T.text2, lineHeight: 1.4 }}>{essence}</span>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
        {traits.map((t, i) => (
          <span key={i} style={{
            fontFamily: T.mono, fontSize: 10.5, color: T.text3,
            letterSpacing: '0.04em',
          }}>
            <span style={{ color: T.textMute }}>·· </span>{t}
          </span>
        ))}
      </div>
    </div>
  );
}

Object.assign(window, { HandoffSheet });
