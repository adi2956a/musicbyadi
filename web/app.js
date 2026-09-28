/**
 * Music by Adi — Client Controller & Hybrid Audio Engine
 * Adheres to Development Spec §1 - §10
 */

const API_BASE = 'http://localhost:4000';

// Global App State
const state = {
  token: localStorage.getItem('musicbyadi_token') || null,
  profile: JSON.parse(localStorage.getItem('musicbyadi_profile') || 'null'),
  currentTab: 'tab-stream',
  songs: [],
  playlists: [],
  downloadedTrackIds: new Set(JSON.parse(localStorage.getItem('musicbyadi_downloads') || '[]')),
  favorites: new Set(),
  simulatedOffline: false,
  wifiOnly: localStorage.getItem('musicbyadi_wifi_only') === 'true',
  searchQuery: '',
  offlineFilter: 'all', // all | playlists | liked

  // Playback state
  currentSong: null,
  queue: [],
  currentIndex: -1,
  isPlaying: false,
  isShuffling: false,
  loopMode: 'off', // off | all | one

  // Admin state
  adminUsers: [],
  adminInvites: [],
  adminStats: {},
  bulkMode: false,
  selectedAdminSongs: new Set()
};

// Undo stack for deleted items (§8.3)
let lastDeletedTrack = null;
let snackbarTimeout = null;

// HTML Elements
const audio = document.getElementById('audio-engine');
const onboardingView = document.getElementById('onboarding-view');
const mainView = document.getElementById('main-view');
const miniPlayer = document.getElementById('mini-player');
const expandedPlayer = document.getElementById('expanded-player');
const settingsScreen = document.getElementById('settings-screen');
const adminScreen = document.getElementById('admin-screen');
const fabCreate = document.getElementById('fab-create');

// --- INITIALIZATION ---
window.addEventListener('DOMContentLoaded', async () => {
  setupEventListeners();
  setupAudioEngine();

  if (state.token && state.profile) {
    showMainApp();
    await refreshLibrary();
  } else {
    showOnboarding();
  }
});

function showOnboarding() {
  onboardingView.classList.remove('hidden');
  mainView.classList.add('hidden');
}

function showMainApp() {
  onboardingView.classList.add('hidden');
  mainView.classList.remove('hidden');
  updateRoleGating();
  renderProfileSettings();
}

function updateRoleGating() {
  const role = state.profile?.role || 'listener';
  const isContributorOrAbove = role === 'owner' || role === 'contributor';
  const isOwner = role === 'owner';

  // FAB only for contributor/owner (§6)
  if (isContributorOrAbove) {
    fabCreate.classList.remove('hidden');
  } else {
    fabCreate.classList.add('hidden');
  }

  // Admin entry in Settings only for owner (§6)
  const adminEntry = document.getElementById('admin-entry-section');
  if (isOwner) {
    adminEntry.classList.remove('hidden');
  } else {
    adminEntry.classList.add('hidden');
  }
}

// --- API HELPER ---
async function apiCall(endpoint, method = 'GET', body = null) {
  if (state.simulatedOffline && !endpoint.includes('/me')) {
    throw new Error('Network offline (simulated)');
  }

  const headers = { 'Content-Type': 'application/json' };
  if (state.token) {
    headers['Authorization'] = `Bearer ${state.token}`;
  }

  const options = { method, headers };
  if (body) {
    options.body = JSON.stringify(body);
  }

  const res = await fetch(`${API_BASE}${endpoint}`, options);
  if (!res.ok) {
    const err = await res.json().catch(() => ({ error: 'Request failed' }));
    throw new Error(err.error || `HTTP ${res.status}`);
  }
  return res.json();
}

// --- ONBOARDING / INVITE REDEEM (§6) ---
async function handleOnboarding(event) {
  event.preventDefault();
  const nameInput = document.getElementById('input-name');
  const codeInput = document.getElementById('input-code');
  const errEl = document.getElementById('onboarding-error');
  const btn = document.getElementById('btn-join');

  const name = nameInput.value.trim();
  const code = codeInput.value.trim().toUpperCase();

  if (!name || !code) return;

  btn.disabled = true;
  btn.textContent = 'Connecting...';
  errEl.classList.add('hidden');

  try {
    const res = await apiCall('/auth/redeem', 'POST', { name, code });
    state.token = res.token;
    state.profile = res.profile;

    localStorage.setItem('musicbyadi_token', res.token);
    localStorage.setItem('musicbyadi_profile', JSON.stringify(res.profile));

    showMainApp();
    await refreshLibrary();
  } catch (err) {
    errEl.textContent = err.message;
    errEl.classList.remove('hidden');
  } finally {
    btn.disabled = false;
    btn.textContent = 'Join Stream';
  }
}

// --- DATA FETCHING & SYNC ---
async function refreshLibrary() {
  try {
    const songsData = await apiCall('/songs');
    state.songs = songsData.songs || [];

    // Pre-populate favorites set
    state.favorites = new Set(
      state.songs.filter(s => s.is_favorite).map(s => s.id)
    );

    const playlistsData = await apiCall('/playlists');
    state.playlists = playlistsData.playlists || [];
  } catch (err) {
    console.warn('Network fetch failed, falling back to local cache/offline tracks:', err);
  }

  renderStreamTab();
  renderPlaylistsTab();
  renderOfflineTab();
}

// --- HYBRID AUDIO ENGINE (§5) ---
function setupAudioEngine() {
  audio.addEventListener('timeupdate', () => {
    if (!audio.duration) return;
    const progress = (audio.currentTime / audio.duration) * 100;
    document.getElementById('mini-progress-fill').style.width = `${progress}%`;
    document.getElementById('expanded-scrubber').value = progress;
    document.getElementById('expanded-time-current').textContent = formatTime(audio.currentTime);
  });

  audio.addEventListener('loadedmetadata', () => {
    document.getElementById('expanded-time-total').textContent = formatTime(audio.duration);
  });

  audio.addEventListener('ended', () => {
    if (state.loopMode === 'one') {
      audio.currentTime = 0;
      audio.play();
    } else {
      playNextTrack();
    }
  });

  audio.addEventListener('play', () => {
    state.isPlaying = true;
    updatePlayPauseIcons();
    document.getElementById('waveform').classList.add('playing');
    highlightActiveSongInLists();
  });

  audio.addEventListener('pause', () => {
    state.isPlaying = false;
    updatePlayPauseIcons();
    document.getElementById('waveform').classList.remove('playing');
    highlightActiveSongInLists();
  });
}

/**
 * Hybrid Playback Resolver (§5)
 * Checks local downloaded cache first (zero egress), hits backend stream URL second.
 */
async function resolveAndPlay(song, contextQueue = null) {
  if (contextQueue) {
    state.queue = [...contextQueue];
    state.currentIndex = state.queue.findIndex(s => s.id === song.id);
  } else if (!state.queue.some(s => s.id === song.id)) {
    state.queue = [song];
    state.currentIndex = 0;
  } else {
    state.currentIndex = state.queue.findIndex(s => s.id === song.id);
  }

  state.currentSong = song;

  // Update Mini Player & Expanded Player UI
  miniPlayer.classList.remove('hidden');
  document.getElementById('mini-title').textContent = song.title;
  document.getElementById('mini-artist').textContent = song.artist || 'Unknown Artist';
  document.getElementById('expanded-title').textContent = song.title;
  document.getElementById('expanded-artist').textContent = song.artist || 'Unknown Artist';
  updateFavoriteButtonState();
  updateDownloadButtonState();

  try {
    let playUrl;
    if (state.downloadedTrackIds.has(song.id)) {
      // 1. Offline path (zero network egress)
      playUrl = `${API_BASE}${song.stream_url}`;
    } else {
      // 2. Fetch short-lived stream URL from Cloudflare Worker/Server
      const streamRes = await apiCall(`/songs/${song.id}/stream-url`);
      playUrl = streamRes.stream_url.startsWith('http')
        ? streamRes.stream_url
        : `${API_BASE}${streamRes.stream_url}`;
    }

    audio.src = playUrl;
    await audio.play();
  } catch (err) {
    console.error('Audio play failed:', err);
    showSnackbar(`Playback failed: ${err.message}`);
  }
}

