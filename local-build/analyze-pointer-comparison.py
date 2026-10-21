"""Compare host motion-event cadence in the two labelled capture phases."""

import argparse
import csv
import json
import math
import statistics
from collections import Counter
from pathlib import Path


def percentile(values, fraction):
    ordered = sorted(values)
    position = (len(ordered) - 1) * fraction
    low = math.floor(position)
    high = math.ceil(position)
    return ordered[low] + (ordered[high] - ordered[low]) * (position - low)


def analyze(path):
    metadata = json.loads(Path(str(path) + '.phases.json').read_text(encoding='utf-8-sig'))
    if not metadata['completed']:
        raise ValueError('Capture was stopped before both phases completed')
    with path.open(encoding='utf-8-sig', newline='') as stream:
        rows = [dict(ms=float(row['elapsed_ms']), device=row['device'],
                     dx=int(row['dx']), dy=int(row['dy']), flags=int(row['flags']))
                for row in csv.DictReader(stream)]
    results = []
    for phase in metadata['phases']:
        # Omit the first two seconds for the hand change and the last second
        # before the transition. Both devices get the same 17-second window.
        start = (phase['start_seconds'] + 2) * 1000
        end = (phase['end_seconds'] - 1) * 1000
        events = [row for row in rows if start <= row['ms'] < end and (row['dx'] or row['dy'])]
        counts = Counter(row['device'] for row in events)
        if not counts:
            raise ValueError(f"No movement during {phase['label']}")
        device, count = counts.most_common(1)[0]
        chosen = [row for row in events if row['device'] == device]
        if count < 100 or count / len(events) < 0.95:
            raise ValueError(f"Insufficient or mixed movement during {phase['label']}: {counts}")
        if any(row['flags'] & 1 for row in chosen):
            raise ValueError('Absolute pointer input cannot be compared as relative mouse motion')
        times = [row['ms'] for row in chosen]
        gaps = [after - before for before, after in zip(times, times[1:])]
        longest = sorted(zip(gaps, times), reverse=True)[:5]
        results.append(dict(
            label=phase['label'], device=device, duration_seconds=(end-start)/1000,
            event_count=count, events_per_second=count/((end-start)/1000),
            median_gap_ms=statistics.median(gaps), p95_gap_ms=percentile(gaps, 0.95),
            p99_gap_ms=percentile(gaps, 0.99), max_gap_ms=max(gaps),
            gaps_over_20ms=sum(gap > 20 for gap in gaps),
            gaps_over_50ms=sum(gap > 50 for gap in gaps),
            gaps_under_1ms=sum(gap < 1 for gap in gaps),
            longest_gaps=[dict(gap_ms=gap, at_seconds=at/1000) for gap, at in longest],
            other_device_events=len(events)-count,
        ))
    if results[0]['device'] == results[1]['device']:
        raise ValueError('The same device dominated both phases; two devices were not identified')
    return dict(capture=str(path), trimmed_seconds_per_phase=17, results=results,
                interpretation='Windows nonzero relative-motion arrival cadence, not USB polling or display frame timing')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('capture', type=Path)
    args = parser.parse_args()
    try:
        report = analyze(args.capture)
    except (OSError, ValueError, KeyError) as exc:
        parser.exit(1, f'Comparison unavailable: {exc}\n')
    target = args.capture.with_suffix('.comparison.json')
    target.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report, ensure_ascii=False, indent=2))
    print(f'Saved: {target}')
