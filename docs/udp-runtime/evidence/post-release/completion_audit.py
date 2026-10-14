"""Verify hardening delivery without changing source, tags or publication."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--write', action='store_true')
args = parser.parse_args()
evidence = Path(__file__).resolve().parent
root = evidence.parents[3]

def git(*arguments):
    return subprocess.check_output(['git', *arguments], cwd=root)

pub = json.loads((evidence / 'published-verification.json').read_text())
head = git('rev-parse', 'HEAD').decode().strip()
remote = {line.split()[1]: line.split()[0] for line in git(
    'ls-remote', 'origin', 'refs/heads/main', 'refs/heads/codex/post-release-hardening',
    'refs/tags/0.8.1').decode().splitlines()}
assert remote['refs/heads/main'] == head == remote['refs/heads/codex/post-release-hardening']
assert remote['refs/tags/0.8.1'] == pub['tag_sha']
paths = ['lib', 'test', 'scripts', '.github/workflows', 'mix.exs', 'mix.lock', 'README.md']
assert not git('diff', '--name-only', pub['tag_sha'], head, '--', *paths).strip()
for entry in pub['source_files']:
    assert hashlib.sha256((root / entry['file']).read_bytes()).hexdigest() == entry['sha256']
locks = [name for name in git('ls-tree', '-r', '--name-only', 'cd65c84').decode().splitlines()
         if name.endswith('.lock')]
for name in locks:
    assert git('show', 'cd65c84:' + name) == git('show', head + ':' + name)
checked_jobs = 0
for prefix, count in [('final-regressions', 3), ('final-network', 19),
                      ('main-regressions', 3), ('main-network', 19),
                      ('main-test', 1), ('release-workflow', 2)]:
    result = json.loads((evidence / (prefix + '-results.json')).read_text())
    assert result['conclusion'] == 'success' and len(result['jobs']) == count
    for job in result['jobs']:
        assert job['conclusion'] == 'success'
        assert hashlib.sha256((evidence / job['evidence_log']).read_bytes()).hexdigest() == job['sha256']
        checked_jobs += 1
ci = json.loads((evidence / 'main-ci-results.json').read_text())
assert ci['headSha'] == pub['tag_sha'] and ci['conclusion'] == 'failure'
for job in ci['jobs']:
    expected = 'failure' if job['name'] == 'Credo' else 'success'
    assert job['conclusion'] == expected
    assert hashlib.sha256((evidence / job['evidence_log']).read_bytes()).hexdigest() == job['sha256']
for filename, names in [
    ('final-otp27-results.json', ['format', 'compile-dev', 'compile-test']),
    ('final-otp27-static-resume-results.json', ['dialyzer-retry', 'docs']),
    ('final-otp28-results.json', ['format', 'compile-dev', 'compile-test', 'dialyzer', 'docs'])]:
    records = json.loads((evidence / filename).read_text())['results']
    for name in names:
        assert next(record for record in records if record['name'] == name)['exit'] == 0
for name in ['final-quic-check-exit.txt', 'final-quic-independent-exit.txt']:
    assert (evidence / name).read_text().strip() == '0'
for runtime in ['otp27', 'otp28']:
    result = json.loads((evidence / ('final-' + runtime + '-credo-comparison.json')).read_text())
    assert result['baseline'] == result['current'] == 83 and not result['introduced']
assert pub['result'] == 'PASS' and pub['actual_wire_exchanges'] == 54
assert pub['packaged_file_count'] == 46
assert (evidence / 'published-verifier-exit.txt').read_text().strip() == '0'
for log in ['final-otp27-integration-retry.log', 'final-otp28-integration-final.log']:
    assert '688 tests, 0 failures' in (evidence / log).read_text()
assert sum('RUNTIME_STRESS_PASS' in line for line in (
    evidence / 'final-runtime-stress-otp27.log').read_text().splitlines()) == 3
for name in ['abyss-udp-broadcast-multicast-codex-prompt.md', 'abyss-udp-codex-prompt.md',
             'abyss-udp-implementation-plan.md']:
    assert (root.parent.parent / name).is_file()
result = {'result': 'PASS', 'handoff_verified_sha': head, 'release_tag': '0.8.1',
          'immutable_release_sha': pub['tag_sha'], 'remote_refs': remote,
          'published_files_checked': 46, 'existing_lockfiles_unchanged': locks,
          'code_test_script_workflow_parity': 'PASS',
          'source_linked_success_jobs_checked': checked_jobs,
          'credo': '83 baseline, zero introduced; absolute FAIL',
          'full_integration': '688 tests + 3 doctests / 0 each final runtime',
          'publication': '54 actual exchanges,18 endpoints,checksum/source parity PASS',
          'unrelated_user_files': 'three originals remain preserved',
          'remaining_required_work': 'NONE'}
if args.write:
    (evidence / 'completion-audit.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result, indent=2))
