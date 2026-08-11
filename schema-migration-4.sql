-- ============================================================
-- Red Rock Robotics — Migration 4
-- ------------------------------------------------------------
-- Adds a "category" column to assignments, quizzes, and
-- tutorials, so each can be grouped/filtered with a dropdown
-- instead of scrolling through one long list.
-- Run this once, on top of migrations 1-3.
-- ============================================================

alter table assignments add column category text not null default 'General';
alter table quizzes add column category text not null default 'General';
alter table tutorials add column category text not null default 'General';
