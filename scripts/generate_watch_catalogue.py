#!/usr/bin/env python3
"""Generate Watch's offline name/identity catalog from the phone's source catalog.

No images are copied. Existing free-provider media references are preserved.
"""
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = root / 'WorkoutDataKit/everkinetic-data'
legacy = json.loads((source / 'exercises.json').read_text())
updates = json.loads((source / 'opengym-text-templates.json').read_text())
by_id = {item['uuid']: item for item in legacy}
by_id.update({item['uuid']: item for item in updates})
result = []
for item in sorted(by_id.values(), key=lambda item: item['title'].casefold()):
    filename = item.get('animation') or item.get('image') or ''
    basename = Path(filename).stem
    media_id = basename.split('-', 1)[1] if '-' in basename and '/' not in filename else None
    result.append({'id': item['uuid'], 'name': item['title'],
                   'muscle': (item.get('primary') or [None])[0],
                   'imageURL': f'https://static.exercisedb.dev/media/{media_id}.gif' if media_id else None})
destination = root / 'WatchIron Extension/WatchExerciseCatalog.json'
destination.write_text(json.dumps(result, ensure_ascii=False, separators=(',', ':')) + '\n')
assert len({entry['id'] for entry in result}) == len(result)
print(f'{len(result)} exercises; {destination.stat().st_size} bytes')
