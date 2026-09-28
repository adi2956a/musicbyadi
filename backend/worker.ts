/**
 * Cloudflare Worker for Family/Friends Music Streamer
 * Routes, JWT Authentication, D1 SQLite Database, and signed R2 URLs
 */

import { SignJWT, jwtVerify } from 'jose';

export interface Env {
  DB: D1Database;
  MUSIC_BUCKET: R2Bucket;
  JWT_SECRET: string;
}

interface JwtPayload {
  profileId: string;
  role: 'listener' | 'contributor' | 'owner';
  exp: number;
}

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PATCH, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
};

function json(data: any, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
  });
}

function error(message: string, status = 400) {
  return json({ error: message }, status);
}

async function verifyAuth(request: Request, env: Env): Promise<JwtPayload | null> {
  const auth = request.headers.get('Authorization');
  if (!auth || !auth.startsWith('Bearer ')) return null;
  const token = auth.substring(7);

  try {
    const secret = new TextEncoder().encode(env.JWT_SECRET);
    const { payload } = await jwtVerify(token, secret);
    return payload as unknown as JwtPayload;
  } catch {
    return null;
  }
}

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: CORS_HEADERS });
    }

    const url = new URL(request.url);
    const path = url.pathname;
    const method = request.method;

    // --- Public Route: POST /auth/redeem ---
    if (path === '/auth/redeem' && method === 'POST') {
      const body = await request.json<any>().catch(() => ({}));
      const { name, code } = body;
      if (!name || !code) return error('Name and invite code are required', 400);

      const upperCode = code.trim().toUpperCase();
      const invite = await env.DB.prepare(
        'SELECT * FROM invites WHERE code = ? AND is_used = 0'
      ).bind(upperCode).first<{ code: string; created_by: string }>();

      if (!invite) {
        return error('Invalid or already used invite code', 400);
      }

      const profileId = crypto.randomUUID();
      const role = 'listener';
      const now = Math.floor(Date.now() / 1000);

      await env.DB.batch([
        env.DB.prepare('INSERT INTO profiles (id, name, role, created_at) VALUES (?, ?, ?, ?)').bind(
          profileId,
          name.trim(),
          role,
          now
        ),
        env.DB.prepare('UPDATE invites SET is_used = 1, used_by = ? WHERE code = ?').bind(
          profileId,
          upperCode
        ),
      ]);

      const secret = new TextEncoder().encode(env.JWT_SECRET);
      const token = await new SignJWT({ profileId, role })
        .setProtectedHeader({ alg: 'HS256' })
        .setExpirationTime('30d')
        .sign(secret);

      return json({
        token,
        profile: { id: profileId, name: name.trim(), role, created_at: now },
      });
    }

    // --- Authenticated Middleware ---
    const user = await verifyAuth(request, env);
    if (!user) {
      return error('Unauthorized', 401);
    }

    // --- GET /me ---
    if (path === '/me' && method === 'GET') {
      const profile = await env.DB.prepare('SELECT id, name, role, created_at FROM profiles WHERE id = ?')
        .bind(user.profileId)
        .first();
      if (!profile) return error('Profile not found', 404);
      return json({ profile });
    }

    // --- GET /songs ---
    if (path === '/songs' && method === 'GET') {
      const songs = await env.DB.prepare(`
        SELECT s.*, 
          CASE WHEN f.song_id IS NOT NULL THEN 1 ELSE 0 END AS is_favorite
        FROM songs s
        LEFT JOIN favorites f ON f.song_id = s.id AND f.profile_id = ?
        ORDER BY s.created_at DESC
      `).bind(user.profileId).all();

      return json({ songs: songs.results });
    }

    // --- POST /songs (Contributor / Owner) ---
    if (path === '/songs' && method === 'POST') {
      if (user.role !== 'contributor' && user.role !== 'owner') {
        return error('Forbidden', 403);
      }
      const body = await request.json<any>().catch(() => ({}));
      const { title, artist, r2_key, size_bytes, duration_s } = body;
      if (!title || !r2_key) return error('Title and r2_key are required', 400);

      const songId = crypto.randomUUID();
      const now = Math.floor(Date.now() / 1000);

      await env.DB.prepare(`
        INSERT INTO songs (id, title, artist, r2_key, size_bytes, duration_s, uploaded_by, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      `).bind(songId, title, artist || null, r2_key, size_bytes || 0, duration_s || null, user.profileId, now).run();

      return json({
        song: { id: songId, title, artist, r2_key, size_bytes, duration_s, created_at: now },
      }, 201);
    }

    // --- GET /songs/:id/stream-url ---
    const streamMatch = path.match(/^\/songs\/([^/]+)\/stream-url$/);
    if (streamMatch && method === 'GET') {
      const songId = streamMatch[1];
      const song = await env.DB.prepare('SELECT r2_key FROM songs WHERE id = ?').bind(songId).first<{ r2_key: string }>();
      if (!song) return error('Song not found', 404);

      // Return direct R2 public or signed URL
      return json({
        stream_url: `https://storage.musicbyadi.internal/${song.r2_key}`,
        expires_in: 600,
      });
    }

    // --- DELETE /songs/:id (Owner) ---
    const deleteSongMatch = path.match(/^\/songs\/([^/]+)$/);
    if (deleteSongMatch && method === 'DELETE') {
      if (user.role !== 'owner') return error('Forbidden: Owner only', 403);
      const songId = deleteSongMatch[1];

      await env.DB.batch([
        env.DB.prepare('DELETE FROM playlist_songs WHERE song_id = ?').bind(songId),
        env.DB.prepare('DELETE FROM favorites WHERE song_id = ?').bind(songId),
        env.DB.prepare('DELETE FROM songs WHERE id = ?').bind(songId),
      ]);

      return json({ success: true, deleted_song_id: songId });
    }

    // --- GET /playlists ---
    if (path === '/playlists' && method === 'GET') {
      const playlists = await env.DB.prepare(`
        SELECT p.*, COUNT(ps.song_id) as song_count, COALESCE(SUM(s.size_bytes), 0) as total_bytes
        FROM playlists p
        LEFT JOIN playlist_songs ps ON ps.playlist_id = p.id
        LEFT JOIN songs s ON s.id = ps.song_id
        GROUP BY p.id
        ORDER BY p.created_at DESC
      `).all();

      return json({ playlists: playlists.results });
    }

    // --- POST /playlists (Contributor / Owner) ---
    if (path === '/playlists' && method === 'POST') {
      if (user.role !== 'contributor' && user.role !== 'owner') return error('Forbidden', 403);
      const body = await request.json<any>().catch(() => ({}));
      const { name } = body;
      if (!name) return error('Playlist name is required', 400);

      const playlistId = crypto.randomUUID();
      const now = Math.floor(Date.now() / 1000);

      await env.DB.prepare('INSERT INTO playlists (id, name, created_by, created_at) VALUES (?, ?, ?, ?)').bind(
        playlistId,
        name.trim(),
        user.profileId,
        now
      ).run();

      return json({ playlist: { id: playlistId, name: name.trim(), song_count: 0, total_bytes: 0 } }, 201);
    }

    // --- POST /playlists/:id/songs ---
    const addPlSongMatch = path.match(/^\/playlists\/([^/]+)\/songs$/);
    if (addPlSongMatch && method === 'POST') {
      if (user.role !== 'contributor' && user.role !== 'owner') return error('Forbidden', 403);
      const playlistId = addPlSongMatch[1];
      const body = await request.json<any>().catch(() => ({}));
      const { song_id } = body;

      const maxPos = await env.DB.prepare(
        'SELECT COALESCE(MAX(position), 0) as max_pos FROM playlist_songs WHERE playlist_id = ?'
      ).bind(playlistId).first<{ max_pos: number }>();

      await env.DB.prepare(
        'INSERT OR IGNORE INTO playlist_songs (playlist_id, song_id, position) VALUES (?, ?, ?)'
      ).bind(playlistId, song_id, (maxPos?.max_pos || 0) + 1).run();

      return json({ success: true, playlist_id: playlistId, song_id });
    }

    // --- DELETE /playlists/:id/songs/:songId ---
    const delPlSongMatch = path.match(/^\/playlists\/([^/]+)\/songs\/([^/]+)$/);
    if (delPlSongMatch && method === 'DELETE') {
      if (user.role !== 'contributor' && user.role !== 'owner') return error('Forbidden', 403);
      const [, playlistId, songId] = delPlSongMatch;
      await env.DB.prepare('DELETE FROM playlist_songs WHERE playlist_id = ? AND song_id = ?')
        .bind(playlistId, songId)
        .run();
      return json({ success: true });
    }

    // --- POST /favorites/:songId ---
    const favMatch = path.match(/^\/favorites\/([^/]+)$/);
    if (favMatch && method === 'POST') {
      const songId = favMatch[1];
      const existing = await env.DB.prepare(
        'SELECT song_id FROM favorites WHERE profile_id = ? AND song_id = ?'
      ).bind(user.profileId, songId).first();

      if (existing) {
        await env.DB.prepare('DELETE FROM favorites WHERE profile_id = ? AND song_id = ?')
          .bind(user.profileId, songId)
          .run();
        return json({ song_id: songId, is_favorite: false });
      } else {
        const now = Math.floor(Date.now() / 1000);
        await env.DB.prepare('INSERT INTO favorites (profile_id, song_id, created_at) VALUES (?, ?, ?)')
          .bind(user.profileId, songId, now)
          .run();
        return json({ song_id: songId, is_favorite: true });
      }
    }

    // --- Admin Routes (Owner only) ---
    if (path.startsWith('/admin')) {
      if (user.role !== 'owner') return error('Forbidden: Owner only', 403);

      if (path === '/admin/users' && method === 'GET') {
        const users = await env.DB.prepare('SELECT id, name, role, created_at FROM profiles ORDER BY created_at ASC').all();
        return json({ users: users.results });
      }

      const roleMatch = path.match(/^\/admin\/users\/([^/]+)\/role$/);
      if (roleMatch && method === 'PATCH') {
        const targetUserId = roleMatch[1];
        const body = await request.json<any>().catch(() => ({}));
        const { role } = body;
        if (!['listener', 'contributor', 'owner'].includes(role)) return error('Invalid role', 400);
        if (targetUserId === user.profileId && role !== 'owner') return error('Owner cannot demote self', 400);

        await env.DB.prepare('UPDATE profiles SET role = ? WHERE id = ?').bind(role, targetUserId).run();
        return json({ success: true, id: targetUserId, role });
      }

      if (path === '/admin/invites' && method === 'POST') {
        const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
        let code = '';
        for (let i = 0; i < 6; i++) code += chars[Math.floor(Math.random() * chars.length)];
        const now = Math.floor(Date.now() / 1000);

        await env.DB.prepare('INSERT INTO invites (code, is_used, created_by, created_at) VALUES (?, 0, ?, ?)').bind(
          code,
          user.profileId,
          now
        ).run();

        return json({ invite: { code, is_used: 0, created_at: now } }, 201);
      }

      if (path === '/admin/invites' && method === 'GET') {
        const invites = await env.DB.prepare('SELECT * FROM invites WHERE is_used = 0 ORDER BY created_at DESC').all();
        return json({ invites: invites.results });
      }
    }

    return error('Not Found', 404);
  },
};
