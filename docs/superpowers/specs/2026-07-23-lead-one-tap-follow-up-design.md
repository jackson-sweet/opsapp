# Lead One-Tap Follow-Up Design

**Date:** 2026-07-23
**Surfaces:** OPS iOS Leads, OPS Web email transport, Supabase lead lifecycle

## Outcome

An operator can send the standard quote follow-up from a due or overdue lead with one tap. OPS sends a real reply from the operator's connected mailbox in the existing provider thread. Only provider-confirmed delivery advances the lead to `THEIR MOVE` and schedules the next check-in.

## Operator experience

- A due or overdue lead with an email address shows `SEND FOLLOW-UP` in the existing chase strip.
- One tap starts the send. The control disables while the request is in flight so repeated taps cannot create parallel work.
- A reconciled send returns the authoritative opportunity, removes the lead from `DUE TODAY` or `OVERDUE`, and shows `FOLLOW-UP SENT · BACK <DATE>`.
- A provider-accepted send whose local reconciliation is still finishing shows `FOLLOW-UP SENT · SYNCING`. OPS never sends again under a new request key while that result is unresolved.
- A definite rejection leaves the lead due and shows `FOLLOW-UP FAILED · TRY AGAIN`.
- A missing or unsafe threaded-send binding leaves the lead unchanged, shows `FOLLOW-UP UNAVAILABLE · USE EMAIL`, and restores the ordinary `HANDLED` action for that app session.
- No confirmation sheet is added. The explicit `SEND FOLLOW-UP` label is the confirmation, and the provider send cannot be undone.

The existing quick `EMAIL` action remains the custom-compose path. The existing `HANDLED` action remains available whenever the real threaded follow-up is unavailable.

## Standard message

Subject:

> Following up

Body:

> Hi {{first_name}}, just checking in to see if you had any questions about the quote. No pressure — I wanted to make sure you had everything you needed.

The connected mailbox signature is appended server-side. Company-specific lifecycle templates remain authoritative. Existing companies still using the old stock template are upgraded to this wording; customized templates are preserved.

## Server-authoritative send

The iOS request is intentionally small:

```http
POST /api/leads/{opportunityId}/follow-up
Authorization: Bearer <Firebase ID token>
Content-Type: application/json

{ "idempotencyKey": "<stable UUID for this tap>" }
```

iOS never supplies a company, user, recipient, mailbox, provider thread, provider message, subject, body, or signature. The server resolves all of them from the authenticated actor and current database/provider state.

Before provider I/O the server must:

1. Resolve the active, open opportunity in the actor's company.
2. Enforce current `pipeline.edit` and `inbox.send` permissions plus assignment and mailbox ownership.
3. Resolve one canonical linked email thread and active mailbox.
4. Fetch the provider thread and verify the newest message is outbound from that mailbox. A newer inbound means the operator owes a reply, so the stock follow-up must not send.
5. Verify the lead recipient is a participant in that provider thread.
6. Resolve the current lifecycle template and connected-mailbox signature.
7. Create or reuse the open `template_follow_up` lifecycle draft bound to the exact provider message.
8. Prepare the existing durable `email_send_intents` record using the supplied idempotency key.

The existing email delivery pipeline owns the provider call, provider acceptance receipt, reconciliation, activity, correspondence event, thread update, label writeback, and learning queue.

## Delivery and lead-state boundary

Provider acceptance is irreversible, while database reconciliation is retryable. The send intent is therefore the only authority for retries.

For a `template_follow_up` intent, reconciliation also calls one idempotent database transition keyed by the send intent. That transition:

- marks the lifecycle draft sent;
- increments `unanswered_follow_up_count` exactly once;
- stamps `second_follow_up_sent_at` when the count reaches two;
- clears the stale operator-follow-up-miss state;
- sets `handled_at`;
- sets `next_follow_up_at` to three days after send, preserving an existing sooner future date;
- resolves the open follow-up-miss notification;
- creates one standard `lead_follow_up_sent` notification;
- stores the applied timestamp and comeback date on the send intent.

System-handoff drafts are explicitly excluded from this transition because they answer inbound mail rather than chase an unanswered quote.

## Idempotency

iOS stores one UUID for the active tap until the server returns a definitive outcome. Network retries and app-response loss reuse that UUID. The backend's unique `(company_id, idempotency_key)` send intent and immutable request fingerprint ensure the provider can be called at most once.

- Reconciled: clear the stored key.
- Provider rejected before delivery: clear it so a later deliberate tap can create a fresh attempt.
- Mailbox busy, network failure, provider accepted/reconciliation pending, or delivery unknown: retain it.

## UI placement

The chase strip remains one 44-point control.

- `OVERDUE` / `DUE TODAY` + editable + email + not locally unavailable: `SEND FOLLOW-UP`
- all other actionable ownership states: existing `HANDLED` or `ADJUST`

The control uses existing `OPSStyle` type, semantic tones, spacing, border, and haptic tokens. No new animation is introduced.

## Scope boundaries

- No autonomous sends.
- No offline send queue; delayed surprise email is unsafe.
- No client-authored template.
- No blind send when thread, participant, mailbox, or latest-message direction is ambiguous.
- No change to the ordinary custom email composer.
- No push, deployment, production migration, or App Store release in this implementation pass.
