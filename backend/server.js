const express = require('express');
const cors = require('cors');
const jwt = require('jsonwebtoken');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const app = express();
const PORT = process.env.PORT || 4000;
const JWT_SECRET = process.env.JWT_SECRET || 'musicbyadi_family_secret_jwt_key_2026';

app.use(cors());
app.use(express.json());

// In-Memory Database mirrored from backend/schema.sql
let profiles = [
  { id: 'owner-uuid-1', name: 'Adi (Owner)', role: 'owner', created_at: 1727500000 },
  { id: 'contrib-uuid-2', name: 'Maya (Contributor)', role: 'contributor', created_at: 1727500050 }
];

let invites = [
  { code: 'FAMILY', is_used: 0, used_by: null, created_by: 'owner-uuid-1', created_at: 1727500000 },
  { code: 'JAM123', is_used: 0, used_by: null, created_by: 'owner-uuid-1', created_at: 1727500000 },
  { code: 'VIP456', is_used: 0, used_by: null, created_by: 'owner-uuid-1', created_at: 1727500000 }
];

let songs = [
  {
    id: 'song-1',
    title: 'Midnight Acoustic Session',
    artist: 'Adi & Friends',
    r2_key: 'tracks/midnight_acoustic.wav',
    thumb_key: null,
    size_bytes: 4823400,
    duration_s: 204,
    uploaded_by: 'owner-uuid-1',
    created_at: 1727500100
  },
  {
    id: 'song-2',
    title: 'Chaptal Street Lo-Fi',
    artist: 'Urban Grooves',
    r2_key: 'tracks/chaptal_lofi.wav',
    thumb_key: null,
    size_bytes: 3950100,
    duration_s: 168,
    uploaded_by: 'owner-uuid-1',
    created_at: 1727500200
  },
  {
    id: 'song-3',
    title: 'Sunlit Horizon',
    artist: 'Acoustica',
    r2_key: 'tracks/sunlit_horizon.wav',
    thumb_key: null,
    size_bytes: 5120000,
    duration_s: 225,
    uploaded_by: 'owner-uuid-1',
    created_at: 1727500300
  },
  {
    id: 'song-4',
    title: 'Late Night Synthwave',
    artist: 'Retro Beats',
    r2_key: 'tracks/synthwave_night.wav',
    thumb_key: null,
    size_bytes: 6200000,
    duration_s: 270,
    uploaded_by: 'owner-uuid-1',
    created_at: 1727500400
  },
  {
    id: 'song-5',
    title: 'Rainy Sunday Piano',
    artist: 'Serenade',
    r2_key: 'tracks/rainy_piano.wav',
    thumb_key: null,
    size_bytes: 3100000,
    duration_s: 135,
    uploaded_by: 'owner-uuid-1',
    created_at: 1727500500
  }
];

let playlists = [
  { id: 'pl-1', name: 'Chilled Evenings', created_by: 'owner-uuid-1', created_at: 1727500600 },
  { id: 'pl-2', name: 'Roadtrip Jamz', created_by: 'owner-uuid-1', created_at: 1727500700 }
];

let playlist_songs = [
  { playlist_id: 'pl-1', song_id: 'song-1', position: 1 },
  { playlist_id: 'pl-1', song_id: 'song-2', position: 2 },
  { playlist_id: 'pl-1', song_id: 'song-5', position: 3 },
  { playlist_id: 'pl-2', song_id: 'song-3', position: 1 },
  { playlist_id: 'pl-2', song_id: 'song-4', position: 2 }
];

let favorites = [
  { profile_id: 'owner-uuid-1', song_id: 'song-1', created_at: 1727500800 },
  { profile_id: 'owner-uuid-1', song_id: 'song-3', created_at: 1727500801 }
];

// Ensure tracks directory exists and seed harmonic audio files
const tracksDir = path.join(__dirname, 'tracks');
if (!fs.existsSync(tracksDir)) {
  fs.mkdirSync(tracksDir, { recursive: true });
}

