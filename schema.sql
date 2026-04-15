-- ============================================================
-- TIMELINE — Supabase schema
-- Run this in Supabase SQL Editor
-- ============================================================

-- ============================================================
-- 1. TRACKS — global pool of all songs ever added
-- ============================================================
create table if not exists public.tracks (
  id uuid primary key default gen_random_uuid(),
  spotify_id text unique not null,        -- e.g. "3ZFTkvIE7kyPt6Nu3PEa7V"
  artist text not null,
  title text not null,
  year integer not null check (year between 1900 and 2100),
  album text,
  cover_url text,
  preview_url text,                        -- 30s preview from Spotify (optional fallback)
  duration_ms integer,
  added_by uuid references auth.users(id),
  created_at timestamptz default now()
);

create index if not exists tracks_year_idx on public.tracks(year);
create index if not exists tracks_artist_idx on public.tracks(artist);

-- ============================================================
-- 2. PLAYLISTS — curated collections (Dansk, Disney, etc.)
-- ============================================================
create table if not exists public.playlists (
  id uuid primary key default gen_random_uuid(),
  slug text unique not null,               -- "dansk", "disney", "international"
  name text not null,                      -- "Dansk Musik"
  description text,
  category text not null,                  -- maps to card theme: dansk/american/international/disney
  owner_id uuid references auth.users(id),
  is_public boolean default false,
  created_at timestamptz default now()
);

-- ============================================================
-- 3. PLAYLIST_TRACKS — many-to-many
-- ============================================================
create table if not exists public.playlist_tracks (
  playlist_id uuid references public.playlists(id) on delete cascade,
  track_id uuid references public.tracks(id) on delete cascade,
  added_at timestamptz default now(),
  primary key (playlist_id, track_id)
);

-- ============================================================
-- 4. CARDS — physical printed cards (one per QR code)
-- The card_id is what's encoded in the QR.
-- ============================================================
create table if not exists public.cards (
  id text primary key,                     -- short ID, e.g. "a3f9k2" (encoded in QR)
  track_id uuid references public.tracks(id) on delete cascade not null,
  playlist_id uuid references public.playlists(id) on delete set null,
  printed_at timestamptz,
  created_at timestamptz default now()
);

create index if not exists cards_track_idx on public.cards(track_id);

-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================
alter table public.tracks enable row level security;
alter table public.playlists enable row level security;
alter table public.playlist_tracks enable row level security;
alter table public.cards enable row level security;

-- Tracks: anyone authenticated can read; anyone authenticated can insert
drop policy if exists "tracks_read" on public.tracks;
create policy "tracks_read" on public.tracks
  for select using (auth.role() = 'authenticated');

drop policy if exists "tracks_insert" on public.tracks;
create policy "tracks_insert" on public.tracks
  for insert with check (auth.role() = 'authenticated');

-- Playlists: read public + own; modify only own
drop policy if exists "playlists_read" on public.playlists;
create policy "playlists_read" on public.playlists
  for select using (is_public = true or owner_id = auth.uid());

drop policy if exists "playlists_modify_own" on public.playlists;
create policy "playlists_modify_own" on public.playlists
  for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());

-- Playlist tracks: tied to playlist ownership
drop policy if exists "playlist_tracks_read" on public.playlist_tracks;
create policy "playlist_tracks_read" on public.playlist_tracks
  for select using (
    exists (
      select 1 from public.playlists p
      where p.id = playlist_id and (p.is_public = true or p.owner_id = auth.uid())
    )
  );

drop policy if exists "playlist_tracks_modify" on public.playlist_tracks;
create policy "playlist_tracks_modify" on public.playlist_tracks
  for all using (
    exists (
      select 1 from public.playlists p
      where p.id = playlist_id and p.owner_id = auth.uid()
    )
  );

-- Cards: same as playlist
drop policy if exists "cards_read" on public.cards;
create policy "cards_read" on public.cards
  for select using (
    exists (
      select 1 from public.playlists p
      where p.id = playlist_id and (p.is_public = true or p.owner_id = auth.uid())
    )
    or playlist_id is null
  );

drop policy if exists "cards_modify" on public.cards;
create policy "cards_modify" on public.cards
  for all using (
    exists (
      select 1 from public.playlists p
      where p.id = playlist_id and p.owner_id = auth.uid()
    )
  );

-- ============================================================
-- SEED — four default empty playlists
-- (run once after creating your first user, then update owner_id manually
--  or remove the owner_id line to seed without ownership)
-- ============================================================
-- insert into public.playlists (slug, name, category, is_public, description) values
--   ('dansk', 'Dansk Musik', 'dansk', true, 'Danske hits gennem tiderne'),
--   ('amerikansk', 'Amerikansk Musik', 'american', true, 'US hits'),
--   ('international', 'Internationalt', 'international', true, 'Hits fra hele verden'),
--   ('disney', 'Disney', 'disney', true, 'Disney-klassikere');
