import gzip
import hashlib
import io
import json
import os
import re
import sys
import tarfile
from pathlib import Path

root = Path(__file__).resolve().parent.parent
skill_dir = root / 'skills' / 'plain-support'
output_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else root / 'dist' / 'discovery'
commit = os.environ['GITHUB_SHA']
if re.fullmatch(r'[0-9a-f]{40}', commit) is None:
    raise ValueError('GITHUB_SHA must be a full lowercase commit SHA')

frontmatter = (skill_dir / 'SKILL.md').read_text().split('---', 2)[1]
description = next(line.removeprefix('description: ').strip() for line in frontmatter.splitlines() if line.startswith('description: '))
output_dir.mkdir(parents=True, exist_ok=True)
archive_path = output_dir / 'plain-support.tar.gz'

with archive_path.open('wb') as output:
    with gzip.GzipFile(filename='', fileobj=output, mode='wb', mtime=0) as compressed:
        with tarfile.open(fileobj=compressed, mode='w', format=tarfile.USTAR_FORMAT) as archive:
            for path in sorted(skill_dir.rglob('*')):
                if path.is_symlink():
                    raise ValueError(f'Symlinks are not supported: {path}')
                if path.is_file():
                    data = path.read_bytes()
                    entry = tarfile.TarInfo(path.relative_to(skill_dir).as_posix())
                    entry.size = len(data)
                    entry.mode = path.stat().st_mode & 0o777
                    archive.addfile(entry, io.BytesIO(data))

index = {
    '$schema': 'https://schemas.agentskills.io/discovery/0.2.0/schema.json',
    'skills': [{
        'name': 'plain-support',
        'type': 'archive',
        'description': description,
        'url': f'https://github.com/team-plain/skills/releases/download/discovery-{commit}/plain-support.tar.gz',
        'digest': 'sha256:' + hashlib.sha256(archive_path.read_bytes()).hexdigest(),
    }],
}
(output_dir / 'index.json').write_text(json.dumps(index, indent=2) + '\n')