function generateSimpleWav(filename, baseFreq = 220, chordType = 'minor', durationSeconds = 15) {
  const filePath = path.join(tracksDir, filename);
  if (fs.existsSync(filePath)) return;

  const sampleRate = 22050;
  const numSamples = sampleRate * durationSeconds;
  const numChannels = 2;
  const bytesPerSample = 2;
  const blockAlign = numChannels * bytesPerSample;
  const byteRate = sampleRate * blockAlign;
  const dataSize = numSamples * blockAlign;

  const buffer = Buffer.alloc(44 + dataSize);

  // RIFF chunk descriptor
  buffer.write('RIFF', 0);
  buffer.writeUInt32LE(36 + dataSize, 4);
  buffer.write('WAVE', 8);

  // fmt sub-chunk
  buffer.write('fmt ', 12);
  buffer.writeUInt32LE(16, 16); // Subchunk1Size (16 for PCM)
  buffer.writeUInt16LE(1, 20);  // AudioFormat (1 = PCM)
  buffer.writeUInt16LE(numChannels, 22);
  buffer.writeUInt32LE(sampleRate, 24);
  buffer.writeUInt32LE(byteRate, 28);
  buffer.writeUInt16LE(blockAlign, 32);
  buffer.writeUInt16LE(bytesPerSample * 8, 34);

  // data sub-chunk
  buffer.write('data', 36);
  buffer.writeUInt32LE(dataSize, 40);

  // Generate musical chord progression with lush reverb/envelope
  let offset = 44;
  const freqs = chordType === 'minor'
    ? [baseFreq, baseFreq * 1.1892, baseFreq * 1.4983, baseFreq * 1.7818]
    : [baseFreq, baseFreq * 1.2599, baseFreq * 1.4983, baseFreq * 1.8877];

  for (let i = 0; i < numSamples; i++) {
    const t = i / sampleRate;
    // Arpeggiate across chord notes
    const noteIdx = Math.floor(t * 2) % freqs.length;
    const f = freqs[noteIdx];
    const envelope = Math.min(1.0, Math.sin((t % 0.5) * Math.PI * 2) * 0.8 + 0.2) * (1 - (i / numSamples) * 0.1);
    
    // Smooth harmonic tone
    const sampleVal = Math.sin(2 * Math.PI * f * t) * 0.6 +
                      Math.sin(2 * Math.PI * f * 2 * t) * 0.2 +
                      Math.sin(2 * Math.PI * (f * 0.5) * t) * 0.2;

    const int16 = Math.max(-32767, Math.min(32767, Math.floor(sampleVal * envelope * 16000)));

    // Left channel
    buffer.writeInt16LE(int16, offset);
    offset += 2;
    // Right channel (slight stereo phase)
    const rightVal = Math.sin(2 * Math.PI * f * (t + 0.001)) * envelope * 16000;
    buffer.writeInt16LE(Math.max(-32767, Math.min(32767, Math.floor(rightVal))), offset);
    offset += 2;
  }

  fs.writeFileSync(filePath, buffer);
}

// Generate the 5 sample audio tracks
generateSimpleWav('midnight_acoustic.wav', 220, 'minor', 25);
generateSimpleWav('chaptal_lofi.wav', 174.61, 'major', 22);
generateSimpleWav('sunlit_horizon.wav', 261.63, 'major', 28);
generateSimpleWav('synthwave_night.wav', 146.83, 'minor', 30);
generateSimpleWav('rainy_piano.wav', 196.00, 'minor', 20);

// Serve static track audio
app.use('/tracks', express.static(tracksDir));

// --- AUTH MIDDLEWARE ---
function authenticateToken(req, res, next) {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];
  if (!token) {
    return res.status(401).json({ error: 'Authentication required' });
  }

  jwt.verify(token, JWT_SECRET, (err, decoded) => {
    if (err) {
      return res.status(403).json({ error: 'Invalid or expired token' });
    }
    req.user = decoded; // { profileId, role }
    next();
  });
}

function requireRole(allowedRoles) {
  return (req, res, next) => {
    if (!req.user || !allowedRoles.includes(req.user.role)) {
      return res.status(403).json({ error: `Forbidden: requires role in [${allowedRoles.join(', ')}]` });
    }
    next();
  };
}

// --- ROUTES ---

