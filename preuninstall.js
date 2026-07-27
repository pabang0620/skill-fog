#!/usr/bin/env node
'use strict';

const { spawnSync } = require('child_process');
const path = require('path');
const fs = require('fs');

const UNINSTALL_SCRIPT = path.join(__dirname, 'uninstall.sh');

function main() {
  console.log("[skill-fog] Data in ~/.skill-fog is preserved. Run 'bash uninstall.sh --remove-data' to remove it.");

  // npm preuninstall은 CI 환경이나 --ignore-scripts 시 스킵
  if (process.env.CI || process.env.SKIP_SKILL_FOG_UNINSTALL) {
    console.log('[skill-fog] Skipping uninstall (CI or SKIP_SKILL_FOG_UNINSTALL set)');
    return;
  }

  if (!fs.existsSync(UNINSTALL_SCRIPT)) {
    console.error('[skill-fog] uninstall.sh not found. Please run manually:');
    console.error('  bash ./uninstall.sh --keep-data --yes');
    return;
  }

  console.log('[skill-fog] Running uninstall.sh...');

  const result = spawnSync('bash', [UNINSTALL_SCRIPT, '--keep-data', '--yes'], {
    stdio: 'inherit',
    env: process.env,
  });

  if (result.error) {
    console.error('[skill-fog] Failed to run uninstall.sh:', result.error.message);
    process.exit(1);
  }

  if (result.status !== 0) {
    console.error('[skill-fog] uninstall.sh exited with code ' + result.status);
    process.exit(result.status > 0 ? result.status : 1);
  }
}

main();