function togglePlayPause() {
  if (!state.currentSong) return;
  if (audio.paused) {
    audio.play();
  } else {
    audio.pause();
  }
}

function playNextTrack() {
  if (!state.queue.length) return;
  if (state.currentIndex + 1 < state.queue.length) {
    state.currentIndex++;
    resolveAndPlay(state.queue[state.currentIndex]);
  } else if (state.loopMode === 'all') {
    state.currentIndex = 0;
    resolveAndPlay(state.queue[0]);
  }
}

function playPrevTrack() {
  if (!state.queue.length) return;
  if (audio.currentTime > 3) {
    audio.currentTime = 0;
    return;
  }
  if (state.currentIndex - 1 >= 0) {
    state.currentIndex--;
    resolveAndPlay(state.queue[state.currentIndex]);
  }
}

function updatePlayPauseIcons() {
  const miniIcon = document.getElementById('mini-play-icon');
  const largeIcon = document.getElementById('large-play-icon');

  if (state.isPlaying) {
    const pauseSvg = '<rect x="6" y="4" width="4" height="16"></rect><rect x="14" y="4" width="4" height="16"></rect>';
    miniIcon.innerHTML = pauseSvg;
    largeIcon.innerHTML = pauseSvg;
  } else {
    const playSvg = '<polygon points="5 3 19 12 5 21 5 3"></polygon>';
    miniIcon.innerHTML = playSvg;
    largeIcon.innerHTML = playSvg;
  }
}

// --- RENDER TAB 1: STREAM ---
function renderStreamTab() {
  // 1. Playlist Rail (§6, §8.9: cover-less, monochrome, capped at ~8-10 visible)
  const railEl = document.getElementById('playlist-rail');
  railEl.innerHTML = '';
  const railPlaylists = state.playlists.slice(0, 10);

  railPlaylists.forEach(pl => {
    const chip = document.createElement('div');
    chip.className = 'playlist-chip';
    chip.innerHTML = `
      <span>${escapeHtml(pl.name)}</span>
      <span class="playlist-chip-count">${pl.song_count || 0}</span>
    `;
    chip.addEventListener('click', () => {
      // Switch to Playlists tab
      switchTab('tab-playlists');
    });
    railEl.appendChild(chip);
  });

  // 2. Song list
  const listEl = document.getElementById('stream-song-list');
  listEl.innerHTML = '';

  const q = state.searchQuery.toLowerCase();
  const filtered = state.songs.filter(s => {
    if (!q) return true;
    return s.title.toLowerCase().includes(q) || (s.artist || '').toLowerCase().includes(q);
  });

  if (!filtered.length) {
    listEl.innerHTML = `<div style="padding: 32px 16px; text-align: center; color: var(--text-secondary); font-size: 13px;">
      ${q ? `No tracks found for "${escapeHtml(q)}"` : 'No songs available in stream.'}
    </div>`;
    return;
  }

  filtered.forEach(song => {
    const isCurrent = state.currentSong?.id === song.id;
    const isFavorite = state.favorites.has(song.id);
    const isDownloaded = state.downloadedTrackIds.has(song.id);

    const tile = document.createElement('div');
    tile.className = `song-tile ${isCurrent ? 'is-active' : ''}`;
    tile.dataset.id = song.id;

    tile.innerHTML = `
      <div class="song-tile-play-indicator">
        ${isCurrent && state.isPlaying ? '❚❚' : '▶'}
      </div>
      <div class="song-tile-info">
        <div class="song-tile-title">${escapeHtml(song.title)}</div>
        <div class="song-tile-meta">
          <span>${escapeHtml(song.artist || 'Unknown')}</span>
          <span>• ${formatBytes(song.size_bytes)}</span>
        </div>
      </div>
      <div class="song-tile-actions">
        <button class="song-tile-action-btn ${isFavorite ? 'active-favorite' : ''}" data-action="favorite" title="Favorite">
          ${isFavorite ? '♥' : '♡'}
        </button>
        <button class="song-tile-action-btn" data-action="add-playlist" title="Add to Playlist" style="font-size: 14px;">
          +≡
        </button>
        <button class="song-tile-action-btn ${isDownloaded ? 'active-downloaded' : ''}" data-action="download" title="Download">
          ${isDownloaded ? '✓' : '⇣'}
        </button>
      </div>
    `;

    // Click on row plays immediately (§6)
    tile.addEventListener('click', (e) => {
      if (e.target.closest('[data-action]')) return;
      resolveAndPlay(song, filtered);
    });

    // Favorite toggle
    tile.querySelector('[data-action="favorite"]').addEventListener('click', (e) => {
      e.stopPropagation();
      toggleFavorite(song.id);
    });

    // Add to playlist
    tile.querySelector('[data-action="add-playlist"]').addEventListener('click', (e) => {
      e.stopPropagation();
      openAddToPlaylistSheet(song);
    });

    // Download toggle
    tile.querySelector('[data-action="download"]').addEventListener('click', (e) => {
      e.stopPropagation();
      toggleDownload(song);
    });

    listEl.appendChild(tile);
  });
}

// --- RENDER TAB 2: PLAYLISTS ---
function renderPlaylistsTab() {
  const listEl = document.getElementById('playlists-list');
  listEl.innerHTML = '';

  const q = state.searchQuery.toLowerCase();
  const filtered = state.playlists.filter(p => {
    if (!q) return true;
    return p.name.toLowerCase().includes(q);
  });

  if (!filtered.length) {
    listEl.innerHTML = `<div style="padding: 32px 16px; text-align: center; color: var(--text-secondary); font-size: 13px;">
      ${q ? `No playlists found for "${escapeHtml(q)}"` : 'No playlists yet.'}
    </div>`;
    return;
  }

  filtered.forEach(pl => {
    const item = document.createElement('div');
    item.className = 'playlist-item';
    item.innerHTML = `
      <div>
        <div class="playlist-item-name">${escapeHtml(pl.name)}</div>
        <div class="playlist-item-tracks">${pl.song_count || 0} tracks • ${formatBytes(pl.total_bytes || 0)}</div>
      </div>
      <div style="display: flex; align-items: center; gap: 8px;">
        <button class="btn-small-accent" data-action="bulk-add" title="Add Multiple Songs in 1-Click" style="padding: 6px 10px; font-size: 11px;">
          + Add Songs
        </button>
        <button class="icon-btn" data-action="download-all" title="Download All">
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"></path>
            <polyline points="7 10 12 15 17 10"></polyline>
            <line x1="12" y1="15" x2="12" y2="3"></line>
          </svg>
        </button>
      </div>
    `;

    item.addEventListener('click', (e) => {
      if (e.target.closest('[data-action]')) return;
      openPlaylistDetailSheet(pl);
    });

    item.querySelector('[data-action="bulk-add"]').addEventListener('click', (e) => {
      e.stopPropagation();
      openBulkAddToPlaylistSheet(pl);
    });

    item.querySelector('[data-action="download-all"]').addEventListener('click', (e) => {
      e.stopPropagation();
      if (pl.songs) {
        pl.songs.forEach(s => toggleDownload(s, true));
        showSnackbar(`Downloading ${pl.songs.length} tracks in "${pl.name}"`);
      }
    });

    listEl.appendChild(item);
  });
}

