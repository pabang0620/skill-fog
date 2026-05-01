#!/usr/bin/env node
'use strict';

const { execSync, spawnSync } = require('child_process');
const path = require('path');
const fs = require('fs');

const INSTALL_SCRIPT = path.join(__dirname, 'install.sh');

function main() {
  // npm postinstall은 CI 환경이나 --ignore-scripts 시 스킵
  if (process.env.CI || process.env.SKIP_SKILL_FOG_INSTALL) {
    console.log('[skill-fog] Skipping install (CI or SKIP_SKILL_FOG_INSTALL set)');
    return;
  }

  if (!fs.existsSync(INSTALL_SCRIPT)) {
    console.error('[skill-fog] install.sh not found. Please run manually:');
    console.error('  bash ./install.sh');
    return;
  }

  console.log('[skill-fog] Running install.sh...');

  const result = spawnSync('bash', [INSTALL_SCRIPT], {
    stdio: 'inherit',
    env: process.env,
  });

  if (result.error) {
    console.error('\n[skill-fog] Failed to run install.sh automatically.');
    console.error('  Error:', result.error.message);
    console.error('\nPlease run manually:');
    console.error('  bash ' + INSTALL_SCRIPT);
    process.exit(0); // npm install 자체는 실패로 처리하지 않음
  }

  if (result.status !== 0) {
    console.error('\n[skill-fog] Installation failed with exit code ' + result.status);
    console.error('\nTo retry manually:');
    console.error('  bash ' + INSTALL_SCRIPT);
    process.exit(result.status);
  }
}

main();
