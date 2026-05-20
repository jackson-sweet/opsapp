// Seed data for Books tab mocks.
// Numbers are tuned so each card tells a distinct story:
//   P&L     → healthy mid-tier owner ($42K net on $118K rev = 36% margin)
//   Flow    → mostly positive with one bad week to show variance
//   A/R     → real chase pile, mix of buckets, 90+ skew
//   Forecast→ pipeline weighted toward late-stage (signals momentum)
//   Jobs    → 3 winners, 2 losers, worst loser visible
// Period assumed: 6 MONTHS unless noted.

window.SEED = {
  period: { token: 'sixMonths', label: '6 MONTHS', short: '6M' },

  // Card 1 — P&L
  pl: {
    payments:    118400,
    expenses:    76220,
    netCash:     42180,
    marginPct:   36,
    outstanding: 12640, outstandingCount: 4,
    forecast:    38900, forecastCount: 7,
  },

  // Card 2 — Cash flow (paired weekly bars, 8 weeks of trailing data)
  cashflow: {
    netCash: 42180,
    salesTotal: 142800,
    avgPerWeek: 14800,
    daysToPay: 18.2,
    weeks: [
      // [label, in, out]
      ['W14', 14200,  -8200],
      ['W15', 18800,  -9100],
      ['W16',  9400, -11400],   // bad week — expenses > income
      ['W17', 22600,  -7800],
      ['W18', 16200,  -8400],
      ['W19', 20400,  -9600],
      ['W20', 24800, -11200],
      ['W21', 16400,  -10520],
    ],
  },

  // Card 3 — A/R (always all-open)
  ar: {
    total:    17800,
    openCount:    5,
    overdueCount: 4,
    buckets: [
      { range: '0–30D',  amount:  4800, color: 'olive' },
      { range: '31–60D', amount:  3200, color: 'fin-r' },
      { range: '61–90D', amount:  6400, color: 'tan' },
      { range: '90D+',   amount:  3400, color: 'brick' },
    ],
    topChase: { client: 'Verity Projects', invoice: 'INV-00284', amount: 6400, daysOverdue: 71 },
    chaseList: [
      { client: 'Verity Projects',  invoice: 'INV-00284', amount: 6400, days: 71 },
      { client: 'Halcyon Builders', invoice: 'INV-00301', amount: 3400, days: 94 },
      { client: 'Mara Lin',         invoice: 'INV-00298', amount: 3200, days: 42 },
      { client: 'Joel Lioudakis',   invoice: 'INV-00276', amount: 2200, days: 12 },
      { client: 'Dave Bernard',     invoice: 'INV-00292', amount:  600, days: 24 },
    ],
  },

  // Card 4 — Forecast (always active opps; weighted by stage probability)
  forecast: {
    weighted:    84500,
    activeCount: 12,
    closeRate:   64,
    staleCount:  3,
    stages: [
      { name: 'QUALIFYING',  amount: 18200, pct: 0.62 },
      { name: 'QUOTING',     amount: 12400, pct: 0.40 },
      { name: 'QUOTED',      amount: 26800, pct: 0.95 },
      { name: 'FOLLOW-UP',   amount:  9500, pct: 0.30 },
      { name: 'NEGOTIATION', amount: 17600, pct: 0.78 },
    ],
  },

  // Card 5 — Jobs (top 5 by net; always include worst loser)
  jobs: {
    profitableCount: 9,
    avgMarginPct:    32,
    losersCount:     2,
    list: [
      { name: 'OAK GROVE NEW',  net:  19800, margin: 41 },
      { name: 'PERRY ST RENO',  net:  19500, margin: 38 },
      { name: 'MILL POND ADDN', net:   8200, margin: 22 },
      { name: 'STATE ST KITCHN', net: -2600, margin: -8 },
      { name: 'RIVERVIEW DECK', net:  -4400, margin: -14 },
    ],
  },

  // Period menu options
  periods: [
    { token: 'month',       label: '30 DAYS',      short: '30D' },
    { token: 'quarter',     label: '90 DAYS',      short: '90D' },
    { token: 'sixMonths',   label: '6 MONTHS',     short: '6M'  },
    { token: 'year',        label: '1 YEAR',       short: '1Y'  },
    { token: 'thisMonth',   label: 'THIS MONTH',   short: 'MTD' },
    { token: 'lastMonth',   label: 'LAST MONTH',   short: 'LAST'},
    { token: 'thisQuarter', label: 'THIS QUARTER', short: 'QTD' },
    { token: 'ytd',         label: 'YEAR TO DATE', short: 'YTD' },
  ],
};

// Currency formatter — $42,180 (no cents)
window.fmt$ = (n, opts = {}) => {
  const abs = Math.abs(n);
  const sign = n < 0 ? '−' : (opts.sign ? '+' : '');
  if (opts.compact && abs >= 1000) {
    if (abs >= 1_000_000) return `${sign}$${(abs/1_000_000).toFixed(1)}M`;
    return `${sign}$${(abs/1000).toFixed(abs >= 10000 ? 1 : 1)}K`;
  }
  return `${sign}$${abs.toLocaleString('en-US', { maximumFractionDigits: 0 })}`;
};

// Number formatter — 12, 17%
window.fmtN = (n) => Number(n).toLocaleString('en-US', { maximumFractionDigits: 0 });
