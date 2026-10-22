"""Regression coverage for ZIP extraction into an existing document root."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location('package_website', Path(__file__).parents[1] / 'ci/package_website.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class WebrootArchiveTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.source = self.base / 'assembled'
        self.root = self.source / 'FELTOLTENDO'
        self.records = []
        for name, data in [('index.html', b'<h1>Website</h1>'), ('flow/app/index.html', b'<h1>App</h1>'), ('assets/mobile-v41.css', b'body{margin:0}')]:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            self.records.append({'path': name, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
        (self.source / 'FAJLLISTA.json').write_text(json.dumps(self.records))

    def test_extract_at_document_root_and_exclude_transfer_leftovers(self):
        (self.root / '.leftover.apk').write_bytes(b'unlisted transfer')
        archive = self.base / 'upload.zip'
        module.package(self.source, archive)
        document_root = self.base / 'public_html'
        document_root.mkdir()
        (document_root / '.htaccess').write_text('existing rewrites')
        with zipfile.ZipFile(archive) as z:
            self.assertIn('index.html', z.namelist())
            self.assertGreater(z.getinfo('index.html').date_time[0], 1980)
            self.assertNotIn('.leftover.apk', z.namelist())
            self.assertTrue(all((i.external_attr >> 16) & 0o777 == 0o644 for i in z.infolist()))
            z.extractall(document_root)
        self.assertEqual((document_root / 'index.html').read_bytes(), b'<h1>Website</h1>')
        self.assertEqual((document_root / '.htaccess').read_text(), 'existing rewrites')
        self.assertFalse((document_root / 'FELTOLTENDO').exists())

    def test_reject_incomplete_upload(self):
        (self.root / 'index.html').write_text('partial upload')
        with self.assertRaisesRegex(ValueError, 'differs from manifest'):
            module.package(self.source, self.base / 'upload.zip')

    def test_reject_escape_path(self):
        self.records[0]['path'] = '../index.html'
        (self.source / 'FAJLLISTA.json').write_text(json.dumps(self.records))
        with self.assertRaisesRegex(ValueError, 'Invalid upload path'):
            module.package(self.source, self.base / 'upload.zip')


if __name__ == '__main__':
    unittest.main()
