# Site-visit conflict review

Approved scope: make phone/MCP conflicts resolvable without losing either version.
Design authority: root DESIGN.md and mobile/MOBILE.md; existing Pending Work styles.

The operator is leaving a site with a saved measurement or checklist edit. Another device saved first. The immediate job is to compare the actual values, choose the intended result, and get back to work. Opening review preserves the pending edit. Reading current values requires connectivity; a failed read keeps the comparison and disables confirmation. Saving is explicit and rechecks the versions shown. A new conflict remains open with both versions. A save receipt closes only the exact reviewed work.

Layout variants considered:

1. Hierarchical: `Pending Work > field label > pending value > current value > original disclosure > decision footer`. Strong on one field, repetitive for template/default changes.
2. Grid: `field | original | pending | current` with a bottom action. Requires horizontal scanning that is unsuitable for long notes on a phone.
3. Flow: `one field > choose value > next field > review all > save`. Too much navigation for the common single field conflict.
4. Hybrid (chosen): `Pending Work > REVIEW SAVED FORM > exact affected fields, each with current and pending values + original disclosure > one confirmation footer`. Keeps the existing recovery entry point and a single scroll owner. Extra template default effects appear as explicit affected rows.

Intent: a trades operator must recover work confidently in glare, with gloves and intermittent connectivity. The view uses the existing black canvas, text/text2 for readable content, metadata for original timestamps/labels, and rose only for actionable errors. Hairline and glassSurface separate fields without decoration. Mohave body carries notes; existing metadata/mono styles carry dates and numeric values. OPSStyle spacing2/3/3_5 and the existing primary/secondary button styles provide the same rhythm and touch targets as Pending Work.

The review does not show SQL, request hashes, UUIDs, or command internals. It does not infer a conflict resolution from Retry. Original/pending/server values remain in the durable command and receipt. An explicit current-version choice retires the pending send with an audit record; it does not delete the audit copies. Existing sheet dismissal, accessibility labels, large text behavior and reduced-motion behavior are retained.
