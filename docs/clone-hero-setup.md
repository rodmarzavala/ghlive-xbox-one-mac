# Setting up Clone Hero with GHLive

GHLive turns the Guitar Hero Live guitar into key presses, so Clone Hero sees it as a keyboard. This guide binds those keys once and gets you playing.

The control names in step 2 come from Clone Hero's controls screen as seen on a real setup. Other menu names in this guide describe what to look for and can differ between game versions.

## 1. Start GHLive first

Open GHLive, plug in the dongle and turn on the guitar. Wait until GHLive's menu shows **Guitar connected**. Leave GHLive running while you play.

Want to be sure every button works first? Open **Input Monitor... → Test my guitar** ([details](../README.md#check-that-your-guitar-works)).

## 2. Bind the guitar in Clone Hero's controls

Clone Hero's controls screen lists **Actions** with columns for **Keyboard**, **Mouse** and **Controller**. Its fret rows carry two names, one for a 5-fret guitar and one for a 6-fret (GHL) guitar:

| Clone Hero row | Press on the guitar | Key GHLive sends (6-fret preset) |
|---|---|---|
| Green \| Black 1 | Black 1 | `1` |
| Red \| Black 2 | Black 2 | `2` |
| Yellow \| Black 3 | Black 3 | `3` |
| Blue \| White 1 | White 1 | `Q` |
| Orange \| White 2 | White 2 | `W` |
| 2X Kick \| White 3 | White 3 | `E` |
| Strum Up / Strum Down | Strum up / down | Up / Down arrow |
| Start Button | Pause | Esc |
| Select Button \| Star Power | Hero Power | Space |
| Whammy (if listed; the name may differ) | Whammy bar | `X` |

You don't need to type the keys: click a cell in the **Keyboard** column, then press that control **on the guitar**, and GHLive sends the key for you.

The Yellow, Blue and Green Cymbal rows are for drums and can stay empty. Clone Hero's own defaults in that column (`A`, `S`, `J`, `K`, `L`, Return, `H`) get replaced as you bind.

## 3. Add songs

Clone Hero ships without songs; the community makes them ("custom charts").

- Each song is either **a folder** (a chart such as `notes.chart` or `notes.mid`, audio such as `song.ogg`/`.opus`, usually a `song.ini`), or **a single `.sng` file**. Never leave songs inside a `.zip`: unzip them so the files sit directly in the song's folder.
- Put them in one folder, for example `~/Documents/Clone Hero Songs`, add it in Clone Hero's song folder settings, and **scan songs**. Scan again whenever you add songs.

## 4. 6-fret charts vs. 5-fret charts

Your guitar's notes are **black and white**. They only appear on screen in songs that include a **6-fret (GHL) chart**, and only when you pick the 6-fret guitar instrument for that song. Most community charts are made for the classic 5-button guitar and show **colored** notes instead.

- **6-fret charts:** pick the 6-fret (GHL) guitar instrument when choosing the song. If a song should have one but the instrument isn't offered, rescan. The chart itself must contain a 6-fret part (an `[ExpertGHLGuitar]` section in `notes.chart`, or a `PART GUITAR GHL` track in `notes.mid`).
- **5-fret charts:** they play with the same bindings. The rows above pair Green/Red/Yellow with Black 1/2/3, and Blue/Orange with White 1/2. Prefer another layout? GHLive's **5-fret (classic charts)** preset is an alternative ([details](../README.md#playing-classic-5-fret-charts)). Choose it in GHLive's Settings, then re-bind Clone Hero's five colored rows with the preset's keys: for **Green**, **Red**, **Yellow**, **Blue** and **Orange**, press White 1, White 2, White 3, Black 2 and Black 3 on the guitar (keys `1` to `5`). Ignore the Black/White name on each row while this preset is active. Switch back to the 6-fret preset and re-bind before playing 6-fret charts.

## 5. Play

Pick a song, the instrument and a difficulty, and play: hold the frets and strum. **Star Power:** press Hero Power or tilt the guitar up. **Pause:** the Pause button.

Nothing happening? Check that the GHLive menu doesn't say **Paused**, and that Clone Hero is the window in front: macOS sends key presses to the active app. More in [Troubleshooting](troubleshooting.md).