// 1. POST /auth/redeem
app.post('/auth/redeem', (req, res) => {
  const { name, code } = req.body;
  if (!name || !code) {
    return res.status(400).json({ error: 'Name and invite code are required' });
  }

  const cleanCode = code.trim().toUpperCase();

  // Master Admin Code (Permanent, usable on ANY device, mobile phone, or APK)
  const isMasterAdmin = cleanCode === 'ADI999' || cleanCode === 'FAMILY';

  let invite = invites.find(inv => inv.code === cleanCode);
  if (!invite && !isMasterAdmin) {
    return res.status(404).json({ error: 'Invalid invite code' });
  }

  if (invite && invite.is_used && !isMasterAdmin) {
    return res.status(400).json({ error: 'Invite code has already been redeemed' });
  }

  // Create new profile
  const newProfileId = isMasterAdmin ? 'owner-uuid-1' : ('user-' + crypto.randomUUID().slice(0, 8));
  const assignedRole = isMasterAdmin ? 'owner' : 'listener';
  
  let newProfile = profiles.find(p => p.id === newProfileId);
  if (!newProfile) {
    newProfile = {
      id: newProfileId,
      name: name.trim(),
      role: assignedRole,
      created_at: Math.floor(Date.now() / 1000)
    };
    profiles.push(newProfile);
  } else {
    newProfile.name = name.trim();
  }

  if (invite && !isMasterAdmin) {
    invite.is_used = 1;
    invite.used_by = newProfileId;
  }

  // Sign JWT token (valid for 30 days)
  const token = jwt.sign(
    { profileId: newProfile.id, role: newProfile.role },
    JWT_SECRET,
    { expiresIn: '30d' }
  );

  return res.json({
    token,
    profile: newProfile
  });
});

// Quick debug login for existing profiles (e.g., Owner)
app.post('/auth/login-as', (req, res) => {
  const { role } = req.body; // 'owner' | 'contributor' | 'listener'
  let profile = profiles.find(p => p.role === role);
  if (!profile) {
    profile = profiles[0];
  }
  const token = jwt.sign(
    { profileId: profile.id, role: profile.role },
    JWT_SECRET,
    { expiresIn: '30d' }
  );
  res.json({ token, profile });
});

// 2. GET /me
app.get('/me', authenticateToken, (req, res) => {
  const profile = profiles.find(p => p.id === req.user.profileId);
  if (!profile) {
    return res.status(404).json({ error: 'Profile not found' });
  }
  return res.json({ profile });
});

// 3. GET /songs
app.get('/songs', authenticateToken, (req, res) => {
  const userFavorites = favorites
    .filter(f => f.profile_id === req.user.profileId)
    .map(f => f.song_id);

  const songsWithFavoriteStatus = songs.map(song => ({
    ...song,
    is_favorite: userFavorites.includes(song.id),
    stream_url: `/tracks/${path.basename(song.r2_key)}`
  }));

  return res.json({ songs: songsWithFavoriteStatus });
});

// 4. POST /songs (Contributor/Owner)
app.post('/songs', authenticateToken, requireRole(['contributor', 'owner']), (req, res) => {
  const { title, artist, duration_s, size_bytes } = req.body;
  if (!title) {
    return res.status(400).json({ error: 'Title is required' });
  }

  const id = 'song-' + crypto.randomUUID().slice(0, 8);
  const song = {
    id,
    title: title.trim(),
    artist: (artist || 'Unknown Artist').trim(),
    r2_key: 'tracks/midnight_acoustic.wav', // default or uploaded audio ref
    thumb_key: null,
    size_bytes: size_bytes || 4194304,
    duration_s: duration_s || 180,
    uploaded_by: req.user.profileId,
    created_at: Math.floor(Date.now() / 1000)
  };

  songs.unshift(song);
  res.status(201).json({ song, upload_url: `/tracks/upload-simulated/${id}` });
});

// 5. GET /songs/:id/stream-url
app.get('/songs/:id/stream-url', authenticateToken, (req, res) => {
  const song = songs.find(s => s.id === req.params.id);
  if (!song) {
    return res.status(404).json({ error: 'Song not found' });
  }

  // Returns signed stream URL (or direct local static URL for dev)
  const filename = path.basename(song.r2_key);
  const streamUrl = `/tracks/${filename}`;
  res.json({
    stream_url: streamUrl,
    expires_in: 600 // 10 minutes
  });
});

