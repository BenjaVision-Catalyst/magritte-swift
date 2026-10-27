#!/usr/bin/env python3
"""Compare supported Magritte JSON semantics, not nonsemantic enumeration order."""
import json
import sys
from pathlib import Path

def canonical(value):
    if isinstance(value, list):
        return [canonical(v) for v in value]
    if isinstance(value, dict):
        result = {k: canonical(v) for k, v in value.items()}
        key = lambda v: json.dumps(v, sort_keys=True, ensure_ascii=False)
        if result.get('type') in ('set', 'bag'):
            result['value'].sort(key=key)
        if 'labels' in result:
            result['labels'].sort(key=lambda v: key(v['value']))
        if 'classes' in result:
            result['classes'].sort()
        for table in ('collections', 'childCollections'):
            if table in result:
                result[table].sort(key=lambda v: v['id'])
        if result.get('kind') in ('set', 'bag') and 'elements' in result:
            result['elements'].sort(key=key)
        if 'descriptions' in result:
            result['descriptions'].sort(key=lambda v: v['id'])
            result['objects'].sort(key=lambda v: v['id'])
        return result
    return value

if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit('usage: compare-graphs.py first.json second.json')
    left, right = (canonical(json.loads(Path(p).read_text())) for p in sys.argv[1:])
    if left != right:
        raise SystemExit('Graph semantics differ')
    print('Graph semantics match')
