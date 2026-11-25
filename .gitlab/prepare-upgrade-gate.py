#!/usr/bin/env python3
"""Temporarily gate only real default-branch image deployments for the 0.31 rollout."""
import json
import os
from pathlib import Path

plan = json.loads(Path('ci-plan.json').read_text())
if not isinstance(plan['image'], bool):
    raise ValueError('Planner image selection must be a boolean')
main = bool(os.environ.get('CI_COMMIT_BRANCH')) and os.environ.get('CI_COMMIT_BRANCH') == os.environ.get('CI_DEFAULT_BRANCH')
gate = {'variables': {'EMVI_UPGRADE_GATE': 'inactive'}}
if plan['image'] and main and not os.environ.get('CI_MERGE_REQUEST_IID'):
    gate = {'staging': {'when': 'manual', 'allow_failure': False}}
Path('ci-upgrade-gate.yml').write_text(json.dumps(gate) + '\n')
