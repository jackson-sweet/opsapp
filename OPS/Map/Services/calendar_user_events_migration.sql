-- Migration: calendar_user_events
-- Run in Supabase SQL editor for project: ijeekuhbatykdomumfjx.supabase.co
-- Created: 2026-03-02

create table if not exists calendar_user_events (
  id            uuid primary key default gen_random_uuid(),
  user_id       text not null,
  company_id    text not null,
  type          text not null check (type in ('personal', 'time_off')),
  title         text not null default '',
  start_date    timestamptz not null,
  end_date      timestamptz not null,
  all_day       boolean not null default true,
  notes         text,
  status        text not null default 'none' check (status in ('none', 'pending', 'approved', 'denied')),
  reviewed_by   text,
  reviewed_at   timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz,
  deleted_at    timestamptz
);

-- Indexes for common query patterns
create index if not exists idx_calendar_user_events_user_id
  on calendar_user_events(user_id);

create index if not exists idx_calendar_user_events_company_id
  on calendar_user_events(company_id);

create index if not exists idx_calendar_user_events_date_range
  on calendar_user_events(start_date, end_date);

-- Row Level Security
alter table calendar_user_events enable row level security;

-- Policy: users manage their own events
create policy "Users manage own events"
  on calendar_user_events
  for all
  using (user_id = auth.uid()::text);

-- Policy: company members (admin/office) can read all events for time-off review
create policy "Company members read all events"
  on calendar_user_events
  for select
  using (
    company_id in (
      select company_id from users where id = auth.uid()::text
    )
  );