// --- RENDER TAB 3: OFFLINE (§6) ---
function renderOfflineTab() {
  const downloadedSongs = state.songs.filter(s => state.downloadedTrackIds.has(s.id));
  const totalUsedBytes = downloadedSongs.reduce((sum, s) => sum + (s.size_bytes || 0), 0);

  // Storage Bar Text & Fill
  const storageText = document.getElementById('offline-storage-text');
  const storageFill = document.getElementById('storage-fill');
  storageText.textContent = `${formatBytes(totalUsedBytes)} used`;
  const pct = Math.min(100, Math.max(3, (totalUsedBytes / (5 * 1024 * 1024 * 1024)) * 100));
  storageFill.style.width = `${pct}%`;

  // Filter songs based on segment control (All / Playlists / Liked)
  let displayed = downloadedSongs;
  if (state.offlineFilter === 'liked') {
    displayed = downloadedSongs.filter(s => state.favorites.has(s.id));
  }

  const listEl = document.getElementById('offline-song-list');
  listEl.innerHTML = '';

  if (!displayed.length) {
    listEl.innerHTML = `
      <div style="padding: 48px 16px; text-align: center; color: var(--text-secondary); font-size: 13px;">
        <div style="font-size: 28px; margin-bottom: 8px;">⇣</div>
        <div>No offline tracks in this filter.</div>
        <div style="color: var(--text-disabled); font-size: 11px; margin-top: 4px;">
          Tap the download icon on any track to save for offline listening.
        </div>
      </div>
    `;
    return;
  }

  displayed.forEach(song => {
    const isCurrent = state.currentSong?.id === song.id;
    const tile = document.createElement('div');
    tile.className = `song-tile ${isCurrent ? 'is-active' : ''}`;
    tile.dataset.id = song.id;

    tile.innerHTML = `
      <div class="song-tile-play-indicator">
        ${isCurrent && state.isPlaying ? '❚❚' : '▶'}
      </div>
      <div class="song-tile-info">
        <div class="song-tile-title">${escapeHtml(song.title)}</div>
        <div class="song-tile-meta">
          <span>${escapeHtml(song.artist || 'Unknown')}</span>
          <span>• ${formatBytes(song.size_bytes)}</span>
        </div>
      </div>
      <div class="song-tile-actions">
        <button class="song-tile-action-btn" data-action="trash" title="Delete Offline Track" style="color: var(--text-disabled)">
          ✕
        </button>
      </div>
    `;

    tile.addEventListener('click', (e) => {
      if (e.target.closest('[data-action]')) return;
      resolveAndPlay(song, displayed);
    });

    // Trash deletes immediately with undo snackbar (§8.3)
    tile.querySelector('[data-action="trash"]').addEventListener('click', (e) => {
      e.stopPropagation();
      deleteOfflineTrack(song);
    });

    listEl.appendChild(tile);
  });
}

function highlightActiveSongInLists() {
  document.querySelectorAll('.song-tile').forEach(tile => {
    const id = tile.dataset.id;
    const isCurrent = state.currentSong?.id === id;
    const indicator = tile.querySelector('.song-tile-play-indicator');

    if (isCurrent) {
      tile.classList.add('is-active');
      if (indicator) indicator.textContent = state.isPlaying ? '❚❚' : '▶';
    } else {
      tile.classList.remove('is-active');
      if (indicator) indicator.textContent = '▶';
    }
  });
}

// --- ACTIONS: FAVORITE & DOWNLOAD & UNDO ---
async function toggleFavorite(songId) {
  try {
    const res = await apiCall(`/favorites/${songId}`, 'POST');
    if (res.is_favorite) {
      state.favorites.add(songId);
    } else {
      state.favorites.delete(songId);
    }
    updateFavoriteButtonState();
    renderStreamTab();
  } catch (err) {
    showSnackbar(`Favorite failed: ${err.message}`);
  }
}

function toggleDownload(song, forceAdd = false) {
  if (state.downloadedTrackIds.has(song.id) && !forceAdd) {
    deleteOfflineTrack(song);
  } else {
    state.downloadedTrackIds.add(song.id);
    localStorage.setItem('musicbyadi_downloads', JSON.stringify([...state.downloadedTrackIds]));
    showSnackbar(`Downloaded "${song.title}" for offline playback`);
    updateDownloadButtonState();
    renderStreamTab();
    renderOfflineTab();
  }
}

function deleteOfflineTrack(song) {
  state.downloadedTrackIds.delete(song.id);
  localStorage.setItem('musicbyadi_downloads', JSON.stringify([...state.downloadedTrackIds]));
  lastDeletedTrack = song;

  renderStreamTab();
  renderOfflineTab();

  // Undo snackbar (§8.3)
  showSnackbar(`Removed "${song.title}" from offline storage`, () => {
    // Restore
    state.downloadedTrackIds.add(lastDeletedTrack.id);
    localStorage.setItem('musicbyadi_downloads', JSON.stringify([...state.downloadedTrackIds]));
    lastDeletedTrack = null;
    renderStreamTab();
    renderOfflineTab();
  });
}

function updateFavoriteButtonState() {
  const btn = document.getElementById('btn-expanded-favorite');
  const label = document.getElementById('expanded-favorite-label');
  if (!state.currentSong) return;

  const isFav = state.favorites.has(state.currentSong.id);
  if (isFav) {
    btn.classList.add('active');
    label.textContent = 'FAVORITED';
  } else {
    btn.classList.remove('active');
    label.textContent = 'FAVORITE';
  }
}

function updateDownloadButtonState() {
  const btn = document.getElementById('btn-expanded-download');
  const label = document.getElementById('expanded-download-label');
  if (!state.currentSong) return;

  const isDown = state.downloadedTrackIds.has(state.currentSong.id);
  if (isDown) {
    btn.classList.add('active');
    label.textContent = 'DOWNLOADED';
  } else {
    btn.classList.remove('active');
    label.textContent = 'DOWNLOAD';
  }
}

// --- SETTINGS SCREEN (§6) ---
function renderProfileSettings() {
  if (!state.profile) return;
  document.getElementById('settings-profile-name').textContent = state.profile.name;
  document.getElementById('settings-profile-id').textContent = `ID: ${state.profile.id}`;
  document.getElementById('settings-profile-role').textContent = state.profile.role.toUpperCase();

  const wifiToggle = document.getElementById('toggle-wifi-only');
  wifiToggle.checked = state.wifiOnly;

  const downloadedSongs = state.songs.filter(s => state.downloadedTrackIds.has(s.id));
  const totalUsedBytes = downloadedSongs.reduce((sum, s) => sum + (s.size_bytes || 0), 0);
  document.getElementById('settings-storage-used').textContent = `${formatBytes(totalUsedBytes)} used`;
}

// --- ADMIN SCREEN (§6) ---
async function openAdminConsole() {
  adminScreen.classList.remove('hidden');
  await refreshAdminData();
}

async function refreshAdminData() {
  try {
    const statsData = await apiCall('/admin/stats');
    state.adminStats = statsData.stats || {};
    document.getElementById('stat-songs').textContent = state.adminStats.total_songs || 0;
    document.getElementById('stat-storage').textContent = formatBytes(state.adminStats.total_bytes || 0);
    document.getElementById('stat-users').textContent = state.adminStats.total_users || 0;
    document.getElementById('unredeemed-badge').textContent = state.adminStats.pending_invites || 0;

    const usersData = await apiCall('/admin/users');
    state.adminUsers = usersData.users || [];
    renderAdminUsers();

    const invitesData = await apiCall('/admin/invites');
    state.adminInvites = invitesData.invites || [];
    renderAdminInvites();

    // Fetch Cloudflare Storage Pools
    const poolsData = await apiCall('/admin/storage-pools').catch(() => ({ pools: [] }));
    state.adminPools = poolsData.pools || [];
    renderAdminPools();

    renderAdminSongs();
    renderAdminPlaylistsStorage();
  } catch (err) {
    showSnackbar(`Admin fetch failed: ${err.message}`);
  }
}

