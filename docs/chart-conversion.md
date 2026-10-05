# 5-fret to 6-fret chart conversion

`ghlive charts add-ghl <folder>` and the menu item "Add 6-fret tracks to songs..." add a 6-fret (GHL) lead guitar track to Clone Hero songs that only have a 5-fret one. It is CPU-only and deterministic: the same input always gives the same output, and nothing is learned or guessed.

The note numbers below come from the community chart format documentation, [GuitarGame_ChartFormats](https://github.com/TheNathannator/GuitarGame_ChartFormats):

- `.chart`: [5-fret guitar](https://github.com/TheNathannator/GuitarGame_ChartFormats/blob/main/docs/Chart-File-Formats/chart-format/Tracks/5-Fret-Guitar.md), [6-fret guitar](https://github.com/TheNathannator/GuitarGame_ChartFormats/blob/main/docs/Chart-File-Formats/chart-format/Tracks/6-Fret-Guitar.md)
- `.mid`: [5-fret guitar](https://github.com/TheNathannator/GuitarGame_ChartFormats/blob/main/docs/Chart-File-Formats/mid-format/Tracks/5-Fret-Guitar.md), [6-fret guitar](https://github.com/TheNathannator/GuitarGame_ChartFormats/blob/main/docs/Chart-File-Formats/mid-format/Tracks/6-Fret-Guitar.md)

## Lane mapping

Clone Hero pairs the controls of the two guitars: Green with Black 1, Red with Black 2, Yellow with Black 3, Blue with White 1, Orange with White 2. Converting lane by lane the same way means the result plays exactly like the 5-fret chart with the same key bindings. White 3 is unused.

| 5-fret | 6-fret |
|---|---|
| Green | Black 1 |
| Red | Black 2 |
| Yellow | Black 3 |
| Blue | White 1 |
| Orange | White 2 |
| Open | Open |
| Force / flip, tap | unchanged |

## `.chart`

For each difficulty, a `[<Difficulty>Single]` section without a `[<Difficulty>GHLGuitar]` gets a new `[<Difficulty>GHLGuitar]` section appended at the end of the file. The 5-fret sections are not touched.

| Note number | 5-fret | 6-fret |
|---|---|---|
| 0 | Green | White 1 |
| 1 | Red | White 2 |
| 2 | Yellow | White 3 |
| 3 | Blue | Black 1 |
| 4 | Orange | Black 2 |
| 8 | (none) | Black 3 |
| 5 | Force / flip | Force / flip |
| 6 | Tap | Tap |
| 7 | Open | Open |

So a 5-fret `N 0` (Green) becomes `N 3` (Black 1), `N 1` becomes `N 4`, `N 2` (Yellow) becomes `N 8` (Black 3), `N 3` (Blue) becomes `N 0` (White 1) and `N 4` (Orange) becomes `N 1` (White 2). Sustain lengths are kept.

- `S` (star power) and `E` (solo and other events) lines are copied. Unknown note numbers are dropped.
- The file stays UTF-8, with its own line endings, and keeps its byte-order mark if it has one, so the edit only ever appends: the original bytes are a prefix of the new file. A file that is not valid UTF-8 is reported as failed and left alone.
- A file with two sections of the same lead-guitar name (for example two `[ExpertSingle]`) is refused as `duplicate [ExpertSingle]`: there is no safe way to know which one is meant.

## `.mid`

Only Standard MIDI Files of type 1 are handled. If there is a `PART GUITAR` track and no `PART GUITAR GHL`, a new track `PART GUITAR GHL` is appended, derived from `PART GUITAR`. The existing tracks are copied byte for byte.

Per difficulty, the 5-fret Green note and the 6-fret Open note are:

| Difficulty | 5-fret Green | 6-fret Open |
|---|---|---|
| Expert | 96 | 94 |
| Hard | 84 | 82 |
| Medium | 72 | 70 |
| Easy | 60 | 58 |

6-fret notes are the Open note plus an offset: Open 0, White 1 +1, White 2 +2, White 3 +3, Black 1 +4, Black 2 +5, Black 3 +6. The 5-fret lanes map onto them as in the table above (Green to Black 1, Red to Black 2, Yellow to Black 3, Blue to White 1, Orange to White 2).

- Force HOPO and force strum (Green + 5 and Green + 6) keep their note numbers.
- The 5-fret open note (Green - 1) is mapped to the 6-fret Open note only when `PART GUITAR` carries an `[ENHANCED_OPENS]` text event. Without it, those notes are dropped.
- The markers 103 (solo), 104 (tap) and 116 (star power) are kept.
- Star Power on GH1/2-era charts: when the track has no notes on 116, or `song.ini` has `star_power_note = 103` or `multiplier_note = 103`, the 103 markers are Star Power, not solos (see "Phrase Mechanics" in the 5-fret `.mid` page). They are written as 116 in the 6-fret track. With `star_power_note = 116` or `multiplier_note = 116`, 103 stays a solo marker whatever the track holds.
- Every other note is dropped. Rock Band hand-animation notes (12 to 59, for example) would otherwise turn into fake 6-fret notes. A dropped note's delta time moves to the next event that is kept, so the notes that stay keep their exact tick and the track keeps its length.
- Sysex, text and meta events are kept. The new track is written with an explicit status byte on every event, because dropping an event could leave a running status without its source.

## `song.ini`

For every converted song, `diff_guitarghl` is added to the `[song]` section of its `song.ini` when the key is missing, with the value of `diff_guitar` (or `0` if that is absent). Clone Hero may hide the 6-fret part of a song without it. An existing `diff_guitarghl` is never overwritten. The same fix is applied to a song that already has a 6-fret track (for example a hand-made one) when its `song.ini` lacks the key, and reported for that song; nothing else about such a song is touched. The rest of the file is kept byte for byte: line endings, a BOM, other keys and the case of the `[song]` header.

## Safety

1. The converted file is built in memory first. A song with nothing to convert is not touched and not backed up.
2. A copy of the file (and of `song.ini` when it changes) goes to `<songs folder name> - backup <yyyy-MM-dd HHmmss>` next to the songs folder, with the same relative paths. It is outside the songs folder on purpose: Clone Hero would scan duplicates.
3. The new contents are written to a hidden temporary file in the same folder, read back and verified, then swapped in atomically.
4. On any failure the original stays as it was and the song is reported as `failed`; the other songs carry on.
5. Symbolic links to charts or song folders are reported as `skipped: symbolic link` and not followed.
6. `--dry-run` runs all of the conversion and verification in memory and writes nothing, not even the backup folder.

Verification, for both formats: for each difficulty, the note counts of the new track equal the mapped note counts of the source. For `.mid` the total length in ticks of the two tracks is equal too, and the original tracks are unchanged. For `.chart` the original text is still there, unchanged.

Running it again adds nothing: songs that already have a 6-fret track are reported as skipped. `.sng` songs are skipped as "not supported yet".
