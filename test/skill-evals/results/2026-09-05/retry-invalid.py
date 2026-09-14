import concurrent.futures
import hashlib
import json
from pathlib import Path
import runpy
import shutil
from types import SimpleNamespace

root = Path('/Users/george/code/claude-code-elixir/test/skill-evals')
original = Path('/private/tmp/astra-skill-eval/runs-pinned')
output = Path('/private/tmp/astra-skill-eval/runs-retries')
records = json.loads((original / 'results.json').read_text())
manifest = json.loads((original / 'manifest.json').read_text())
for name, expected in manifest.items():
    path = root / ('project/mix.lock' if name == 'mix.lock' else name)
    assert hashlib.sha256(path.read_bytes()).hexdigest() == expected, name
trials = [(r['case'], r['condition'], r['repeat']) for r in records if not r['valid_run']]
output.mkdir()
shutil.copy2(original / 'manifest.json', output / 'manifest.json')
protocol = json.loads((original / 'protocol.json').read_text())
protocol.update(phase='Separate retries of invalid original runs', original=str(original), trials=trials)
(output / 'protocol.json').write_text(json.dumps(protocol, indent=2))
args = SimpleNamespace(base=Path('/private/tmp/astra-skill-eval/base'), output=output, timeout=240)
runner = runpy.run_path(str(root / 'run.py'))
with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
    results = list(pool.map(lambda trial: runner['run_trial'](args, trial), trials))
(output / 'results.json').write_text(json.dumps(results, indent=2))
print('Retry passes', sum(r['passed'] for r in results), '/', len(results), flush=True)