// --- ADMIN PLAYLIST STORAGE AUDIT & PER-SONG REMOVAL ---
function renderAdminPlaylistsStorage() {
  const el = document.getElementById('admin-playlists-storage-list');
  const countEl = document.getElementById('admin-playlists-count');
  if (countEl) countEl.textContent = state.playlists.length;
  if (!el) return;
  el.innerHTML = '';

  if (state.playlists.length === 0) {
    el.innerHTML = '<div style="font-size: 12px; color: var(--text-disabled); padding: 8px 0;">No playlists created yet.</div>';
    return;
  }

  state.playlists.forEach(pl => {
    const totalBytes = pl.total_bytes || (pl.songs || []).reduce((sum, s) => sum + (s.size_bytes || 0), 0);
    const item = document.createElement('div');
    item.className = 'admin-item';
    item.style.flexDirection = 'column';
    item.style.alignItems = 'stretch';
    item.style.gap = '8px';

    item.innerHTML = `
      <div style="display: flex; justify-content: space-between; align-items: center;">
        <div>
          <div style="font-size: 14px; font-weight: 600;">${escapeHtml(pl.name)}</div>
          <div style="font-size: 11px; color: var(--text-secondary);">
            ${pl.song_count || (pl.songs || []).length} songs • <strong style="color: var(--accent);">${formatBytes(totalBytes)}</strong> in Cloud
          </div>
        </div>
        <div style="display: flex; gap: 6px;">
          <button class="btn-small-accent" data-action="toggle-inspect" style="font-size: 11px; padding: 4px 8px;">
            Inspect Songs ▾
          </button>
          <button class="icon-btn" data-action="delete-playlist" style="color: var(--destructive-text); padding: 4px;" title="Delete Entire Playlist">
            ✕
          </button>
        </div>
      </div>
      <div class="playlist-songs-inspector hidden" style="border-top: 1px solid var(--divider); padding-top: 8px; margin-top: 4px;">
        ${(pl.songs && pl.songs.length) ? pl.songs.map(song => `
          <div style="display: flex; justify-content: space-between; align-items: center; padding: 6px 0; border-bottom: 1px solid rgba(255,255,255,0.05); font-size: 12px;">
            <div style="flex: 1; min-width: 0; padding-right: 8px;">
              <div style="font-weight: 500; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">${escapeHtml(song.title)}</div>
              <div style="font-size: 11px; color: var(--text-secondary);">${escapeHtml(song.artist || 'Unknown')}</div>
            </div>
            <div style="display: flex; align-items: center; gap: 10px;">
              <span style="font-family: monospace; font-size: 11px; color: var(--accent);">${formatBytes(song.size_bytes)}</span>
              <button class="icon-btn" data-remove-song="${song.id}" style="color: var(--destructive-text); padding: 2px;" title="Remove from playlist">
                ✕
              </button>
            </div>
          </div>
        `).join('') : '<div style="font-size: 11px; color: var(--text-disabled); padding: 4px 0;">No songs in this playlist</div>'}
      </div>
    `;

    // Toggle Inspector
    const toggleBtn = item.querySelector('[data-action="toggle-inspect"]');
    const inspector = item.querySelector('.playlist-songs-inspector');
    toggleBtn.addEventListener('click', () => {
      const isHidden = inspector.classList.contains('hidden');
      inspector.classList.toggle('hidden', !isHidden);
      toggleBtn.textContent = isHidden ? 'Hide Songs ▴' : 'Inspect Songs ▾';
    });

    // Remove individual song from playlist
    item.querySelectorAll('[data-remove-song]').forEach(btn => {
      btn.addEventListener('click', async () => {
        const songId = btn.dataset.removeSong;
        try {
          await apiCall(`/playlists/${pl.id}/songs/${songId}`, 'DELETE');
          showSnackbar(`Removed track from "${pl.name}"`);
          await refreshLibrary();
          await refreshAdminData();
        } catch (e) {
          showSnackbar('Error removing track: ' + e.message);
        }
      });
    });

    // Delete entire playlist
    item.querySelector('[data-action="delete-playlist"]').addEventListener('click', async () => {
      try {
        await apiCall(`/playlists/${pl.id}`, 'DELETE');
        showSnackbar(`Deleted playlist "${pl.name}"`);
        await refreshLibrary();
        await refreshAdminData();
      } catch (e) {
        showSnackbar('Error deleting playlist: ' + e.message);
      }
    });

    el.appendChild(item);
  });
}

// --- INTERACTIVE PLAYLIST DETAIL SHEET WITH PER-SONG SIZES & REMOVE ---
function openPlaylistDetailSheet(pl) {
  const sheet = document.getElementById('action-sheet');
  const heading = document.getElementById('sheet-heading');
  const body = document.getElementById('sheet-body');

  const totalBytes = pl.total_bytes || (pl.songs || []).reduce((sum, s) => sum + (s.size_bytes || 0), 0);
  heading.textContent = pl.name.toUpperCase();

  const role = state.profile?.role || 'listener';
  const canManage = role === 'owner' || role === 'contributor' || pl.created_by === state.profile?.id;

  body.innerHTML = `
    <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 14px; background: var(--surface-alt); padding: 10px 14px; border-radius: 8px;">
      <div>
        <div style="font-size: 13px; font-weight: 600;">Total Cloud Storage</div>
        <div style="font-size: 11px; color: var(--text-secondary);">${pl.song_count || (pl.songs || []).length} tracks in Cloudflare R2</div>
      </div>
      <div style="font-size: 16px; font-weight: 700; color: var(--accent); font-family: monospace;">
        ${formatBytes(totalBytes)}
      </div>
    </div>

    <div style="display: flex; gap: 8px; margin-bottom: 16px;">
      <button class="btn btn-primary" id="sheet-btn-play-all" style="flex: 1; height: 38px; font-size: 13px;">
        ▶ Play All
      </button>
      <button class="btn-small-accent" id="sheet-btn-add-more" style="height: 38px; padding: 0 14px; font-size: 12px;">
        + Add Songs
      </button>
    </div>

    <div style="max-height: 250px; overflow-y: auto; margin-bottom: 14px;">
      ${(pl.songs && pl.songs.length) ? pl.songs.map(song => `
        <div class="admin-item" style="margin-bottom: 6px; padding: 8px 12px; display: flex; justify-content: space-between; align-items: center;">
          <div style="flex: 1; min-width: 0; padding-right: 8px; cursor: pointer;" data-play-song="${song.id}">
            <div style="font-size: 13px; font-weight: 500; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">${escapeHtml(song.title)}</div>
            <div style="font-size: 11px; color: var(--text-secondary);">${escapeHtml(song.artist || 'Unknown')}</div>
          </div>
          <div style="display: flex; align-items: center; gap: 10px;">
            <span style="font-family: monospace; font-size: 11px; color: var(--accent);">${formatBytes(song.size_bytes)}</span>
            ${canManage ? `
              <button class="icon-btn" data-remove-song="${song.id}" style="color: var(--destructive-text); padding: 2px;" title="Remove from playlist">
                ✕
              </button>
            ` : ''}
          </div>
        </div>
      `).join('') : '<div style="color: var(--text-disabled); font-size: 12px; padding: 16px 0; text-align: center;">No tracks in this playlist yet. Tap "+ Add Songs" above!</div>'}
    </div>

    ${canManage ? `
      <div style="border-top: 1px solid var(--divider); padding-top: 12px; display: flex; justify-content: flex-end;">
        <button class="btn-text-danger" id="sheet-btn-delete-pl" style="font-size: 12px; padding: 4px 0;">Delete This Playlist</button>
      </div>
    ` : ''}
  `;

  // Play All
  document.getElementById('sheet-btn-play-all')?.addEventListener('click', () => {
    if (pl.songs && pl.songs.length) {
      closeActionSheet();
      resolveAndPlay(pl.songs[0], pl.songs);
    } else {
      showSnackbar('No songs in playlist to play');
    }
  });

  // Add more songs in 1-click
  document.getElementById('sheet-btn-add-more')?.addEventListener('click', () => {
    closeActionSheet();
    openBulkAddToPlaylistSheet(pl);
  });

  // Play single song from playlist
  body.querySelectorAll('[data-play-song]').forEach(item => {
    item.addEventListener('click', () => {
      const songId = item.dataset.playSong;
      const song = pl.songs.find(s => s.id === songId);
      if (song) {
        closeActionSheet();
        resolveAndPlay(song, pl.songs);
      }
    });
  });

  // Remove single song from playlist
  body.querySelectorAll('[data-remove-song]').forEach(btn => {
    btn.addEventListener('click', async () => {
      const songId = btn.dataset.removeSong;
      try {
        await apiCall(`/playlists/${pl.id}/songs/${songId}`, 'DELETE');
        showSnackbar('Removed track from playlist');
        await refreshLibrary();
        const updated = state.playlists.find(p => p.id === pl.id);
        if (updated) openPlaylistDetailSheet(updated);
        else closeActionSheet();
      } catch (e) {
        showSnackbar('Error removing song: ' + e.message);
      }
    });
  });

  // Delete entire playlist
  document.getElementById('sheet-btn-delete-pl')?.addEventListener('click', async () => {
    try {
      await apiCall(`/playlists/${pl.id}`, 'DELETE');
      closeActionSheet();
      await refreshLibrary();
      showSnackbar(`Deleted playlist "${pl.name}"`);
    } catch (e) {
      showSnackbar('Error deleting playlist: ' + e.message);
    }
  });

  sheet.classList.remove('hidden');
}