// 6. DELETE /songs/:id (Owner or Uploader)
app.delete('/songs/:id', authenticateToken, (req, res) => {
  const idx = songs.findIndex(s => s.id === req.params.id);
  if (idx === -1) {
    return res.status(404).json({ error: 'Song not found' });
  }

  const song = songs[idx];
  const isOwner = req.user.role === 'owner';
  const isUploader = song.uploaded_by === req.user.profileId;

  if (!isOwner && !isUploader) {
    return res.status(403).json({ error: 'Forbidden: only the uploader or owner can delete this song' });
  }

  const removed = songs.splice(idx, 1)[0];
  // Clean from playlist_songs and favorites
  playlist_songs = playlist_songs.filter(ps => ps.song_id !== req.params.id);
  favorites = favorites.filter(f => f.song_id !== req.params.id);

  res.json({ success: true, removedSong: removed });
});

// 7. GET /playlists
app.get('/playlists', authenticateToken, (req, res) => {
  const enrichedPlaylists = playlists.map(pl => {
    const plSongs = playlist_songs
      .filter(ps => ps.playlist_id === pl.id)
      .sort((a, b) => a.position - b.position)
      .map(ps => {
        const song = songs.find(s => s.id === ps.song_id);
        return song ? { ...song, position: ps.position } : null;
      })
      .filter(Boolean);

    const totalBytes = plSongs.reduce((sum, s) => sum + (s.size_bytes || 0), 0);

    return {
      ...pl,
      song_count: plSongs.length,
      total_bytes: totalBytes,
      songs: plSongs
    };
  });

  res.json({ playlists: enrichedPlaylists });
});

// 8. POST /playlists (Contributor/Owner)
app.post('/playlists', authenticateToken, requireRole(['contributor', 'owner']), (req, res) => {
  const { name } = req.body;
  if (!name || !name.trim()) {
    return res.status(400).json({ error: 'Playlist name is required' });
  }

  const newPlaylist = {
    id: 'pl-' + crypto.randomUUID().slice(0, 8),
    name: name.trim(),
    created_by: req.user.profileId,
    created_at: Math.floor(Date.now() / 1000)
  };

  playlists.unshift(newPlaylist);
  res.status(201).json({ playlist: { ...newPlaylist, song_count: 0, songs: [] } });
});

// 9. POST /playlists/:id/songs (Contributor/Owner)
app.post('/playlists/:id/songs', authenticateToken, requireRole(['contributor', 'owner']), (req, res) => {
  const { song_id } = req.body;
  const playlist = playlists.find(p => p.id === req.params.id);
  if (!playlist) {
    return res.status(404).json({ error: 'Playlist not found' });
  }

  const song = songs.find(s => s.id === song_id);
  if (!song) {
    return res.status(404).json({ error: 'Song not found' });
  }

  const existing = playlist_songs.find(ps => ps.playlist_id === playlist.id && ps.song_id === song_id);
  if (!existing) {
    const currentMax = playlist_songs
      .filter(ps => ps.playlist_id === playlist.id)
      .reduce((max, ps) => Math.max(max, ps.position), 0);

    playlist_songs.push({
      playlist_id: playlist.id,
      song_id,
      position: currentMax + 1
    });
  }

  res.json({ success: true, playlist_id: playlist.id, song_id });
});

