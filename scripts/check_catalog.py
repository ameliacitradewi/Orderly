"""Check reproducibility and important classification/CSV normalization cases."""
import csv
from generate_extension_catalog import SOURCE, DESTINATION, build_catalog, extensions, render

categories, descriptions = build_catalog()
assert DESTINATION.read_text() == render(), 'Regenerate ExtensionCatalog.swift'
assert extensions('.asc/.text/.txt') == ['asc', 'text', 'txt']
assert extensions('.frz/.000-.008') == ['frz'] + [f'{i:03}' for i in range(9)]
assert extensions('.zst/.zs1-.zs9/.z10-.z99') == ['zst'] + [f'zs{i}' for i in range(1, 10)] + [f'z{i}' for i in range(10, 100)]
expected = {
    'pdf': 'document', 'page': 'document', 'csv': 'document',
    'python': 'code', 'html': 'code', 'php?': 'code',
    'h264': 'video', 'mp3': 'audio', 'heic': 'image',
    '.ds_store': 'artifact', 'crdownload': 'artifact', 'nii.gz': 'archive',
    'dmg': 'application', 'deb': 'application',
    'bak': 'other', 'ppk': 'other', 'vmsd': 'other', 'app': 'other'
}
for ext, category in expected.items():
    assert categories[ext] == category, (ext, categories[ext])
with SOURCE.open(newline='') as source:
    rows = list(csv.DictReader(source))
for row in rows:
    for ext in extensions(row['Extension']):
        assert ext in categories, ext
assert len(set(categories.values())) == 9
print(f'PASS: {len(rows)} CSV rows covered; {len(categories)} rules; nine categories; generated Swift is current.')
