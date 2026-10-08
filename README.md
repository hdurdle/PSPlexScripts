# PSPlexScripts

PowerShell 7 scripts for querying Plex Media Server libraries: find duplicate files,
low-resolution copies, stereo-only films, mixed-quality TV seasons, problem subtitle and
audio tracks, and more.

Everything is read-only except `Repair-PlexDuplicateActor.ps1`, which previews by
default and only acts with `-Execute`.

## Getting started

Needs PowerShell 7 (`pwsh`).

1. Tell the scripts where your server is:

   ```powershell
   $env:PlexServer = 'plex.your.local:32400'
   ```

   Set it in your profile so it's there in every session.

2. Get a Plex token. Sign in with your Plex account (and two-factor code, if you use one):

   ```powershell
   $env:PlexToken = .\Get-PlexToken.ps1
   ```

   Keep the token in your password manager and set `$env:PlexToken` from your profile
   or a local, uncommitted script. Don't save it in this folder. It shows up as a
   "PSPlexScripts" device under Authorized Devices on plex.tv; remove that device to revoke it.

3. List your libraries to check it works:

   ```powershell
   > .\Get-PlexSections.ps1

   title        key type
   -----        --- ----
   Film         1   movie
   TV           3   show
   ```

Library names (`-Type Film`, `-Type TV`) are whatever your libraries are called on the server.

## Scripts

| Script | What it does |
|---|---|
| `Get-Plex.ps1` | General query: list a library with filters, search, now playing, history, actors, all episodes of a show. Returns the raw `MediaContainer`. |
| `Get-PlexSections.ps1` | Lists libraries. |
| `Get-PlexToken.ps1` | Signs in to plex.tv and returns a token. |
| `Get-PlexMulti.ps1` | Films and episodes with two or more files on disk. |
| `Get-Plex720.ps1` | Titles with a copy at a given resolution (720p by default). |
| `Get-PlexMixedResolution.ps1` | TV shows with a mix of 720p and 1080p episodes. |
| `Get-PlexLowChannelAudio.ps1` | Titles whose best copy is below 5.1 (or another channel count). |
| `Get-PlexDetails.ps1` | Saves full per-item metadata, including streams, to `out/` as JSON. |
| `Get-PlexStreams.ps1` | Reads that JSON and lists PGS subtitles and foreign-language audio. |
| `Get-PlexActors.ps1` | Actors in a library, filtered by name. |
| `Get-PlexGenres.ps1` | Genres in a library with title counts. |
| `Get-PlexDuplicateActor.ps1` | Actors that appear twice under the same name. |
| `Repair-PlexDuplicateActor.ps1` | Refreshes titles credited to those duplicates so Plex merges them. Dry-run unless `-Execute`. |
| `Get-PlexUnwatched.ps1` | Old, rarely watched titles, via [Tautulli](https://tautulli.com) (`$env:TautulliUrl`, `$env:TautulliApiKey`). |
| `Find-FilmList.ps1` | Searches a plain-text film list. |

Every script has help: `Get-Help .\Get-PlexMulti.ps1 -Full`.

`.PlexApi.ps1` is the shared helper the scripts dot-source. It reads the settings,
pages through large libraries and retries when the server is busy.

Output files (`Get-PlexDetails.ps1`, the repair log) go to `out/`, which git ignores.

## Examples

### Find media with duplicate files
Useful if you've collected different-quality copies over time and want to find the
ones you don't need any more.

```powershell
> .\Get-PlexMulti.ps1 Film | Format-Table Title, Resolution, Codec, SizeGB

Title      Resolution Codec SizeGB
-----      ---------- ----- ------
Boss Level 1080       h264    3.05
Boss Level 720        h264    2.12
```

A 4K copy alongside a lower-resolution one is skipped unless you add `-Include4K`.

### Find media at a specific resolution

```powershell
> $lowRes = .\Get-Plex.ps1 -Type Film -Resolution 720
> $lowRes.MediaContainer.Metadata.Count
358
> $lowRes.MediaContainer.Metadata.title
  ... lists all titles ...
```

### Recently added

```powershell
> (.\Get-Plex.ps1 -Type Film -AddedAfter 2026-01-01).MediaContainer.Metadata.title
```

### Now playing

```powershell
> $result = .\Get-Plex.ps1 -NowPlaying
> $result.MediaContainer.Metadata | Select-Object title, @{ n = 'user'; e = { $_.User.title } }
```

### Explore your TV library

```powershell
> $tv = .\Get-Plex.ps1 -Type TV
> $tv.MediaContainer.Metadata.Count
529
> $tv.MediaContainer.Metadata | Where-Object studio -eq 'NBC' | Select-Object title

title
-----
30 Rock
The A-Team
```

### Look at a film's files

```powershell
> $film = (.\Get-Plex.ps1 -Type Film -Title 'Andromeda Strain').MediaContainer.Metadata[0]
> $film.Media

videoResolution : 1080
bitrate         : 11060
audioChannels   : 2
audioCodec      : dca-ma
videoCodec      : h264
container       : mkv
Part            : {@{id=808; file=\\path\to\film\The Andromeda Strain (1971)\The.Andromeda.Strain.1971.mkv; size=10835482508; ...}}
```

Everything Plex knows about your media is in `MediaContainer` and `Metadata`.

### Subtitle and audio problems

```powershell
> .\Get-PlexDetails.ps1 -Type TV                  # slow: one request per episode
> .\Get-PlexStreams.ps1 -Check PgsSubtitles | Format-Table Title, File
```

## Notes

- Plex item metadata has keys that differ only in case (`guid`/`Guid`, `rating`/`Rating`),
  which PowerShell's JSON parser rejects. The helper renames the lowercase ones to
  `plexGuid` and `plexRating`.
- If your server allows unauthenticated access from your LAN, queries work even with
  an expired token. `Get-PlexToken.ps1` still needs your plex.tv sign-in.