// 9b. POST /playlists/:id/bulk-songs (Contributor/Owner - Multi-Add in Single Click)
app.post('/playlists/:id/bulk-songs', authenticateToken, requireRole(['contributor', 'owner']), (req, res) => {
  const { song_ids } = req.body;
  const playlist = playlists.find(p => p.id === req.params.id);
  if (!playlist) {
    return res.status(404).json({ error: 'Playlist not found' });
  }

  if (!Array.isArray(song_ids) || song_ids.length === 0) {
    return res.status(400).json({ error: 'song_ids array is required' });
  }

  let addedCount = 0;
  let currentMax = playlist_songs
    .filter(ps => ps.playlist_id === playlist.id)
    .reduce((max, ps) => Math.max(max, ps.position), 0);

  for (const sId of song_ids) {
    const songExists = songs.some(s => s.id === sId);
    if (!songExists) continue;

    const alreadyIn = playlist_songs.some(ps => ps.playlist_id === playlist.id && ps.song_id === sId);
    if (!alreadyIn) {
      currentMax++;
      playlist_songs.push({
        playlist_id: playlist.id,
        song_id: sId,
        position: currentMax
      });
      addedCount++;
    }
  }

  res.json({
    success: true,
    playlist_id: playlist.id,
    playlist_name: playlist.name,
    added_count: addedCount
  });
});

// 10. DELETE /playlists/:id/songs/:songId (Contributor/Owner)
app.delete('/playlists/:id/songs/:songId', authenticateToken, requireRole(['contributor', 'owner']), (req, res) => {
  playlist_songs = playlist_songs.filter(
    ps => !(ps.playlist_id === req.params.id && ps.song_id === req.params.songId)
  );
  res.json({ success: true });
});

// DELETE /playlists/:id (Owner or Creator)
app.delete('/playlists/:id', authenticateToken, (req, res) => {
  const playlist = playlists.find(p => p.id === req.params.id);
  if (!playlist) {
    return res.status(404).json({ error: 'Playlist not found' });
  }

  const isOwner = req.user.role === 'owner';
  const isCreator = playlist.created_by === req.user.profileId;

  if (!isOwner && !isCreator) {
    return res.status(403).json({ error: 'Forbidden: only the creator or owner can delete this playlist' });
  }

  playlists = playlists.filter(p => p.id !== req.params.id);
  playlist_songs = playlist_songs.filter(ps => ps.playlist_id !== req.params.id);
  res.json({ success: true, removedPlaylistId: req.params.id });
});

// 11. POST /favorites/:songId
app.post('/favorites/:songId', authenticateToken, (req, res) => {
  const songId = req.params.songId;
  const profileId = req.user.profileId;
  const existingIdx = favorites.findIndex(f => f.profile_id === profileId && f.song_id === songId);

  let isFavorite = false;
  if (existingIdx >= 0) {
    favorites.splice(existingIdx, 1);
    isFavorite = false;
  } else {
    favorites.push({
      profile_id: profileId,
      song_id: songId,
      created_at: Math.floor(Date.now() / 1000)
    });
    isFavorite = true;
  }

  res.json({ song_id: songId, is_favorite: isFavorite });
});

// GET /favorites
app.get('/favorites', authenticateToken, (req, res) => {
  const favSongIds = favorites
    .filter(f => f.profile_id === req.user.profileId)
    .map(f => f.song_id);

  const favSongs = songs.filter(s => favSongIds.includes(s.id));
  res.json({ favorites: favSongs });
});

// 12. GET /admin/users (Owner)
app.get('/admin/users', authenticateToken, requireRole(['owner']), (req, res) => {
  res.json({ users: profiles });
});

// 13. PATCH /admin/users/:id/role (Owner)
app.patch('/admin/users/:id/role', authenticateToken, requireRole(['owner']), (req, res) => {
  const { role } = req.body;
  if (!['listener', 'contributor', 'owner'].includes(role)) {
    return res.status(400).json({ error: 'Invalid role' });
  }

  const profile = profiles.find(p => p.id === req.params.id);
  if (!profile) {
    return res.status(404).json({ error: 'User not found' });
  }

  // Owner cannot demote self
  if (profile.id === req.user.profileId && role !== 'owner') {
    return res.status(400).json({ error: 'Owner cannot demote self' });
  }

  profile.role = role;
  res.json({ user: profile });
});

// DELETE /admin/users/:id (Owner)
app.delete('/admin/users/:id', authenticateToken, requireRole(['owner']), (req, res) => {
  if (req.params.id === req.user.profileId) {
    return res.status(400).json({ error: 'Cannot remove yourself' });
  }
  profiles = profiles.filter(p => p.id !== req.params.id);
  res.json({ success: true });
});

