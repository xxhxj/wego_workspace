const path = require('node:path');

const root = __dirname;

module.exports = {
  apps: [
    { name: 'wego-sso-api', cwd: path.join(root, 'backend/sso'), script: 'src/index.js', interpreter: 'node', env: { NODE_ENV: 'production' }, autorestart: true, max_memory_restart: '512M', time: true },
    { name: 'wego-mockup-api', cwd: path.join(root, 'backend/mockup'), script: 'src/index.js', interpreter: 'node', env: { NODE_ENV: 'production' }, autorestart: true, max_memory_restart: '512M', time: true },
    { name: 'wego-quiz-api', cwd: path.join(root, 'backend/quiz'), script: 'src/index.js', interpreter: 'node', env: { NODE_ENV: 'production' }, autorestart: true, max_memory_restart: '512M', time: true },
  ],
};
