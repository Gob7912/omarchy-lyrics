pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

Item {
  id: root

  readonly property var players: Mpris.players ? Mpris.players.values : []

  // Music players score higher than browsers, messengers are discarded
  readonly property var musicApps: /spotify|yandex|vk ?music|vkmusic|deezer|tidal|apple ?music|cider|amberol|rhythmbox|elisa|strawberry|clementine|audacious|lollypop|cmus|mpd|ncspot|spotube|feishin|youtube.?music|ytmusic|soundcloud|tauon|deadbeef|foobar|museeks|haruna|celluloid|mpv|vlc/i
  readonly property var notMusic: /telegram|discord|zoom|skype|teams|whatsapp|signal|slack|element|obs|steam/i

  function playerScore(p) {
    if (!p) return -1000
    var id = (p.identity || "") + " " + (p.desktopEntry || "") + " " + (p.dbusName || "")
    var s = 0
    if (p.isPlaying) s += 100
    if (notMusic.test(id)) s -= 200
    else if (musicApps.test(id)) s += 30
    if (p.trackTitle) s += 10
    if (p.trackArtist) s += 5
    return s
  }

  property int _playerTrigger: 0
  function reevaluatePlayer() {
    _playerTrigger++
  }

  readonly property var player: {
    var trigger = _playerTrigger
    var best = null, top = -100
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      var s = playerScore(p)
      if (s > top) {
        best = p
        top = s
      }
    }
    return best
  }

  Instantiator {
    model: root.players
    delegate: Connections {
      required property var modelData
      target: modelData
      ignoreUnknownSignals: true
      function onIsPlayingChanged() { root.reevaluatePlayer() }
      function onPlaybackStateChanged() { root.reevaluatePlayer() }
      function onPostTrackChanged() { root.reevaluatePlayer() }
    }
  }

  function clearLyrics() {
    lines = []
    plainText = ""
    source = ""
    index = -1
    wordChars = 0
    _pendingKey = ""
    status = "idle"
  }

  onPlayerChanged: {
    clearLyrics()
    fetchTimer.restart()
  }

  readonly property bool isPlaying: player ? player.isPlaying : false
  readonly property string title: player ? (player.trackTitle || "") : ""
  readonly property string artist: player ? (player.trackArtist || "") : ""
  readonly property string album: player ? (player.trackAlbum || "") : ""
  readonly property string artUrl: player ? (player.trackArtUrl || "") : ""
  readonly property real length: player && player.lengthSupported ? player.length : 0

  // Per-track offsets & global fallback
  property int defaultOffsetMs: 0
  property int offsetMs: 0
  readonly property real offsetSec: offsetMs / 1000
  property real position: 0
  property var trackOffsets: ({})

  readonly property string cacheDir: {
    var base = Quickshell.env("XDG_CACHE_HOME")
    if (!base || base === "") base = Quickshell.env("HOME") + "/.cache"
    return base + "/omarchy/lyrics"
  }

  FileView {
    id: trackOffsetsReader
    path: root.cacheDir + "/track_offsets.json"
    printErrors: false
    onLoaded: {
      try {
        root.trackOffsets = JSON.parse(text()) || {}
        root.applyTrackOffset()
      } catch (e) {}
    }
  }

  Process {
    id: saveTrackOffsetsProcess
  }

  function applyTrackOffset() {
    if (trackKey && root.trackOffsets && root.trackOffsets[trackKey] !== undefined) {
      offsetMs = root.trackOffsets[trackKey]
    } else {
      offsetMs = defaultOffsetMs
    }
  }

  function setOffset(val) {
    offsetMs = Math.max(-5000, Math.min(5000, val))
    if (trackKey) {
      var copy = Object.assign({}, trackOffsets)
      copy[trackKey] = offsetMs
      trackOffsets = copy
      saveTrackOffsetsProcess.running = false
      saveTrackOffsetsProcess.command = [
        "python3", "-c",
        "import sys, pathlib, json; p=pathlib.Path(sys.argv[1]); p.parent.mkdir(parents=True, exist_ok=True); p.write_text(json.dumps(json.loads(sys.argv[2]), indent=2), encoding='utf-8')",
        cacheDir + "/track_offsets.json", JSON.stringify(trackOffsets)
      ]
      saveTrackOffsetsProcess.running = true
    }
    updateIndex()
  }

  readonly property bool fromBrowser: {
    if (!player) return false
    var id = (player.identity || "") + " " + (player.desktopEntry || "") + " " + (player.dbusName || "")
    return /firefox|chrom|brave|vivaldi|helium|zen|edge|opera|librewolf|browser|yandex/i.test(id)
  }

  readonly property bool isYouTube: {
    if (!player) return false
    var trackUrl = player.trackUrl ? String(player.trackUrl) : ""
    var trackId = player.trackId ? String(player.trackId) : ""
    var t = title || ""
    var a = artist || ""
    return /youtube/i.test(trackUrl) || /youtube/i.test(trackId) || /youtube/i.test(t) || /youtube/i.test(a) || fromBrowser
  }

  readonly property string trackKey: artist + "\u0001" + title
  property var lines: []
  property string plainText: ""
  property string source: "" // lrclib | netease | lrc.cx | kugou | qq | amll | local
  property string status: "idle" // idle | loading | ok | plain | instrumental | notfound | error
  property int index: -1

  readonly property bool hasLyrics: (status === "ok" || status === "plain") && lines && lines.length > 0
  readonly property string current: {
    if (!lines || !Array.isArray(lines) || index < 0 || index >= lines.length) return ""
    var item = lines[index]
    return item && item.text ? item.text : ""
  }
  readonly property string next: {
    if (!lines || !Array.isArray(lines) || index + 1 < 0 || index + 1 >= lines.length) return ""
    var item = lines[index + 1]
    return item && item.text ? item.text : ""
  }
  readonly property string previous: {
    if (!lines || !Array.isArray(lines) || index <= 0 || index - 1 >= lines.length) return ""
    var item = lines[index - 1]
    return item && item.text ? item.text : ""
  }
  readonly property real lineStart: {
    if (!lines || !Array.isArray(lines) || index < 0 || index >= lines.length) return 0
    var item = lines[index]
    return item && item.t !== undefined ? item.t : 0
  }
  readonly property real lineEnd: {
    if (!lines || !Array.isArray(lines) || index + 1 < 0 || index + 1 >= lines.length) return length
    var item = lines[index + 1]
    return item && item.t !== undefined ? item.t : length
  }

  // Word-by-word timing properties
  readonly property bool wordTimed: {
    if (!lines || !Array.isArray(lines) || index < 0 || index >= lines.length) return false
    var item = lines[index]
    return !!(item && item.s)
  }
  property int wordChars: 0
  property real _wordPos: 0

  property var _mem: ({})
  property string _pendingKey: ""

  Component.onCompleted: {
    applyTrackOffset()
    if (title && title.trim() !== "") {
      fetch()
    }
  }

  onTrackKeyChanged: {
    clearLyrics()
    applyTrackOffset()
    fetchTimer.restart()
  }

  Timer {
    id: fetchTimer
    interval: 350
    onTriggered: root.fetch()
  }

  // Smooth position tracking timer (30ms polling for responsive syllable highlights)
  Timer {
    id: syncTimer
    interval: 30
    repeat: true
    running: root.isPlaying && root.lines && root.lines.length > 0

    onTriggered: {
      if (!root.player) return
      root.updateIndex()
    }
  }

  Connections {
    target: root.player
    ignoreUnknownSignals: true
    function onPlaybackStateChanged() {
      if (root.player) {
        root.updateIndex()
      }
    }
    function onPostTrackChanged() {
      root.index = -1
    }
  }

  function updateIndex() {
    if (!player || !lines || lines.length === 0) return
    position = (player.position || 0) + offsetSec
    var i = index
    if (i < 0 || i >= lines.length || lines[i].t > position) i = -1
    while (i + 1 < lines.length && lines[i + 1].t <= position) {
      i++
    }
    var lineChanged = (i !== index)
    var chars = 0
    if (i >= 0 && lines[i]) {
      chars = lines[i].s ? sungChars(lines[i]) : 0
    }
    if (!lineChanged && chars < wordChars && position > _wordPos - 1) {
      chars = wordChars
    }
    _wordPos = position
    if (lineChanged) {
      wordChars = chars
      index = i
    } else if (chars !== wordChars) {
      wordChars = chars
    }
  }

  function sungChars(l) {
    var ws = l.ws || l.w
    if (!ws || !l.s) return 0
    var n = 0
    // 20ms lead time (within 1 frame at 60fps) so words appear right on sound start without rushing ahead
    var leadPos = position + 0.02
    while (n < ws.length && ws[n] <= leadPos) {
      n++
    }
    if (n === 0) return 0
    var sung = l.s.slice(0, n + 1).join("").replace(/\s+/g, " ").trim().length
    var space = l.text.indexOf(" ", sung)
    return (sung === 0 || sung >= l.text.length || l.text[sung] === " ")
      ? sung
      : (space < 0 ? l.text.length : space)
  }

  // ---- Angel OS Matching & Cleaning Engine ----

  readonly property var versionWords: /\b(?:remix|rmx|live|acoustic|sped\s*up|speed\s*up|slowed|nightcore|reverb|instrumental|karaoke|cover|edit|mashup|8d)\b|ремикс|кавер|минус/i
  readonly property var tempoWords: /sped\s*up|speed\s*up|slowed|nightcore|daycore|ускор|замедл/i
  readonly property bool tempoVersion: tempoWords.test(String(title))

  function translit(x) {
    var map = {"а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "e", "ж": "zh", "з": "z", "и": "i", "й": "y", "к": "k", "л": "l", "м": "m", "н": "n", "о": "o", "п": "p", "р": "r", "с": "s", "т": "t", "у": "u", "ф": "f", "х": "h", "ц": "ts", "ч": "ch", "ш": "sh", "щ": "sch", "ъ": "", "ы": "y", "ь": "", "э": "e", "ю": "yu", "я": "ya", "і": "i", "ї": "yi", "є": "ye", "ґ": "g"}
    return String(x || "").replace(/[а-яёіїєґ]/g, function(ch) { return map[ch] !== undefined ? map[ch] : ch })
  }

  function key(x) {
    var s = translit(String(x || "").toLowerCase().normalize("NFKD").replace(/[̀-ͯ]/g, "").replace(/ё/g, "е"))
    s = s.replace(/&/g, "and").replace(/[^a-z0-9À-ɏͰ-ϿЀ-ӿ぀-ヿ㐀-鿿가-힯]+/g, "")
    return s.replace(/ph/g, "f").replace(/ks/g, "x").replace(/[jy]/g, "i").replace(/w/g, "v").replace(/kh/g, "h").replace(/(.)\1+/g, "$1")
  }

  function titleKey(x) {
    return key(String(x || "").replace(/\s*[\(\[][^\)\]]*[\)\]]/g, " ").replace(/\s+[-–—]\s+.*$/, "").replace(/\s+(?:feat|ft)\.?\s.*$/i, "")) || key(x)
  }

  function ratio(a, b) {
    if (!a || !b) return 0
    if (a === b) return 1
    var m = a.length, n = b.length
    if (Math.abs(m - n) > Math.max(m, n) * 0.5) return 0
    var prev = []
    for (var j = 0; j <= n; j++) prev[j] = j
    for (var i = 1; i <= m; i++) {
      var cur = [i]
      for (var k = 1; k <= n; k++) {
        cur[k] = Math.min(prev[k] + 1, cur[k - 1] + 1, prev[k - 1] + (a[i - 1] === b[k - 1] ? 0 : 1))
      }
      prev = cur
    }
    return 1 - prev[n] / Math.max(m, n)
  }

  function sameName(x, y, need) {
    var a = titleKey(x), b = titleKey(y)
    if (!a || !b) return false
    if (ratio(a, b) >= need) return true
    var short = a.length < b.length ? a : b, long = a.length < b.length ? b : a
    return short.length >= 6 && long.indexOf(short) !== -1 && (short.length / long.length >= 0.8)
  }

  function artistsOf(x) {
    return String(x || "").split(/\s*(?:,|;|&|\/|\bx\b|×|\+|\bfeat\.?|\bft\.?|\bfeaturing\b|\band\b|\bи\b)\s*/i).map(key).filter(function(k) { return k.length > 0 })
  }

  function sameArtist(x, y) {
    var a = artistsOf(x), b = artistsOf(y)
    var whole = key(x), whole2 = key(y)
    if (whole && whole2 && (ratio(whole, whole2) >= 0.75 || whole.indexOf(whole2) !== -1 || whole2.indexOf(whole) !== -1)) {
      return true
    }
    return a.some(function(p) {
      return b.some(function(q) {
        return ratio(p, q) >= 0.75 || (Math.min(p.length, q.length) >= 4 && (p.indexOf(q) !== -1 || q.indexOf(p) !== -1))
      })
    })
  }

  function matches(cand, c, d) {
    if (!cand || !sameName(cand.title, c.title, 0.8)) return false
    var dur = Number(cand.duration) || 0
    var timed = d > 0 && dur > 0
    var wantVersion = versionWords.test(String(c.title) + " " + String(title))
    var candVersion = versionWords.test(String(cand.title))
    var stretch = tempoVersion && !candVersion && timed && (d / dur > 0.6) && (d / dur < 1.5)
    if (timed && Math.abs(dur - d) > 8 && !stretch) return false
    var close = timed && Math.abs(dur - d) <= 3
    if (c.artist && cand.artist && !sameArtist(cand.artist, c.artist) && !(close && key(cand.title) === key(c.title))) {
      return false
    }
    if (wantVersion !== candVersion && !close && !stretch) return false
    return true
  }

  // Clean title & artist from typical noise, video tags, covers, remasters
  function clean(t, a) {
    t = String(t || "")
    a = String(a || "")
    var noise = /\s*[\(\[【〔]\s*(?:official\s*)?(?:hd\s*|hq\s*|4k\s*)?(?:music\s*|lyrics?\s*|lyric\s*|audio\s*)?(?:video|audio|lyrics?(?:\s*video)?|visuali[sz]er|mv|m\/v|hd|hq|4k|8k|60\s?fps|live|clip|official|текст(?:\s*песни)?|караоке|karaoke|with\s+lyrics|letra|legendado|перевод|eng\s*sub|bass\s*boosted|explicit|clean|(?:19|20)\d\d|prod(?:\.|uced)?(?:\s*by)?\s[^\)\]】]*)\s*[\)\]】〕]/gi
    t = t.replace(noise, "").replace(noise, "")
    t = t.replace(/\s*#\S+/g, "").replace(/[\uD83C-\uDBFF][\uDC00-\uDFFF]|[☀-➿️]/g, "")
    t = t.replace(/\s*[|｜•].*$/, "").replace(/\s+(?:4k|hd|hq|mv|m\/v|official\s+video)\s*$/i, "").replace(/\s{2,}/g, " ").trim()
    a = a.replace(/\s*-\s*Topic$/i, "").replace(/VEVO$/i, "").replace(/\s+(?:official|music|records|tv)$/i, "").trim()

    var q = t.match(/^(.+?)\s*[「『«“"]\s*(.+?)\s*[」』»”"]\s*$/)
    if (q && (!a || fromBrowser)) {
      a = q[1].replace(/\s*[-–—:]\s*$/, "").trim()
      t = q[2].trim()
    }

    var m = t.match(/^(.+?)\s+[-–—]\s+(.+)$/) || (fromBrowser ? t.match(/^(.+?)\s*[–—]\s*(.+)$/) : null)
    if (m) {
      var left = m[1].trim(), right = m[2].trim()
      if (/\b(?:remaster(?:ed)?|remix|version|edit|mix|live|mono|stereo|acoustic|instrumental|sped up|slowed|nightcore)\b/i.test(right) && a && !fromBrowser) {
        t = left
      } else if (!a || fromBrowser || left.toLowerCase().indexOf(a.toLowerCase()) !== -1 || a.toLowerCase().indexOf(left.toLowerCase()) !== -1) {
        a = left
        t = right
      }
    }
    t = t.replace(/\s*[\(\[](?:feat|ft|featuring|при уч\.?)\.?\s[^\)\]]*[\)\]]/gi, "").replace(/\s+(?:feat|ft|featuring)\.?\s.*$/i, "").trim()
    var parts = a.split(/\s*(?:,|;|&|\/|\sx\s|×|\sfeat\.?\s|\sft\.?\s)\s*/i).filter(function(x) { return x })
    var firstArtist = parts.length ? parts[0].trim() : a
    return { title: t || String(title || ""), artist: a, firstArtist: firstArtist }
  }

  readonly property var fallbackQuery: {
    var c = clean(title, artist)
    var t = String(c.title).replace(/\s*[\(\[][^\)\]]*[\)\]]/g, "").replace(/\s+[-–—]\s+.*$/, "").trim() || c.title
    var a = c.firstArtist || c.artist
    return (t === c.title && a === c.artist) ? null : { title: t, artist: a, firstArtist: a }
  }

  // YRC to enhanced LRC with syllable timestamps
  function yrcToLrc(yrc) {
    var stamp = function(ms) {
      var t = Math.max(0, ms) / 1000
      var m = Math.floor(t / 60)
      var s = t - m * 60
      return (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s.toFixed(2)
    }
    var out = []
    var rawLines = String(yrc || "").split(/\r?\n/)
    for (var i = 0; i < rawLines.length; i++) {
      var raw = rawLines[i]
      var m = raw.match(/^\[(\d+),\d+\](.*)$/)
      if (!m) continue
      var words = m[2].replace(/\((\d+),\d+,\d+\)/g, function(x, t) {
        return "<" + stamp(parseInt(t)) + ">"
      })
      out.push("[" + stamp(parseInt(m[1])) + "]" + words)
    }
    return stripCredits(out.join("\n"))
  }

  function stripCredits(lrc) {
    return String(lrc || "").split(/\r?\n/).filter(function(l) {
      if (/^\s*\[\d+:\d+(?:[.:]\d+)?\]\s*[^\[\]]{1,24}\s?[:：]\s?/.test(l) &&
          /作|曲|词|编|制作|混音|录音|Producer|Lyricist|Composer|Written|Composed|Arranged|Lyrics by|Music by/i.test(l)) {
        return false
      }
      if (/^\s*\[00:(?:0\d|1[0-5])[.:]\d+\]\s*(?:.{1,80}\s[-–]\s.{1,80}|(?:written|composed|produced|arranged|lyrics|music)\s+by\s*[:：].*|词\s*[:：].*|曲\s*[:：].*)$/i.test(l)) {
        return false
      }
      return true
    }).join("\n")
  }

  function goodLrc(lrc) {
    return /\[\d+:\d+/.test(lrc || "") && parseLrc(stripCredits(lrc)).filter(function(l) { return l.text }).length >= 3
  }

  function utf8(bin) {
    bin = String(bin || "").replace(/^\ufeff/, "")
    var valid = true
    for (var k = 0; k < bin.length && valid; k++) {
      var c = bin.charCodeAt(k)
      if (c > 0xff) valid = false
      else if (c >= 0x80) {
        var n = c >= 0xf0 ? 3 : c >= 0xe0 ? 2 : c >= 0xc0 ? 1 : -1
        if (n < 0) valid = false
        for (var j = 1; valid && j <= n; j++) {
          var cc = bin.charCodeAt(k + j)
          if (!(cc >= 0x80 && cc < 0xc0)) valid = false
        }
        k += Math.max(0, n)
      }
    }
    if (!valid) return bin
    var out = "", i = 0
    if (bin.charCodeAt(0) === 0xef && bin.charCodeAt(1) === 0xbb && bin.charCodeAt(2) === 0xbf) i = 3
    while (i < bin.length) {
      var c1 = bin.charCodeAt(i++)
      if (c1 < 0x80) out += String.fromCharCode(c1)
      else if (c1 >= 0xc0 && c1 < 0xe0) out += String.fromCharCode(((c1 & 0x1f) << 6) | (bin.charCodeAt(i++) & 0x3f))
      else if (c1 >= 0xe0 && c1 < 0xf0) {
        var c2 = bin.charCodeAt(i++), c3 = bin.charCodeAt(i++)
        out += String.fromCharCode(((c1 & 0x0f) << 12) | ((c2 & 0x3f) << 6) | (c3 & 0x3f))
      } else if (c1 >= 0xf0) {
        var c2_ = bin.charCodeAt(i++), c3_ = bin.charCodeAt(i++), c4 = bin.charCodeAt(i++)
        var cp = ((c1 & 0x07) << 18) | ((c2_ & 0x3f) << 12) | ((c3_ & 0x3f) << 6) | (c4 & 0x3f)
        out += String.fromCodePoint(cp)
      }
    }
    return out
  }

  function entities(t) {
    return String(t || "").replace(/&#(\d+);/g, function(m, n) { return String.fromCodePoint(parseInt(n)) })
      .replace(/&apos;/g, "'").replace(/&quot;/g, '"').replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&")
  }

  // Angel OS estimateWords: vowel counting + punctuation grouping + max 0.30s per syllable
  function estimateWords(ls, total) {
    var vowels = /[аеёиоуыэюяaeiouyäöüéèàáíóú]/gi
    var cjk = /[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff\uff66-\uff9f]/
    for (var i = 0; i < ls.length; i++) {
      var l = ls[i]
      if (l.w || !l.text) continue
      // Attach lone marks or dashes to the word before it
      var words = l.text.split(" ").reduce(function(a, x) {
        if (a.length && !/[0-9A-Za-z\u00c0-\u024f\u0400-\u04ff\u3040-\u30ff\u4e00-\u9fff\uac00-\ud7af]/.test(x)) {
          a[a.length - 1] += " " + x
        } else if (x.length > 0) {
          a.push(x)
        }
        return a
      }, [])
      // For unspaced CJK, split into small 2-3 char chunks
      if (words.length < 2 && cjk.test(l.text) && l.text.length >= 2) {
        words = []
        var chunkSize = l.text.length <= 6 ? 2 : (l.text.length <= 12 ? 3 : 4)
        for (var ci = 0; ci < l.text.length; ci += chunkSize) {
          words.push(l.text.slice(ci, ci + chunkSize))
        }
      }
      if (words.length < 2) continue
      var end = (i + 1 < ls.length && ls[i + 1].t > l.t) ? ls[i + 1].t : (total > l.t ? total : l.t + 4)
      var syl = words.map(function(x) { return Math.max(1, (x.match(vowels) || []).length) })
      var sum = syl.reduce(function(a, b) { return a + b }, 0)
      var span = Math.min((end - l.t) * 0.85, sum * 0.30)
      var ws = [], s = [""]
      var acc = 0
      for (var k = 0; k < words.length; k++) {
        ws.push(l.t + (span * acc / sum))
        s.push((k && !cjk.test(l.text) ? " " : "") + words[k])
        acc += syl[k]
      }
      ls[i] = Object.assign({}, l, { ws: ws, s: s })
    }
    return ls
  }

  function parseLrc(text) {
    var out = []
    var rawLines = String(text || "").split("\n")
    var re = /^\s*\[(\d+):(\d+(?:[.:]\d+)?)\]/
    for (var i = 0; i < rawLines.length; i++) {
      var raw = rawLines[i]
      var stamps = []
      var rest = raw
      var m
      while ((m = rest.match(re))) {
        stamps.push(parseInt(m[1]) * 60 + parseFloat(m[2].replace(":", ".")))
        rest = rest.slice(m[0].length)
      }
      var w = []
      var parts = rest.split(/<(\d+):(\d+(?:[.:]\d+)?)>/)
      var s = [parts[0]]
      for (var k = 1; k + 2 < parts.length; k += 3) {
        w.push(parseInt(parts[k]) * 60 + parseFloat(parts[k + 1].replace(":", ".")))
        s.push(parts[k + 2] || "")
      }
      var cleanLine = s.join("").replace(/\s+/g, " ").trim()
      if (cleanLine.length > 0) {
        for (var si = 0; si < stamps.length; si++) {
          if (w.length > 0 && stamps.length === 1) {
            out.push({ t: stamps[si], text: cleanLine, w: w, s: s })
          } else {
            out.push({ t: stamps[si], text: cleanLine })
          }
        }
      }
    }
    out.sort(function(a, b) { return a.t - b.t })
    return out
  }

  function apply(data) {
    source = data && data.source ? data.source : ""
    plainText = data && data.plainLyrics ? String(data.plainLyrics) : ""
    if (!data) {
      lines = []
      status = "notfound"
    } else if (data.instrumental) {
      lines = []
      status = "instrumental"
    } else if (data.syncedLyrics) {
      var k = (data.scale > 0.5 && data.scale < 2) ? data.scale : 1
      var rawParsed = parseLrc(data.syncedLyrics)
      var scaled = rawParsed.map(function(l) {
        if (k === 1) return l
        var updated = Object.assign({}, l, { t: l.t * k })
        if (l.w) updated.w = l.w.map(function(x) { return x * k })
        return updated
      })
      lines = estimateWords(scaled, length)
      status = lines.length > 0 ? "ok" : "notfound"
      wordsUpgrade(trackKey, data)
    } else if (data.plainLyrics) {
      var firstLine = (plainText.split("\n").find(function(l) { return l.trim() !== "" }) || "").trim()
      lines = [{ t: 0, text: firstLine }]
      status = "plain"
    } else {
      lines = []
      status = "notfound"
    }
    index = -1
    wordChars = 0
    if (player) updateIndex()
  }

  // Background syllable upgrade from NetEase YRC (Angel OS core innovation)
  function wordsUpgrade(key, data) {
    if (!data || !data.syncedLyrics || data.wordsTried || /<\d+:\d+/.test(data.syncedLyrics)) {
      return
    }
    var c = clean(title, artist)
    var d = length
    var markTried = function() {
      if (_mem[key] === data) {
        storeCache(key, Object.assign({}, data, { wordsTried: true }))
      }
    }

    var queryUrl = "https://music.163.com/api/cloudsearch/pc?s=" + encodeURIComponent((c.title + " " + c.artist).trim()) + "&type=1&limit=8"
    http(queryUrl, function(code, body) {
      var songs = body && body.result && body.result.songs ? body.result.songs : []
      var match = songs.find(function(x) {
        return matches({
          title: x.name,
          artist: (x.ar || []).map(function(a) { return a.name }).join(", "),
          duration: (x.dt || 0) / 1000
        }, c, d)
      })
      if (!match) return markTried()

      http("https://music.163.com/api/song/lyric/v1?id=" + match.id + "&lv=1&yv=1", function(code2, lyr) {
        var lrc = lyr && lyr.yrc && lyr.yrc.lyric ? yrcToLrc(lyr.yrc.lyric) : ""
        if (goodLrc(lrc)) {
          var up = {
            source: "NetEase (YRC)",
            syncedLyrics: lrc,
            trackName: match.name,
            duration: (match.dt || 0) / 1000,
            wordsTried: true
          }
          if (tempoVersion && up.duration > 0 && d > 0 && Math.abs(up.duration - d) > 3) {
            up.scale = d / up.duration
          }
          storeCache(key, up)
          if (key === trackKey) {
            apply(up)
          }
          return
        }

        // If no YRC, check if NetEase standard LRC has higher line resolution than current data
        http("https://music.163.com/api/song/lyric?id=" + match.id + "&lv=1", function(code3, lyr3) {
          var stdLrc = lyr3 && lyr3.lrc && lyr3.lrc.lyric ? stripCredits(lyr3.lrc.lyric) : ""
          var curLines = (data.syncedLyrics.match(/\[\d+:\d+/g) || []).length
          var newLines = (stdLrc.match(/\[\d+:\d+/g) || []).length
          if (goodLrc(stdLrc) && newLines > curLines + 10) {
            var upStd = {
              source: "NetEase (LRC)",
              syncedLyrics: stdLrc,
              trackName: match.name,
              duration: (match.dt || 0) / 1000,
              wordsTried: true
            }
            if (tempoVersion && upStd.duration > 0 && d > 0 && Math.abs(upStd.duration - d) > 3) {
              upStd.scale = d / upStd.duration
            }
            storeCache(key, upStd)
            if (key === trackKey) {
              apply(upStd)
            }
            return
          }
          markTried()
        })
      })
    })
  }

  function cacheFileName(key) {
    var h = 0
    for (var i = 0; i < key.length; i++) {
      h = (h * 31 + key.charCodeAt(i)) | 0
    }
    var safe = key.replace(/[\/\\:*?"<>|\s\u0001.]+/g, "_").slice(0, 40)
    return cacheDir + "/" + safe + "_" + (h >>> 0).toString(16) + ".json"
  }

  function storeCache(key, data) {
    _mem[key] = data
    var file = cacheFileName(key)
    saveProcess.running = false
    saveProcess.command = [
      "python3", "-c",
      "import sys, pathlib; p=pathlib.Path(sys.argv[1]); p.parent.mkdir(parents=True, exist_ok=True); p.write_text(sys.argv[2], encoding='utf-8')",
      file, JSON.stringify(data)
    ]
    saveProcess.running = true
  }

  Process {
    id: saveProcess
  }

  function fetch() {
    plainText = ""
    lines = []
    index = -1
    wordChars = 0
    if (!title || title.trim() === "") {
      status = "idle"
      return
    }
    var key = trackKey
    _pendingKey = key
    if (_mem[key] !== undefined) {
      apply(_mem[key])
      return
    }
    status = "loading"
    diskReader.key = key
    diskReader.path = cacheFileName(key)
    diskReader.reload()
  }

  FileView {
    id: diskReader
    property string key: ""
    printErrors: false
    onLoaded: {
      if (!root || key !== root._pendingKey) return
      try {
        var data = JSON.parse(text())
        if (data && (data.syncedLyrics || data.plainLyrics)) {
          root._mem[key] = data
          root.apply(data)
          return
        }
      } catch (e) {}
      if (root) root.fetchNet(key)
    }
    onLoadFailed: {
      if (root && key === root._pendingKey) {
        root.fetchNet(key)
      }
    }
  }

  function http(url, cb) {
    var xhr = new XMLHttpRequest()
    xhr.onreadystatechange = function() {
      if (xhr.readyState !== XMLHttpRequest.DONE) return
      var body = null
      try {
        body = xhr.status === 200 ? JSON.parse(xhr.responseText) : null
      } catch (e) {}
      cb(xhr.status, body)
    }
    xhr.open("GET", url)
    xhr.setRequestHeader("User-Agent", "Mozilla/5.0 (X11; Linux x86_64) omarchy-lyrics/1.0")
    xhr.send()
  }

  // Multi-engine search pipeline (LRCLIB -> NetEase -> LRC.CX -> Kugou -> QQ -> Fallback)
  function fetchNet(key) {
    var c = clean(title, artist)
    var d = length
    var plainFallback = null

    var finish = function(data) {
      if (key !== root._pendingKey) return
      if (data && data.syncedLyrics && root.tempoVersion && data.duration > 0 && d > 0 && Math.abs(data.duration - d) > 3) {
        data = Object.assign({}, data, { scale: d / data.duration })
      }
      if (data) {
        root.storeCache(key, data)
        root.apply(data)
      } else if (plainFallback) {
        root.storeCache(key, plainFallback)
        root.apply(plainFallback)
      } else {
        root._mem[key] = null
        root.apply(null)
      }
    }

    var keepPlain = function(data) {
      if (!plainFallback && data && data.plainLyrics && String(data.plainLyrics).trim()) {
        plainFallback = data
      }
    }

    // Pipeline steps
    var tryStep1_LrclibGet = function(queryItem, onNext) {
      var dur = d > 0 ? Math.round(d) : 0
      var url = "https://lrclib.net/api/get?track_name=" + encodeURIComponent(queryItem.title)
        + "&artist_name=" + encodeURIComponent(queryItem.artist)
        + (dur > 0 ? "&duration=" + dur : "")
      http(url, function(code, res) {
        if (key !== root._pendingKey) return
        var ok = res && matches({ title: res.trackName, artist: res.artistName, duration: res.duration }, queryItem, d)
        if (ok && (res.syncedLyrics || res.instrumental)) {
          res.source = "lrclib"
          return finish(res)
        }
        if (ok) keepPlain(Object.assign({ source: "lrclib" }, res))
        onNext()
      })
    }

    var tryStep2_LrclibSearch = function(queryItem, onNext) {
      var url = "https://lrclib.net/api/search?track_name=" + encodeURIComponent(queryItem.title)
        + "&artist_name=" + encodeURIComponent(queryItem.artist)
      http(url, function(code, list) {
        if (key !== root._pendingKey) return
        if (Array.isArray(list)) {
          var okList = list.filter(function(r) {
            return matches({ title: r.trackName || r.name, artist: r.artistName, duration: r.duration }, queryItem, d)
          })
          var synced = okList.filter(function(r) { return r.syncedLyrics }).sort(function(x, y) {
            var durDiff = Math.abs((x.duration || 0) - d) - Math.abs((y.duration || 0) - d)
            if (Math.abs(durDiff) > 1.5) return durDiff
            var scoreX = (ratio(x.artistName, queryItem.artist) * 100) + ((x.syncedLyrics.match(/\[\d+:\d+/g) || []).length)
            var scoreY = (ratio(y.artistName, queryItem.artist) * 100) + ((y.syncedLyrics.match(/\[\d+:\d+/g) || []).length)
            return scoreY - scoreX
          })
          if (synced.length > 0) {
            var item = synced[0]
            item.source = "lrclib"
            return finish(item)
          }
          var plain = okList.find(function(r) { return r.plainLyrics })
          if (plain) keepPlain(Object.assign({ source: "lrclib" }, plain))
        }
        onNext()
      })
    }

    var tryStep3_NetEase = function(queryItem, onNext) {
      var q = (queryItem.title + " " + queryItem.artist).trim()
      var url = "https://music.163.com/api/cloudsearch/pc?s=" + encodeURIComponent(q) + "&type=1&limit=10"
      http(url, function(code, body) {
        if (key !== root._pendingKey) return
        var songs = body && body.result && body.result.songs ? body.result.songs : []
        var match = songs.find(function(x) {
          return matches({
            title: x.name,
            artist: (x.ar || []).map(function(a) { return a.name }).join(", "),
            duration: (x.dt || 0) / 1000
          }, queryItem, d)
        })
        if (!match) return onNext()

        // Try YRC syllable lyrics first
        http("https://music.163.com/api/song/lyric/v1?id=" + match.id + "&lv=1&yv=1", function(c1, lyr1) {
          if (key !== root._pendingKey) return
          var yrcLrc = lyr1 && lyr1.yrc && lyr1.yrc.lyric ? yrcToLrc(lyr1.yrc.lyric) : ""
          if (goodLrc(yrcLrc)) {
            return finish({
              source: "NetEase (YRC)",
              syncedLyrics: yrcLrc,
              trackName: match.name,
              duration: (match.dt || 0) / 1000
            })
          }
          // Try standard line LRC
          http("https://music.163.com/api/song/lyric?id=" + match.id + "&lv=1", function(c2, lyr2) {
            if (key !== root._pendingKey) return
            var stdLrc = lyr2 && lyr2.lrc && lyr2.lrc.lyric ? stripCredits(lyr2.lrc.lyric) : ""
            if (goodLrc(stdLrc)) {
              return finish({
                source: "NetEase",
                syncedLyrics: stdLrc,
                trackName: match.name,
                duration: (match.dt || 0) / 1000
              })
            }
            onNext()
          })
        })
      })
    }

    var tryStep4_LrcCx = function(queryItem, onNext) {
      var url = "https://api.lrc.cx/jsonapi?title=" + encodeURIComponent(queryItem.title)
        + "&artist=" + encodeURIComponent(queryItem.artist)
      http(url, function(code, list) {
        if (key !== root._pendingKey) return
        if (Array.isArray(list)) {
          var match = list.find(function(r) {
            return goodLrc(r.lrc) && matches({ title: r.title, artist: r.artist || "?", duration: r.duration || 0 }, queryItem, d)
          })
          if (match) {
            var cleanLrc = stripCredits(match.lrc)
            return finish({
              source: "lrc.cx",
              syncedLyrics: cleanLrc,
              trackName: match.title,
              duration: match.duration || 0
            })
          }
        }
        onNext()
      })
    }

    var tryStep5_Kugou = function(queryItem, onNext) {
      var q = (queryItem.artist + " " + queryItem.title).trim()
      var url = "http://mobilecdn.kugou.com/api/v3/search/song?format=json&keyword=" + encodeURIComponent(q) + "&page=1&pagesize=10"
      http(url, function(code, body) {
        if (key !== root._pendingKey) return
        var list = body && body.data && body.data.info ? body.data.info : []
        var match = list.find(function(x) {
          return matches({ title: x.songname, artist: x.singername, duration: x.duration }, queryItem, d)
        })
        if (!match || !match.hash) return onNext()

        var krcUrl = "https://krcs.kugou.com/search?ver=1&man=yes&client=mobi&keyword=&duration="
          + (d > 0 ? Math.round(d * 1000) : (match.duration || 0) * 1000)
          + "&hash=" + match.hash
        http(krcUrl, function(code2, dlInfo) {
          if (key !== root._pendingKey) return
          var cand = dlInfo && dlInfo.candidates && dlInfo.candidates[0]
          if (!cand) return onNext()

          var dlUrl = "https://lyrics.kugou.com/download?ver=1&client=pc&id=" + cand.id
            + "&accesskey=" + cand.accesskey + "&fmt=lrc&charset=utf8"
          http(dlUrl, function(code3, dlRes) {
            if (key !== root._pendingKey) return
            var lrc = dlRes && dlRes.content ? utf8(Qt.atob(dlRes.content)) : null
            if (goodLrc(lrc)) {
              return finish({
                source: "Kugou",
                syncedLyrics: stripCredits(lrc),
                trackName: match.songname,
                duration: match.duration || 0
              })
            }
            onNext()
          })
        })
      })
    }

    // Execute chain for cleaned query
    tryStep1_LrclibGet(c, function() {
      tryStep2_LrclibSearch(c, function() {
        tryStep3_NetEase(c, function() {
          tryStep4_LrcCx(c, function() {
            tryStep5_Kugou(c, function() {
              // If not found, try fallback round with stripped title and primary artist
              var fb = root.fallbackQuery
              if (fb) {
                tryStep1_LrclibGet(fb, function() {
                  tryStep3_NetEase(fb, function() {
                    tryStep4_LrcCx(fb, function() {
                      finish(null)
                    })
                  })
                })
              } else {
                finish(null)
              }
            })
          })
        })
      })
    })
  }

  function togglePlaying() {
    if (player && typeof player.togglePlaying === "function") player.togglePlaying()
  }

  function next() {
    if (player && typeof player.next === "function") player.next()
  }

  function previous() {
    if (player && typeof player.previous === "function") player.previous()
  }

  function seek(targetSeconds) {
    if (player) {
      player.position = Math.max(0, targetSeconds)
      player.positionChanged()
      updateIndex()
    }
  }
}
