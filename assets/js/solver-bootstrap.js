// Yubbly bridge for the yt-dlp/ejs YouTube n-signature solver.
// The two minified files above are bundled dependencies.
window.__yubblyPlayers = window.__yubblyPlayers || {};

window.__yubblySolveN = function (playerUrl, playerJs, challenge) {
  try {
    if (playerJs && !window.__yubblyPlayers[playerUrl]) {
      window.__yubblyPlayers[playerUrl] = playerJs;
    }
    var player = window.__yubblyPlayers[playerUrl];
    if (!player) {
      return JSON.stringify({ error: 'Player JavaScript not loaded.' });
    }
    var result = jsc({
      type: 'player',
      player: player,
      requests: [{ type: 'n', challenges: [challenge] }]
    });
    var response = result && result.responses && result.responses[0];
    if (!response || response.type !== 'result') {
      return JSON.stringify({
        error: (response && response.error) || 'Solver returned no result.'
      });
    }
    var value = response.data && response.data[challenge];
    if (!value) {
      return JSON.stringify({ error: 'Solver returned no value.' });
    }
    return JSON.stringify({ value: value });
  } catch (e) {
    return JSON.stringify({ error: String((e && e.stack) || e) });
  }
};