// 14. POST /admin/invites (Owner)
app.post('/admin/invites', authenticateToken, requireRole(['owner']), (req, res) => {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let code = '';
  for (let i = 0; i < 6; i++) {
    code += chars.charAt(Math.floor(Math.random() * chars.length));
  }

  const invite = {
    code,
    is_used: 0,
    used_by: null,
    created_by: req.user.profileId,
    created_at: Math.floor(Date.now() / 1000)
  };

  invites.push(invite);
  res.status(201).json({ invite });
});

// GET /admin/invites (Owner)
app.get('/admin/invites', authenticateToken, requireRole(['owner']), (req, res) => {
  const unused = invites.filter(i => !i.is_used);
  res.json({ invites: unused });
});

// DELETE /admin/invites/:code (Owner)
app.delete('/admin/invites/:code', authenticateToken, requireRole(['owner']), (req, res) => {
  const code = req.params.code.toUpperCase();
  invites = invites.filter(i => i.code !== code);
  res.json({ success: true });
});

// GET /admin/stats (Owner)
app.get('/admin/stats', authenticateToken, requireRole(['owner']), (req, res) => {
  const totalSongs = songs.length;
  const totalBytes = songs.reduce((sum, s) => sum + (s.size_bytes || 0), 0);
  const totalUsers = profiles.length;
  const pendingInvites = invites.filter(i => !i.is_used).length;

  res.json({
    stats: {
      total_songs: totalSongs,
      total_bytes: totalBytes,
      total_users: totalUsers,
      pending_invites: pendingInvites
    }
  });
});

// Load Multi-Account Cloudflare configuration
let cloudflareConfig = {
  storage_pools: [
    {
      id: "pool-1",
      name: "Cloudflare Account 1 (Primary - 10GB Free)",
      bucket_name: "musicbyadi-audio-1",
      max_bytes: 10737418240,
      enabled: true
    }
  ]
};

try {
  const cfgPath = path.join(__dirname, 'cloudflare.config.json');
  if (fs.existsSync(cfgPath)) {
    cloudflareConfig = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
  }
} catch (e) {
  console.warn('[Config] Using default storage pool:', e.message);
}

// 15. GET /admin/storage-pools (Owner)
app.get('/admin/storage-pools', authenticateToken, requireRole(['owner']), (req, res) => {
  res.json({ pools: cloudflareConfig.storage_pools || [] });
});

// 16. POST /admin/storage-pools (Owner)
app.post('/admin/storage-pools', authenticateToken, requireRole(['owner']), (req, res) => {
  const { name, account_id, bucket_name, access_key_id, secret_access_key, public_url_or_domain } = req.body;
  if (!name || !bucket_name) {
    return res.status(400).json({ error: 'Name and bucket_name are required' });
  }

  const newPool = {
    id: 'pool-' + crypto.randomUUID().slice(0, 6),
    name: name.trim(),
    account_id: account_id || '',
    bucket_name: bucket_name.trim(),
    access_key_id: access_key_id || '',
    secret_access_key: secret_access_key || '',
    public_url_or_domain: public_url_or_domain || '',
    max_bytes: 10737418240, // 10 GB free tier
    enabled: true
  };

  cloudflareConfig.storage_pools = cloudflareConfig.storage_pools || [];
  cloudflareConfig.storage_pools.push(newPool);

  try {
    fs.writeFileSync(path.join(__dirname, 'cloudflare.config.json'), JSON.stringify(cloudflareConfig, null, 2));
  } catch (err) {}

  res.status(201).json({ pool: newPool });
});

// 17. GET /download-apk
app.get('/download-apk', (req, res) => {
  const apkPath = path.join(__dirname, '..', 'build', 'app', 'outputs', 'flutter-apk', 'app-release.apk');
  if (fs.existsSync(apkPath)) {
    res.download(apkPath, 'MusicByAdi.apk');
  } else {
    res.status(404).json({
      error: 'APK not yet built. Run "flutter build apk --release" or use the 1-Tap Mobile Install on http://localhost:3000!'
    });
  }
});

app.listen(PORT, () => {
  console.log(`[MusicByAdi] Backend server running on http://localhost:${PORT}`);
});

