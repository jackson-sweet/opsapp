#!/usr/bin/env python3
"""Lightweight source verification only: no build, package resolution or tests."""
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[3]
source = [
    'OPS/Utilities/PhotoCacheLedger.swift', 'OPS/Utilities/PhotoThumbnailLoader.swift',
    'OPS/Utilities/DurableCaptureStore.swift', 'OPS/Utilities/CameraCaptureSession.swift',
    'OPS/Utilities/PhotoPrefetchProjectReader.swift', 'OPS/Utilities/LeadImageStager.swift',
    'OPS/Utilities/PhotoPrefetchService.swift', 'OPS/Utilities/ImageFileManager.swift',
    'OPS/Utilities/StorageProfiler.swift', 'OPS/Utilities/PhotoDownloadManager.swift',
    'OPS/Services/LeadImageService.swift', 'OPS/Views/Components/Images/CameraBatchView.swift',
    'OPS/Utilities/StagedPhotoDestinations.swift', 'OPS/Utilities/ProjectPhotoFormDraftStore.swift',
    'OPS/Views/Leads/LeadDetailView.swift', 'OPS/Views/Leads/DaySheet/DaySheetLeadCard.swift',
    'OPS/Views/Components/Project/ProjectDetailsView.swift', 'OPS/Views/Components/Project/ProjectActionBar.swift',
    'OPS/Views/JobBoard/ProjectFormSheet.swift', 'OPS/Network/ImageSyncManager.swift',
    'OPS/Network/Sync/PhotoProcessor.swift',
]
tests = sorted(str(p.relative_to(root)) for p in (root / 'OPSTests/Media').glob('*.swift'))
subprocess.run(['xcrun', 'swiftc', '-frontend', '-parse', *source, *tests], cwd=root, check=True)
print(f'PASS: Swift syntax parse of {len(source)} source files and {len(tests)} test files (not typecheck/build/test).')
subprocess.run(['git', '-c', 'core.whitespace=cr-at-eol', 'diff', '--check'], cwd=root, check=True)
print('PASS: diff whitespace check with existing CRLF accepted.')
for name in source:
    old = subprocess.run(['git', 'show', f'94543f955ca8a2ccee4cc148c24c6d33de92cccc:{name}'], cwd=root, capture_output=True)
    if old.returncode: continue
    current = (root / name).read_bytes()
    if old.stdout.count(b'\r\n') == old.stdout.count(b'\n'):
        assert current.count(b'\r\n') == current.count(b'\n'), name
    elif b'\r\n' not in old.stdout:
        assert b'\r\n' not in current, name
print('PASS: original LF/CRLF conventions retained in existing source files.')
prefetch = (root / 'OPS/Utilities/PhotoPrefetchService.swift').read_text()
assert 'wouldExceedBudget(' not in prefetch and '.currentUsageBytes()' not in prefetch
assert 'capturedImages: [UIImage]' not in (root / 'OPS/Views/Components/Images/CameraBatchView.swift').read_text()
print('PASS: removed main-actor per-photo cache scans and in-memory original batch array.')
for name in ['LeadDetailView.swift', 'DaySheetLeadCard.swift', 'ProjectDetailsView.swift', 'ProjectActionBar.swift', 'ProjectFormSheet.swift']:
    path = next((root / 'OPS/Views').rglob(name))
    assert 'CameraBatchView {' not in path.read_text(), name
assert 'StorageProfiler.shared.budgetBytes' not in (root / 'OPS/Utilities/ImageFileManager.swift').read_text()
print('PASS: all five owned production camera hosts use typed destination receipts; disk writer avoids main-actor profiler instance.')
print('XCTest compilation/execution and runtime/device performance remain UNRUN pending PM build baton.')
