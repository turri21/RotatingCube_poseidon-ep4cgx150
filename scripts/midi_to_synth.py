#!/usr/bin/env python3
"""
midi_to_synth.py

Converts a standard MIDI file (.mid) into song.hex for the audio_synth module.
Generates NOTE ON / NOTE OFF events with per-channel MIDI channel preserved.

Usage:
    python midi_to_synth.py input.mid output.hex [sample_rate]

Requirements:
    pip install mido
    OR use: pipx run --spec mido python midi_to_synth.py ...
"""

import sys
try:
    import mido
except ImportError:
    print("Error: 'mido' package required.")
    print("Install with: pip install mido")
    print("Or use venv: python3 -m venv ~/midi_env && source ~/midi_env/bin/activate && pip install mido")
    sys.exit(1)


def midi_to_rom(input_path, output_path, sample_rate=48000):
    mid = mido.MidiFile(input_path)
    ticks_per_beat = mid.ticks_per_beat

    # Merge all tracks and sort by absolute MIDI tick
    all_events = []
    for track in mid.tracks:
        abs_tick = 0
        for msg in track:
            abs_tick += msg.time
            all_events.append((abs_tick, msg))

    all_events.sort(key=lambda x: x[0])

    # Walk through events, tracking tempo changes
    tempo = 500000  # default 120 BPM
    prev_tick = 0
    rom_lines = []

    for abs_tick, msg in all_events:
        if msg.type == 'set_tempo':
            tempo = msg.tempo

        elif msg.type in ('note_on', 'note_off'):
            # Determine command
            if msg.type == 'note_on' and msg.velocity > 0:
                cmd = 0x01
            else:
                cmd = 0x00

            # Delta time from previous event, in samples
            delta_ticks = abs_tick - prev_tick
            delta_us = delta_ticks * tempo / ticks_per_beat
            delta_samples = int(delta_us * sample_rate / 1_000_000)

            if delta_samples > 0xFFFFFFFF:
                delta_samples = 0xFFFFFFFF

            word = (
                ((delta_samples & 0xFFFFFFFF) << 32)
                | ((cmd & 0xFF) << 24)
                | ((msg.note & 0xFF) << 16)
                | ((msg.velocity & 0xFF) << 8)
                | (msg.channel & 0x0F)
            )

            rom_lines.append(f"{word:016X}")
            prev_tick = abs_tick

    # Append END event (1 second silence then loop)
    end_delta = sample_rate
    end_word = ((end_delta & 0xFFFFFFFF) << 32) | (0x02 << 24)
    rom_lines.append(f"{end_word:016X}")

    with open(output_path, 'w') as f:
        for line in rom_lines:
            f.write(line + '\n')

    total_seconds = sum(int(line[:8], 16) for line in rom_lines) / sample_rate
    print(f"Wrote {len(rom_lines)} ROM entries to {output_path}")
    print(f"Approximate song length: {total_seconds:.1f} seconds")


if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Usage: python midi_to_synth.py <input.mid> <output.hex> [sample_rate]")
        sys.exit(1)

    sr = int(sys.argv[3]) if len(sys.argv) > 3 else 48000
    midi_to_rom(sys.argv[1], sys.argv[2], sr)