function renderAdminPools() {
  const el = document.getElementById('admin-pools-list');
  const countEl = document.getElementById('pools-count');
  if (countEl) countEl.textContent = (state.adminPools || []).length;
  if (!el) return;
  el.innerHTML = '';

  (state.adminPools || []).forEach(pool => {
    const item = document.createElement('div');
    item.className = 'admin-item';
    item.innerHTML = `
      <div>
        <div style="font-size: 13px; font-weight: 600;">${escapeHtml(pool.name)}</div>
        <div style="font-size: 11px; color: var(--text-secondary);">Bucket: <code>${escapeHtml(pool.bucket_name)}</code> • 10 GB Free Tier</div>
      </div>
      <div>
        <span style="color: var(--accent); font-size: 10px; font-weight: 700; border: 1px solid var(--divider); padding: 2px 6px; border-radius: 4px;">ACTIVE</span>
      </div>
    `;
    el.appendChild(item);
  });
}

function renderAdminUsers() {
  const el = document.getElementById('admin-users-list');
  el.innerHTML = '';

  state.adminUsers.forEach(u => {
    const item = document.createElement('div');
    item.className = 'admin-item';
    item.innerHTML = `
      <div>
        <div style="font-size: 13px; font-weight: 600;">${escapeHtml(u.name)}</div>
        <div style="font-size: 11px; color: var(--text-disabled);">${u.id}</div>
      </div>
      <button class="role-chip-toggle" data-uid="${u.id}">
        ${u.role.toUpperCase()} ↻
      </button>
    `;

    item.querySelector('.role-chip-toggle').addEventListener('click', async () => {
      await cycleUserRole(u);
    });

    el.appendChild(item);
  });
}

async function cycleUserRole(user) {
  if (user.id === state.profile.id) {
    showSnackbar('Owner cannot demote self (§6)');
    return;
  }

  const roleCycle = { listener: 'contributor', contributor: 'owner', owner: 'listener' };
  const nextRole = roleCycle[user.role] || 'listener';

  try {
    await apiCall(`/admin/users/${user.id}/role`, 'PATCH', { role: nextRole });
    await refreshAdminData();
  } catch (err) {
    showSnackbar(err.message);
  }
}

function renderAdminInvites() {
  const el = document.getElementById('admin-invites-list');
  el.innerHTML = '';

  if (!state.adminInvites.length) {
    el.innerHTML = '<div style="font-size: 12px; color: var(--text-disabled); padding: 8px 0;">No pending invites</div>';
    return;
  }

  state.adminInvites.forEach(inv => {
    const item = document.createElement('div');
    item.className = 'admin-item';
    item.innerHTML = `
      <div style="display: flex; align-items: center; gap: 8px;">
        <span style="font-family: monospace; font-size: 14px; font-weight: 700; letter-spacing: 2px;">${inv.code}</span>
      </div>
      <div style="display: flex; gap: 8px;">
        <button class="btn-small-accent" data-code="${inv.code}" data-action="copy">Copy</button>
        <button class="icon-btn" data-code="${inv.code}" data-action="revoke" style="color: var(--destructive-text);">✕</button>
      </div>
    `;

    item.querySelector('[data-action="copy"]').addEventListener('click', () => {
      navigator.clipboard.writeText(inv.code);
      showSnackbar(`Invite ${inv.code} copied!`);
    });

    item.querySelector('[data-action="revoke"]').addEventListener('click', async () => {
      await apiCall(`/admin/invites/${inv.code}`, 'DELETE');
      await refreshAdminData();
    });

    el.appendChild(item);
  });
}

function renderAdminSongs() {
  const el = document.getElementById('admin-songs-list');
  el.innerHTML = '';

  state.songs.forEach(s => {
    const item = document.createElement('div');
    item.className = 'admin-item';

    if (!state.bulkMode) {
      item.innerHTML = `
        <div>
          <div style="font-size: 13px; font-weight: 500;">${escapeHtml(s.title)}</div>
          <div style="font-size: 11px; color: var(--text-secondary);">${escapeHtml(s.artist || 'Unknown')}</div>
        </div>
        <button class="icon-btn" data-action="delete-single" style="color: var(--text-disabled)">✕</button>
      `;

      item.querySelector('[data-action="delete-single"]').addEventListener('click', async () => {
        try {
          await apiCall(`/songs/${s.id}`, 'DELETE');
          showSnackbar(`Deleted track "${s.title}"`);
          await refreshLibrary();
          await refreshAdminData();
        } catch (err) {
          showSnackbar(err.message);
        }
      });
    } else {
      const isChecked = state.selectedAdminSongs.has(s.id);
      item.innerHTML = `
        <label style="display: flex; align-items: center; gap: 10px; width: 100%; cursor: pointer;">
          <input type="checkbox" ${isChecked ? 'checked' : ''} data-id="${s.id}">
          <div>
            <div style="font-size: 13px;">${escapeHtml(s.title)}</div>
            <div style="font-size: 11px; color: var(--text-secondary);">${escapeHtml(s.artist || 'Unknown')}</div>
          </div>
        </label>
      `;

      item.querySelector('input').addEventListener('change', (e) => {
        if (e.target.checked) {
          state.selectedAdminSongs.add(s.id);
        } else {
          state.selectedAdminSongs.delete(s.id);
        }
        document.getElementById('bulk-selected-count').textContent = `${state.selectedAdminSongs.size} selected`;
      });
    }

    el.appendChild(item);
  });
}

// --- BOTTOM SHEET (UPLOAD SONG / NEW PLAYLIST) ---
function openActionSheet() {
  const sheet = document.getElementById('action-sheet');
  const heading = document.getElementById('sheet-heading');
  const body = document.getElementById('sheet-body');

  heading.textContent = state.currentTab === 'tab-playlists' ? 'NEW PLAYLIST' : 'UPLOAD TRACK';

  if (state.currentTab === 'tab-playlists') {
    body.innerHTML = `
      <div class="form-group">
        <label>PLAYLIST NAME</label>
        <input type="text" id="sheet-input-name" placeholder="e.g. Late Night Vibes" autocomplete="off" autofocus>
      </div>
      <button class="btn btn-primary" id="sheet-btn-submit">Create Playlist</button>
    `;

    document.getElementById('sheet-btn-submit').addEventListener('click', async () => {
      const name = document.getElementById('sheet-input-name').value.trim();
      if (!name) return;
      try {
        await apiCall('/playlists', 'POST', { name });
        closeActionSheet();
        await refreshLibrary();
        showSnackbar(`Created playlist "${name}"`);
      } catch (err) {
        showSnackbar(err.message);
      }
    });
  } else {
    body.innerHTML = `
      <div class="form-group">
        <label>TRACK TITLE</label>
        <input type="text" id="sheet-input-title" placeholder="e.g. Acoustic Waves" autocomplete="off">
      </div>
      <div class="form-group">
        <label>ARTIST / PRODUCER</label>
        <input type="text" id="sheet-input-artist" placeholder="e.g. Adi" autocomplete="off">
      </div>
      <button class="btn btn-primary" id="sheet-btn-submit">Add to Library</button>
    `;

    document.getElementById('sheet-btn-submit').addEventListener('click', async () => {
      const title = document.getElementById('sheet-input-title').value.trim();
      const artist = document.getElementById('sheet-input-artist').value.trim();
      if (!title) return;
      try {
        await apiCall('/songs', 'POST', {
          title,
          artist,
          duration_s: 180,
          size_bytes: 4200000
        });
        closeActionSheet();
        await refreshLibrary();
        showSnackbar(`Uploaded "${title}"`);
      } catch (err) {
        showSnackbar(err.message);
      }
    });
  }

  sheet.classList.remove('hidden');
}

