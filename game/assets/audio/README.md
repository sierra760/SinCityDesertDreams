# Game audio

Music, interface sounds and sound effects made for Sin City: Desert Dreams.
Nothing here is sampled or converted from another game. `provenance.json`
records how every file was made, with hashes.

| Folder | Contents | Made by |
| --- | --- | --- |
| `music/` | Songs, stereo Ogg Vorbis | Composed for this game as MIDI (kept in `assets/audio/music/`) and rendered through the project's own synthesized instrument bank |
| `ui/` | Clicks, chimes, placement, error and casino stingers, mono | Synthesized by `tools/build_ui_sounds.py` (which also makes the elevator and station chimes in `sfx/`) |
| `sfx/` | Disasters, vehicles, crowds and city sounds | Generated with ElevenLabs (Creator plan, commercial rights) from the prompts in `tools/audio/sfx_prompts.json`, then trimmed, normalized and encoded by `tools/generate_sfx.py`; masters are in `assets/audio/sfx/` |

Files ending in `_loop` are seamless loops; `GameAudio` turns looping on when
it loads them. `footsteps_sand_step_*` are single steps sliced from one
generated clip, and `footsteps_sand_loop` lays them out at an even stride. One-shots are trimmed and peak-normalized to about −1 dBFS; loops
are leveled to about −18 dBFS RMS; songs to about −17 dBFS RMS.

## License

All files here are project-owned assets under CC BY-NC-SA 4.0 (see
`LICENSING.md`), as are the MIDI masters in `assets/audio/music/`. The
synthesizer and build scripts are GPL-3.0-or-later code.

## Rebuilding

```
python3 tools/build_ui_sounds.py
ELEVENLABS_API_KEY=... python3 tools/generate_sfx.py NAME --force
python3 tools/generate_sfx.py --process-only  # reprocess masters, no API calls
```

The tools need numpy, ffmpeg and oggenc (`brew install vorbis-tools`).
