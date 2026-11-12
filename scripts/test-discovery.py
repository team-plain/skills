import hashlib
import json
import os
import subprocess
import tarfile
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
COMMIT = 'a' * 40


class DiscoveryTest(unittest.TestCase):
    def test_archive_and_index_match(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            env = {**os.environ, 'GITHUB_SHA': COMMIT}
            command = ['python3', str(ROOT / 'scripts/build-discovery.py'), str(output)]
            subprocess.run(command, env=env, check=True)
            archive = (output / 'plain-support.tar.gz').read_bytes()
            index = json.loads((output / 'index.json').read_text())
            skill = index['skills'][0]
            self.assertEqual(skill['digest'], 'sha256:' + hashlib.sha256(archive).hexdigest())
            self.assertEqual(skill['url'], f'https://github.com/team-plain/skills/releases/download/discovery-{COMMIT}/plain-support.tar.gz')
            with tarfile.open(output / 'plain-support.tar.gz', 'r:gz') as contents:
                self.assertIn('SKILL.md', contents.getnames())
                self.assertIn('scripts/plain-api.sh', contents.getnames())
                self.assertIn('references/ENTITIES.md', contents.getnames())
                instructions = contents.extractfile('SKILL.md').read().decode()
                self.assertIn(f"description: {skill['description']}", instructions)
            subprocess.run(command, env=env, check=True)
            self.assertEqual(archive, (output / 'plain-support.tar.gz').read_bytes())


if __name__ == '__main__':
    unittest.main()