function closeActionSheet() {
  document.getElementById('action-sheet').classList.add('hidden');
}

// --- ADD TO PLAYLIST SHEET ---
function openAddToPlaylistSheet(song) {
  const sheet = document.getElementById('action-sheet');
  const heading = document.getElementById('sheet-heading');
  const body = document.getElementById('sheet-body');

  heading.textContent = 'ADD TO PLAYLIST';

  const role = state.profile?.role || 'listener';
  const isContributorOrAbove = role === 'owner' || role === 'contributor';

  let playlistsHtml = '';
  if (!state.playlists || state.playlists.length === 0) {
    playlistsHtml = '<div style="color: var(--text-secondary); font-size: 13px; padding: 12px 0;">No playlists available.</div>';
  } else {
    playlistsHtml = state.playlists.map(pl => {
      const alreadyIn = pl.songs && pl.songs.some(s => s.id === song.id);
      return `
        <div class="admin-item" style="cursor: pointer; margin-bottom: 8px;" data-playlist-id="${pl.id}">
          <div>
            <div style="font-size: 14px; font-weight: 600;">${escapeHtml(pl.name)}</div>
            <div style="font-size: 11px; color: var(--text-secondary);">${pl.song_count || 0} tracks</div>
          </div>
          <div>
            ${alreadyIn
              ? '<span style="color: var(--accent); font-size: 11px; font-weight: 600;">✓ In Playlist</span>'
              : '<button class="btn-small-accent" style="pointer-events: none;">+ Add</button>'}
          </div>
        </div>
      `;
    }).join('');
  }

  body.innerHTML = `
    <div style="font-size: 12px; color: var(--text-secondary); margin-bottom: 12px;">
      Track: <strong style="color: var(--text-primary);">${escapeHtml(song.title)}</strong>
    </div>
    <div style="max-height: 200px; overflow-y: auto; margin-bottom: 16px;">
      ${playlistsHtml}
    </div>
    ${isContributorOrAbove ? `
      <div style="border-top: 1px solid var(--divider); padding-top: 14px;">
        <label style="display: block; font-size: 10px; font-weight: 600; letter-spacing: 1px; color: var(--text-secondary); margin-bottom: 6px;">OR CREATE NEW PLAYLIST</label>
        <div style="display: flex; gap: 8px;">
          <input type="text" id="new-pl-inline-input" placeholder="Playlist name..." style="flex: 1; height: 38px; background: var(--surface-alt); border: 1px solid var(--divider); border-radius: 6px; color: var(--text-primary); padding: 0 10px; font-size: 13px; outline: none;">
          <button class="btn-small-accent" id="btn-create-and-add" style="height: 38px; padding: 0 14px;">Create &amp; Add</button>
        </div>
      </div>
    ` : ''}
  `;

  // Attach click listeners to existing playlists
  body.querySelectorAll('[data-playlist-id]').forEach(item => {
    item.addEventListener('click', async () => {
      const plId = item.dataset.playlistId;
      const pl = state.playlists.find(p => p.id === plId);
      try {
        await apiCall(`/playlists/${plId}/songs`, 'POST', { song_id: song.id });
        closeActionSheet();
        await refreshLibrary();
        showSnackbar(`Added "${song.title}" to "${pl?.name || 'playlist'}"`);
      } catch (err) {
        showSnackbar('Failed to add: ' + err.message);
      }
    });
  });

  // Attach listener to create & add button
  const btnCreateAndAdd = document.getElementById('btn-create-and-add');
  if (btnCreateAndAdd) {
    btnCreateAndAdd.addEventListener('click', async () => {
      const input = document.getElementById('new-pl-inline-input');
      const name = input?.value.trim();
      if (!name) return;
      try {
        const createRes = await apiCall('/playlists', 'POST', { name });
        const newPl = createRes.playlist;
        await apiCall(`/playlists/${newPl.id}/songs`, 'POST', { song_id: song.id });
        closeActionSheet();
        await refreshLibrary();
        showSnackbar(`Created "${name}" & added "${song.title}"`);
      } catch (err) {
        showSnackbar('Error: ' + err.message);
      }
    });
  }

  sheet.classList.remove('hidden');
}

// --- MULTI-ADD SONGS TO PLAYLIST IN SINGLE CLICK ---
function openBulkAddToPlaylistSheet(playlist) {
  const sheet = document.getElementById('action-sheet');
  const heading = document.getElementById('sheet-heading');
  const body = document.getElementById('sheet-body');

  heading.textContent = `ADD SONGS TO "${playlist.name.toUpperCase()}"`;

  const existingIds = new Set((playlist.songs || []).map(s => s.id));
  const selectedSongIds = new Set();

  function renderList() {
    return state.songs.map(s => {
      const alreadyIn = existingIds.has(s.id);
      const isChecked = selectedSongIds.has(s.id);
      return `
        <label class="admin-item" style="cursor: pointer; margin-bottom: 6px; display: flex; align-items: center; gap: 12px; ${alreadyIn ? 'opacity: 0.5;' : ''}">
          <input type="checkbox" data-bulk-song="${s.id}" ${isChecked ? 'checked' : ''} ${alreadyIn ? 'disabled' : ''}>
          <div style="flex: 1; min-width: 0;">
            <div style="font-size: 13px; font-weight: 500;">${escapeHtml(s.title)}</div>
            <div style="font-size: 11px; color: var(--text-secondary);">${escapeHtml(s.artist || 'Unknown')} • ${formatBytes(s.size_bytes)}</div>
          </div>
          ${alreadyIn ? '<span style="color: var(--accent); font-size: 10px; font-weight: 700;">ALREADY IN</span>' : ''}
        </label>
      `;
    }).join('');
  }

  body.innerHTML = `
    <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 12px;">
      <span style="font-size: 12px; color: var(--text-secondary);" id="bulk-selection-summary">0 tracks selected</span>
      <div style="display: flex; gap: 8px;">
        <button class="btn-small-accent" id="btn-bulk-select-all" style="font-size: 11px; padding: 4px 8px;">Select All</button>
        <button class="btn-small-accent" id="btn-bulk-clear-all" style="font-size: 11px; padding: 4px 8px; background: var(--surface-alt); color: var(--text-secondary); border: 1px solid var(--divider);">Clear</button>
      </div>
    </div>
    <div id="bulk-songs-container" style="max-height: 260px; overflow-y: auto; margin-bottom: 16px;">
      ${renderList()}
    </div>
    <button class="btn btn-primary" id="btn-submit-bulk-add" style="display: flex; align-items: center; justify-content: center; gap: 8px;">
      ⚡ Add Selected Songs (0) in 1-Click
    </button>
  `;

  function updateSummaryAndButton() {
    const summary = document.getElementById('bulk-selection-summary');
    const submitBtn = document.getElementById('btn-submit-bulk-add');
    if (summary) summary.textContent = `${selectedSongIds.size} tracks selected`;
    if (submitBtn) {
      submitBtn.textContent = `⚡ Add Selected Songs (${selectedSongIds.size}) in 1-Click`;
      submitBtn.disabled = selectedSongIds.size === 0;
    }
  }

  function wireCheckboxes() {
    body.querySelectorAll('[data-bulk-song]').forEach(chk => {
      chk.addEventListener('change', (e) => {
        const id = chk.dataset.bulkSong;
        if (e.target.checked) selectedSongIds.add(id);
        else selectedSongIds.delete(id);
        updateSummaryAndButton();
      });
    });
  }

  wireCheckboxes();
  updateSummaryAndButton();

  // Select all eligible songs
  document.getElementById('btn-bulk-select-all').addEventListener('click', () => {
    state.songs.forEach(s => {
      if (!existingIds.has(s.id)) selectedSongIds.add(s.id);
    });
    body.querySelector('#bulk-songs-container').innerHTML = renderList();
    wireCheckboxes();
    updateSummaryAndButton();
  });

  // Clear all
  document.getElementById('btn-bulk-clear-all').addEventListener('click', () => {
    selectedSongIds.clear();
    body.querySelector('#bulk-songs-container').innerHTML = renderList();
    wireCheckboxes();
    updateSummaryAndButton();
  });

  // Submit in single click
  document.getElementById('btn-submit-bulk-add').addEventListener('click', async () => {
    if (selectedSongIds.size === 0) return;
    const song_ids = Array.from(selectedSongIds);
    const submitBtn = document.getElementById('btn-submit-bulk-add');
    submitBtn.disabled = true;
    submitBtn.textContent = 'Adding...';

    try {
      const res = await apiCall(`/playlists/${playlist.id}/bulk-songs`, 'POST', { song_ids });
      closeActionSheet();
      await refreshLibrary();
      showSnackbar(`Added ${res.added_count || song_ids.length} tracks to "${playlist.name}"!`);
    } catch (err) {
      showSnackbar('Error adding songs: ' + err.message);
      submitBtn.disabled = false;
      updateSummaryAndButton();
    }
  });

  sheet.classList.remove('hidden');
}

