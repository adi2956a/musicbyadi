-- Cloudflare D1 Database Schema for Family/Friends Music Streamer

CREATE TABLE IF NOT EXISTS profiles (
  id          TEXT PRIMARY KEY,       -- uuid
  name        TEXT NOT NULL,
  role        TEXT NOT NULL DEFAULT 'listener', -- listener | contributor | owner
  created_at  INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS invites (
  code        TEXT PRIMARY KEY,       -- 6-char alphanumeric
  is_used     INTEGER NOT NULL DEFAULT 0,
  used_by     TEXT REFERENCES profiles(id),
  created_by  TEXT REFERENCES profiles(id),
  created_at  INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS songs (
  id          TEXT PRIMARY KEY,
  title       TEXT NOT NULL,
  artist      TEXT,
  r2_key      TEXT NOT NULL,          -- path in R2 bucket
  thumb_key   TEXT,                   -- optional cover art
  size_bytes  INTEGER NOT NULL,
  duration_s  INTEGER,
  uploaded_by TEXT REFERENCES profiles(id),
  created_at  INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS playlists (
  id          TEXT PRIMARY KEY,
  name        TEXT NOT NULL,
  created_by  TEXT REFERENCES profiles(id),
  created_at  INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS playlist_songs (
  playlist_id TEXT REFERENCES playlists(id),
  song_id     TEXT REFERENCES songs(id),
  position    INTEGER NOT NULL,
  PRIMARY KEY (playlist_id, song_id)
);

CREATE TABLE IF NOT EXISTS favorites (
  profile_id  TEXT REFERENCES profiles(id),
  song_id     TEXT REFERENCES songs(id),
  created_at  INTEGER NOT NULL,
  PRIMARY KEY (profile_id, song_id)
);

-- Seed Initial Data
INSERT OR IGNORE INTO profiles (id, name, role, created_at) 
VALUES ('owner-uuid-1', 'Adi (Owner)', 'owner', 1727500000);

INSERT OR IGNORE INTO invites (code, is_used, used_by, created_by, created_at)
VALUES ('FAMILY', 0, NULL, 'owner-uuid-1', 1727500000);

INSERT OR IGNORE INTO invites (code, is_used, used_by, created_by, created_at)
VALUES ('JAM123', 0, NULL, 'owner-uuid-1', 1727500000);

INSERT OR IGNORE INTO songs (id, title, artist, r2_key, thumb_key, size_bytes, duration_s, uploaded_by, created_at)
VALUES 
('song-1', 'Midnight Acoustic Session', 'Adi & Friends', 'tracks/midnight_acoustic.mp3', NULL, 4823400, 204, 'owner-uuid-1', 1727500100),
('song-2', 'Chaptal Street Lo-Fi', 'Urban Grooves', 'tracks/chaptal_lofi.mp3', NULL, 3950100, 168, 'owner-uuid-1', 1727500200),
('song-3', 'Sunlit Horizon', 'Acoustica', 'tracks/sunlit_horizon.mp3', NULL, 5120000, 225, 'owner-uuid-1', 1727500300),
('song-4', 'Late Night Synthwave', 'Retro Beats', 'tracks/synthwave_night.mp3', NULL, 6200000, 270, 'owner-uuid-1', 1727500400),
('song-5', 'Rainy Sunday Piano', 'Serenade', 'tracks/rainy_piano.mp3', NULL, 3100000, 135, 'owner-uuid-1', 1727500500);

INSERT OR IGNORE INTO playlists (id, name, created_by, created_at)
VALUES 
('pl-1', 'Chilled Evenings', 'owner-uuid-1', 1727500600),
('pl-2', 'Roadtrip Jamz', 'owner-uuid-1', 1727500700);

INSERT OR IGNORE INTO playlist_songs (playlist_id, song_id, position)
VALUES 
('pl-1', 'song-1', 1),
('pl-1', 'song-2', 2),
('pl-1', 'song-5', 3),
('pl-2', 'song-3', 1),
('pl-2', 'song-4', 2);
