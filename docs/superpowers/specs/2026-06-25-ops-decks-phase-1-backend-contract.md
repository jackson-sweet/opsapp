# OPS Decks Phase 1 Backend Contract

## Provision Deck Company

Endpoint owner: ops-web server API.

Request:
- firebase_uid: string
- email: string
- display_name: string?
- source_app: "ops_decks"

Response:
- company_id: uuid
- user_id: uuid
- role: "admin"
- subscription_plan: "decks"

Database effects:
- Create one `companies` row for the deck-only company.
- Create or link one `users` row with `firebase_uid`/`auth_id` and `company_id`.
- Do not write deck entitlement into `companies.subscription_status`.
- Set a clear deck-only origin field or `subscription_plan = 'decks'` so the OPS app can route to upgrade instead of treating this as a lapsed OPS subscription.

## Deck Subscription Mirror

Table: deck_subscriptions

Columns:
- id uuid primary key
- company_id uuid not null references companies(id)
- revenuecat_customer_id text not null
- entitlement text not null
- product_id text not null
- status text not null
- store text not null
- expires_at timestamptz
- last_event_at timestamptz not null
- created_at timestamptz not null default now()
- updated_at timestamptz not null default now()

RLS:
- company-scoped read for the owning company.
- server-only writes through the RevenueCat webhook.

## Account Deletion

Request:
- firebase_uid: string
- company_id: uuid

Effects:
- Soft-delete deck designs.
- Delete or anonymize the deck-only company/user according to OPS account deletion policy.
- Return deletion receipt id and timestamp.
