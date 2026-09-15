# Follow-up after parent's first serial regression run

The parent executed the harness and retained `proof.7Bk8GG`. Independent log read confirms nine original identity observations, nine repaired identity checks and both sequence phases passed. The run then stopped at the P7 future-date assertion. No runtime was executed by this subagent.

The failure is a timezone mismatch, not an expired fixed literal: original line 96 uses `(current_date+1)::text`. PostgreSQL initialized on this Mac uses the local timezone, while the synthetic company is UTC. During the evening in Vancouver, session tomorrow equals the UTC company's current business day, which correctly passes production validation.

`p7-business-date-test.patch` changes only that assertion to compute tomorrow using the company timezone and `clock_timestamp`, matching the validator. `git apply --check` passed before the parent applied it. The standalone corrected SQL is `expense-correction-runtime.business-date.sql`. No migration or product runtime changed.

The harness now explicitly starts its private server with `timezone=UTC` so unrelated session-relative fixture defaults are deterministic. The observed `/dev/null is not a plain file` warning is removed by providing empty regular pgpass/service files inside its private mode-700 scratch directory with mode-600 defaults. Credentials remain absent and all connection arguments still identify the newly created local socket cluster. Bash syntax passed; this revised harness has not been executed by this subagent.

All 23 distinct source inputs referenced by the harness were inspected for future-relative expectations and fixed date literals; details are in `date-expectation-audit.json`. No other stale wall-clock future expectation was found. The payroll September 2 future-payment cases are intentionally future relative to their explicit September 1 observed-at snapshot, so their fixed dates and expected output remain unchanged. Capability-version dates, July/September fixture provenance, 1970 null sentinels, and the 2020 stale-revision test are also preserved.