// --- EVENT LISTENERS ---
function setupEventListeners() {
  // Quick 1-Click Login buttons on onboarding
  const btnQuickAdmin = document.getElementById('btn-quick-admin');
  if (btnQuickAdmin) {
    btnQuickAdmin.addEventListener('click', async () => {
      try {
        const res = await apiCall('/auth/login-as', 'POST', { role: 'owner' });
        state.token = res.token;
        state.profile = res.profile;
        localStorage.setItem('musicbyadi_token', res.token);
        localStorage.setItem('musicbyadi_profile', JSON.stringify(res.profile));
        showMainApp();
        await refreshLibrary();
        showSnackbar('Signed in as Admin / Owner (Adi)');
      } catch (e) {
        showSnackbar('Quick login failed: ' + e.message);
      }
    });
  }

  const btnQuickListener = document.getElementById('btn-quick-listener');
  if (btnQuickListener) {
    btnQuickListener.addEventListener('click', async () => {
      try {
        const res = await apiCall('/auth/login-as', 'POST', { role: 'listener' });
        state.token = res.token;
        state.profile = res.profile;
        localStorage.setItem('musicbyadi_token', res.token);
        localStorage.setItem('musicbyadi_profile', JSON.stringify(res.profile));
        showMainApp();
        await refreshLibrary();
        showSnackbar('Signed in as Listener (Sarah)');
      } catch (e) {
        showSnackbar('Quick login failed: ' + e.message);
      }
    });
  }

  // Navigation Tabs
  document.querySelectorAll('.nav-item').forEach(btn => {
    btn.addEventListener('click', () => {
      const tabId = btn.dataset.tab;
      switchTab(tabId);
    });
  });

  // Offline Segment Control
  document.querySelectorAll('.segment-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.segment-btn').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      state.offlineFilter = btn.dataset.filter;
      renderOfflineTab();
    });
  });

  // Offline Simulated Toggle
  const offlineBadge = document.getElementById('offline-sim-toggle');
  offlineBadge.addEventListener('click', () => {
    state.simulatedOffline = !state.simulatedOffline;
    if (state.simulatedOffline) {
      offlineBadge.classList.add('offline-active');
      offlineBadge.textContent = 'OFFLINE MODE';
      showSnackbar('Simulated offline mode: serving offline cached library');
    } else {
      offlineBadge.classList.remove('offline-active');
      offlineBadge.textContent = 'ONLINE';
      showSnackbar('Connected: online streaming enabled');
    }
  });

  // Inline Expanding Search (§6, §8.7)
  const searchContainer = document.getElementById('search-container');
  const toggleSearchBtn = document.getElementById('btn-toggle-search');
  const searchInput = document.getElementById('inline-search-input');
  const clearSearchBtn = document.getElementById('btn-clear-search');

  toggleSearchBtn.addEventListener('click', () => {
    searchInput.classList.remove('hidden');
    clearSearchBtn.classList.remove('hidden');
    toggleSearchBtn.classList.add('hidden');
    searchInput.focus();
  });

  clearSearchBtn.addEventListener('click', () => {
    searchInput.value = '';
    state.searchQuery = '';
    searchInput.classList.add('hidden');
    clearSearchBtn.classList.add('hidden');
    toggleSearchBtn.classList.remove('hidden');
    renderStreamTab();
    renderPlaylistsTab();
  });

  searchInput.addEventListener('input', (e) => {
    state.searchQuery = e.target.value;
    renderStreamTab();
    renderPlaylistsTab();
  });

  // Mini Player Play/Pause and Next
  document.getElementById('mini-btn-play').addEventListener('click', (e) => {
    e.stopPropagation();
    togglePlayPause();
  });

  document.getElementById('mini-btn-next').addEventListener('click', (e) => {
    e.stopPropagation();
    playNextTrack();
  });

  // Expand Player Click
  document.getElementById('mini-player-expand-trigger').addEventListener('click', () => {
    expandedPlayer.classList.remove('hidden');
  });

  // Collapse Player
  document.getElementById('btn-collapse-player').addEventListener('click', () => {
    expandedPlayer.classList.add('hidden');
  });
  document.getElementById('expanded-player-close').addEventListener('click', () => {
    expandedPlayer.classList.add('hidden');
  });

  // Expanded Player Controls
  document.getElementById('btn-play-large').addEventListener('click', togglePlayPause);
  document.getElementById('btn-next').addEventListener('click', playNextTrack);
  document.getElementById('btn-prev').addEventListener('click', playPrevTrack);

  document.getElementById('btn-shuffle').addEventListener('click', () => {
    state.isShuffling = !state.isShuffling;
    document.getElementById('btn-shuffle').classList.toggle('active', state.isShuffling);
  });

  document.getElementById('btn-loop').addEventListener('click', () => {
    if (state.loopMode === 'off') state.loopMode = 'all';
    else if (state.loopMode === 'all') state.loopMode = 'one';
    else state.loopMode = 'off';
    document.getElementById('btn-loop').classList.toggle('active', state.loopMode !== 'off');
  });

  // Scrubber Seek
  const scrubber = document.getElementById('expanded-scrubber');
  scrubber.addEventListener('input', () => {
    if (audio.duration) {
      audio.currentTime = (scrubber.value / 100) * audio.duration;
    }
  });

  // Expanded Favorite & Download buttons
  document.getElementById('btn-expanded-favorite').addEventListener('click', () => {
    if (state.currentSong) toggleFavorite(state.currentSong.id);
  });

  document.getElementById('btn-expanded-download').addEventListener('click', () => {
    if (state.currentSong) toggleDownload(state.currentSong);
  });

  const btnExpandedAddPlaylist = document.getElementById('btn-expanded-add-playlist');
  if (btnExpandedAddPlaylist) {
    btnExpandedAddPlaylist.addEventListener('click', () => {
      if (state.currentSong) openAddToPlaylistSheet(state.currentSong);
    });
  }

  // Settings Screen Pushed Navigation (§6)
  document.getElementById('btn-open-settings').addEventListener('click', () => {
    renderProfileSettings();
    settingsScreen.classList.remove('hidden');
  });

  document.getElementById('btn-close-settings').addEventListener('click', () => {
    settingsScreen.classList.add('hidden');
  });

  document.getElementById('toggle-wifi-only').addEventListener('change', (e) => {
    state.wifiOnly = e.target.checked;
    localStorage.setItem('musicbyadi_wifi_only', state.wifiOnly);
  });

  document.getElementById('btn-clear-downloads').addEventListener('click', () => {
    state.downloadedTrackIds.clear();
    localStorage.removeItem('musicbyadi_downloads');
    renderProfileSettings();
    renderOfflineTab();
    showSnackbar('Cleared all offline downloads');
  });

  document.getElementById('btn-signout').addEventListener('click', () => {
    localStorage.clear();
    location.reload();
  });

  // Admin Screen
  document.getElementById('btn-open-admin').addEventListener('click', openAdminConsole);
  document.getElementById('btn-close-admin').addEventListener('click', () => {
    adminScreen.classList.add('hidden');
  });

  document.getElementById('btn-admin-generate-invite').addEventListener('click', async () => {
    try {
      const res = await apiCall('/admin/invites', 'POST');
      showSnackbar(`Generated code: ${res.invite.code}`);
      await refreshAdminData();
    } catch (err) {
      showSnackbar(err.message);
    }
  });

  document.getElementById('btn-toggle-bulk').addEventListener('click', () => {
    state.bulkMode = !state.bulkMode;
    state.selectedAdminSongs.clear();
    document.getElementById('bulk-actions-bar').classList.toggle('hidden', !state.bulkMode);
    document.getElementById('btn-toggle-bulk').textContent = state.bulkMode ? 'Done' : 'Bulk Select';
    renderAdminSongs();
  });

  document.getElementById('btn-bulk-delete').addEventListener('click', async () => {
    for (const songId of state.selectedAdminSongs) {
      await apiCall(`/songs/${songId}`, 'DELETE').catch(() => {});
    }
    state.selectedAdminSongs.clear();
    await refreshLibrary();
    await refreshAdminData();
    showSnackbar('Deleted selected songs');
  });

  // Add Cloudflare Storage Pool button
  const btnAddPool = document.getElementById('btn-add-pool');
  if (btnAddPool) {
    btnAddPool.addEventListener('click', openAddPoolSheet);
  }

  // Install Mobile App button
  const btnInstallMobile = document.getElementById('btn-install-mobile');
  if (btnInstallMobile) {
    btnInstallMobile.addEventListener('click', async () => {
      if (deferredInstallPrompt) {
        deferredInstallPrompt.prompt();
        const { outcome } = await deferredInstallPrompt.userChoice;
        if (outcome === 'accepted') {
          showSnackbar('Installing Music by Adi on your phone!');
        }
        deferredInstallPrompt = null;
      } else {
        // Show instructions modal / snackbar
        showMobileInstallSheet();
      }
    });
  }

  // FAB Click
  fabCreate.addEventListener('click', openActionSheet);
  document.getElementById('sheet-backdrop').addEventListener('click', closeActionSheet);
}

