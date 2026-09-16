import QtQuick
import Quickshell.Services.Mpris
import "MediaModel.js" as MediaModel

// Local stand-in for the omarchy.media service, which the shell never hands
// to a third-party "panel" plugin (see MediaModel.js). Reads MPRIS players
// straight off Quickshell's own Mpris singleton, so Spotify (or anything
// else exposing org.mpris.MediaPlayer2.*) shows up regardless of Omarchy's
// plugin capability scoping. Mirrors the shape of the real omarchy.media
// service closely enough that Notch.qml doesn't need to know the difference.
Item {
  id: root

  property string preferredPlayerKey: ""
  property var playerStartedAt: ({})
  property int playSerial: 0

  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var sourceCyclePlayers: orderedCycleSourcePlayers()
  readonly property var activePlayer: selectActivePlayer()
  readonly property bool hasMedia: activePlayer !== null && !!(activePlayer.trackTitle || activePlayer.trackArtist)
  readonly property string title: activePlayer ? (activePlayer.trackTitle || "") : ""
  readonly property string artist: activePlayer ? (activePlayer.trackArtist || "") : ""
  readonly property string album: activePlayer && activePlayer.trackAlbum ? activePlayer.trackAlbum : ""
  readonly property string artUrl: activePlayer && activePlayer.trackArtUrl ? activePlayer.trackArtUrl : ""
  readonly property string identity: activePlayer ? (activePlayer.identity || activePlayer.desktopEntry || "") : ""

  function playerAppLabel(player) { return MediaModel.playerAppLabel(player) }
  function playerKey(player) { return MediaModel.playerKey(player) }

  function playerForKey(key) {
    if (!key) return null
    for (var i = 0; i < players.length; i++) {
      if (playerKey(players[i]) === key) return players[i]
    }
    return null
  }

  function playerOrder(player, fallback) {
    var key = playerKey(player)
    var value = key ? playerStartedAt[key] : undefined
    return value === undefined ? fallback : value
  }

  function syncPlayingOrder() {
    var next = {}
    var alive = {}
    var serial = playSerial

    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      var key = playerKey(p)
      if (!key) continue

      alive[key] = true
      if (!p.isPlaying) continue

      if (playerStartedAt[key] === undefined) {
        serial += 1
        next[key] = serial
      } else {
        next[key] = playerStartedAt[key]
      }
    }

    if (preferredPlayerKey && !alive[preferredPlayerKey]) preferredPlayerKey = ""

    playSerial = serial
    playerStartedAt = next
  }

  function orderedCycleSourcePlayers() {
    var list = []
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (MediaModel.canCycleSource(p)) list.push(p)
    }

    list.sort(function(a, b) {
      var proxyA = MediaModel.isProxyPlayer(a)
      var proxyB = MediaModel.isProxyPlayer(b)
      if (proxyA !== proxyB) return proxyA ? 1 : -1
      return MediaModel.labelFor(a).localeCompare(MediaModel.labelFor(b))
    })

    return list
  }

  function oldestPlayingPlayer() {
    var oldest = null
    var oldestOrder = 0
    var playingProxy = null
    var proxyOrder = 0

    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (!p || !p.isPlaying) continue

      var proxy = MediaModel.isProxyPlayer(p)
      var order = playerOrder(p, i + 1000)
      if (!proxy && (!oldest || order < oldestOrder)) {
        oldest = p
        oldestOrder = order
      } else if (proxy && (!playingProxy || order < proxyOrder)) {
        playingProxy = p
        proxyOrder = order
      }
    }

    return oldest || playingProxy || null
  }

  function selectActivePlayer() {
    var preferred = null
    var trackPlayer = null
    var trackProxy = null
    var controllablePlayer = null
    var controllableProxy = null
    var identityPlayer = null
    var identityProxy = null

    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (!p) continue

      var proxy = MediaModel.isProxyPlayer(p)

      if (preferredPlayerKey && playerKey(p) === preferredPlayerKey && MediaModel.hasMetadata(p)) preferred = p

      if (MediaModel.hasTrackMetadata(p)) {
        if (!proxy && !trackPlayer) trackPlayer = p
        else if (proxy && !trackProxy) trackProxy = p
      } else if (MediaModel.playerCanControl(p)) {
        if (!proxy && !controllablePlayer) controllablePlayer = p
        else if (proxy && !controllableProxy) controllableProxy = p
      } else if (MediaModel.hasMetadata(p)) {
        if (!proxy && !identityPlayer) identityPlayer = p
        else if (proxy && !identityProxy) identityProxy = p
      }
    }

    if (preferred && preferred.isPlaying) return preferred
    return oldestPlayingPlayer() || preferred || trackPlayer || trackProxy
      || controllablePlayer || controllableProxy || identityPlayer || identityProxy || null
  }

  function switchSource(delta) {
    var list = sourceCyclePlayers
    if (!list || list.length === 0) return false

    var activeKey = playerKey(activePlayer)
    var index = 0
    for (var i = 0; i < list.length; i++) {
      if (playerKey(list[i]) === activeKey) { index = i; break }
    }

    index = (index + delta + list.length) % list.length
    preferredPlayerKey = playerKey(list[index])
    return true
  }

  Component.onCompleted: root.syncPlayingOrder()
  onPlayersChanged: root.syncPlayingOrder()

  Instantiator {
    model: root.players
    delegate: Connections {
      required property var modelData
      target: modelData
      function onIsPlayingChanged() { root.syncPlayingOrder() }
    }
  }
}
