-- ============================================================
-- MIGRATION — allow 'manual' (Klassisk Hitster) as a game mode
-- Run this in Supabase SQL Editor
-- ============================================================

alter table public.games
  drop constraint if exists games_mode_check;

alter table public.games
  add constraint games_mode_check
  check (mode in ('classic', 'advanced', 'expert', 'mixed', 'manual'));
