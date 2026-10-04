#!/usr/bin/env python3
"""Fast isolated launcher smoke checks; the serving model is a labeled HTTP fixture."""
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
print('Launcher smoke: explicit HTTP protocol fixture; no live-model quality claim.', flush=True)
suite = unittest.defaultTestLoader.discover(str(ROOT / 'tests'), pattern='test_judge_setup.py')
result = unittest.TextTestRunner(verbosity=2).run(suite)
raise SystemExit(0 if result.wasSuccessful() else 1)