// --- PWA INSTALL & CLOUDFLARE POOLS SHEET ---
let deferredInstallPrompt = null;
window.addEventListener('beforeinstallprompt', (e) => {
  e.preventDefault();
  deferredInstallPrompt = e;
  const title = document.getElementById('install-mobile-title');
  if (title) title.textContent = 'Install App on Phone (1-Tap Ready)';
});

if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('/sw.js').catch(() => {});
}

function showMobileInstallSheet() {
  const sheet = document.getElementById('action-sheet');
  const heading = document.getElementById('sheet-heading');
  const body = document.getElementById('sheet-body');

  heading.textContent = 'INSTALL ON YOUR PHONE';
  body.innerHTML = `
    <div style="font-size: 13px; line-height: 1.6; color: var(--text-primary); margin-bottom: 16px;">
      <p style="margin-bottom: 10px;"><strong>Method 1: 1-Tap Home Screen Install (Recommended)</strong></p>
      <div style="color: var(--text-secondary); font-size: 12px; margin-bottom: 14px; background: var(--surface-alt); padding: 10px; border-radius: 6px;">
        1. Open this website on your Android phone's Chrome browser: <br>
        <code>http://YOUR_PC_IP:3000</code><br>
        2. Tap Chrome's menu (<strong>⋮</strong> in top-right) and tap <strong>"Install app"</strong> or <strong>"Add to Home screen"</strong>.<br>
        3. An app icon named <strong>MusicByAdi</strong> will be installed on your phone!
      </div>

      <p style="margin-bottom: 10px;"><strong>Method 2: Standalone Android APK</strong></p>
      <div style="color: var(--text-secondary); font-size: 12px; background: var(--surface-alt); padding: 10px; border-radius: 6px;">
        To compile the native .apk, run in terminal:<br>
        <code>flutter build apk --release</code><br>
        The installer will be generated at:<br>
        <code>build/app/outputs/flutter-apk/app-release.apk</code>
      </div>
    </div>
    <button class="btn btn-primary" onclick="closeActionSheet()">Got It</button>
  `;
  sheet.classList.remove('hidden');
}

function openAddPoolSheet() {
  const sheet = document.getElementById('action-sheet');
  const heading = document.getElementById('sheet-heading');
  const body = document.getElementById('sheet-body');

  heading.textContent = 'CONNECT CLOUDFLARE ACCOUNT';
  body.innerHTML = `
    <div style="font-size: 12px; color: var(--text-secondary); margin-bottom: 12px;">
      Add multiple Cloudflare accounts to pool free <strong>10 GB R2 storage</strong> per account!
    </div>
    <div class="form-group">
      <label>ACCOUNT NICKNAME</label>
      <input type="text" id="pool-input-name" placeholder="e.g. Second Cloudflare Account" autocomplete="off">
    </div>
    <div class="form-group">
      <label>R2 BUCKET NAME</label>
      <input type="text" id="pool-input-bucket" placeholder="e.g. musicbyadi-audio-2" autocomplete="off">
    </div>
    <div class="form-group">
      <label>ACCOUNT ID (OPTIONAL)</label>
      <input type="text" id="pool-input-account" placeholder="From Cloudflare dashboard URL" autocomplete="off">
    </div>
    <button class="btn btn-primary" id="btn-save-pool">Add Storage Account</button>
  `;

  document.getElementById('btn-save-pool').addEventListener('click', async () => {
    const name = document.getElementById('pool-input-name').value.trim();
    const bucket = document.getElementById('pool-input-bucket').value.trim();
    const accountId = document.getElementById('pool-input-account').value.trim();
    if (!name || !bucket) {
      showSnackbar('Please enter Account Nickname and Bucket Name');
      return;
    }
    try {
      await apiCall('/admin/storage-pools', 'POST', {
        name,
        bucket_name: bucket,
        account_id: accountId
      });
      closeActionSheet();
      await refreshAdminData();
      showSnackbar(`Connected Cloudflare account "${name}"!`);
    } catch (e) {
      showSnackbar('Error: ' + e.message);
    }
  });

  sheet.classList.remove('hidden');
}

function switchTab(tabId) {
  state.currentTab = tabId;

  document.querySelectorAll('.nav-item').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.tab === tabId);
  });

  document.querySelectorAll('.tab-pane').forEach(pane => {
    pane.classList.toggle('hidden', pane.id !== tabId);
    pane.classList.toggle('active', pane.id === tabId);
  });

  const titles = {
    'tab-stream': 'STREAM',
    'tab-playlists': 'PLAYLISTS',
    'tab-offline': 'OFFLINE LIBRARY'
  };
  document.getElementById('screen-title').textContent = titles[tabId] || 'STREAM';
}

function showSnackbar(text, onUndo = null) {
  const bar = document.getElementById('snackbar');
  const textEl = document.getElementById('snackbar-text');
  const undoBtn = document.getElementById('snackbar-undo');

  clearTimeout(snackbarTimeout);
  textEl.textContent = text;

  if (onUndo) {
    undoBtn.classList.remove('hidden');
    undoBtn.onclick = () => {
      onUndo();
      bar.classList.add('hidden');
    };
  } else {
    undoBtn.classList.add('hidden');
  }

  bar.classList.remove('hidden');
  snackbarTimeout = setTimeout(() => {
    bar.classList.add('hidden');
  }, 4000);
}

// Utility formatters
function formatTime(seconds) {
  if (isNaN(seconds) || seconds < 0) return '0:00';
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${m}:${s < 10 ? '0' : ''}${s}`;
}

function formatBytes(bytes) {
  if (!bytes) return '0 B';
  const mb = bytes / (1024 * 1024);
  if (mb >= 1) return `${mb.toFixed(1)} MB`;
  const kb = bytes / 1024;
  return `${kb.toFixed(0)} KB`;
}

function escapeHtml(str) {
  if (!str) return '';
  return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}
