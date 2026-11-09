import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');

function readEnv(file) {
  const full = path.join(root, file);
  const out = {};
  if (!fs.existsSync(full)) return out;
  for (const line of fs.readFileSync(full, 'utf8').split(/\r?\n/)) {
    const match = line.match(/^\s*([A-Za-z0-9_]+)\s*=\s*(.*)\s*$/);
    if (!match || match[1].startsWith('#')) continue;
    let value = match[2].trim();
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    }
    out[match[1]] = value;
  }
  return out;
}

const sso = readEnv('wego_sso/backend/.env');
const mockup = readEnv('wego_3d_texture/backend/.env');
const quiz = readEnv('wego_quiz_3d/backend/.env');

const mysqlHost = sso.MYSQL_HOST || mockup.MYSQL_HOST || quiz.MYSQL_HOST || '127.0.0.1';
const mysqlPort = sso.MYSQL_PORT || mockup.MYSQL_PORT || quiz.MYSQL_PORT || '3306';
const mysqlUser = sso.MYSQL_USER || mockup.MYSQL_USER || quiz.MYSQL_USER || 'root';
const mysqlPassword = sso.MYSQL_PASSWORD || mockup.MYSQL_PASSWORD || quiz.MYSQL_PASSWORD || '';
const minioEndpoint = mockup.MINIO_ENDPOINT || '127.0.0.1';
const minioPort = mockup.MINIO_PORT || '9000';
const minioUseSsl = mockup.MINIO_USE_SSL || 'false';
const minioScheme = minioUseSsl === 'true' ? 'https' : 'http';

function shellQuote(value) {
  return `'${String(value).replace(/'/g, "'\\''")}'`;
}

const lines = [
  '# 由 make-deploy-env.mjs 根据本机 .env 生成；包含密钥，不要提交到 Git。',
  'BASE_DOMAIN=your-domain.com',
  'SSO_DOMAIN=',
  'MOCKUP_DOMAIN=',
  'CAD_DOMAIN=',
  'QUIZ_DOMAIN=',
  'FILES_DOMAIN=',
  'ENABLE_TLS=0',
  'LETSENCRYPT_EMAIL=',
  '',
  '# MySQL',
  `MYSQL_HOST=${shellQuote(mysqlHost)}`,
  `MYSQL_PORT=${shellQuote(mysqlPort)}`,
  `MYSQL_USER=${shellQuote(mysqlUser)}`,
  `MYSQL_PASSWORD=${shellQuote(mysqlPassword)}`,
  `SSO_DB=${shellQuote(sso.MYSQL_DATABASE || 'wego_sso')}`,
  `MOCKUP_DB=${shellQuote(mockup.MYSQL_DATABASE || 'wego_mockup')}`,
  `QUIZ_DB=${shellQuote(quiz.MYSQL_DATABASE || 'wego_quiz')}`,
  `MYSQL_TIMEZONE=${shellQuote(quiz.MYSQL_TIMEZONE || '+08:00')}`,
  '',
  '# MinIO',
  `MINIO_ENDPOINT=${shellQuote(minioEndpoint)}`,
  `MINIO_PORT=${shellQuote(minioPort)}`,
  `MINIO_USE_SSL=${shellQuote(minioUseSsl)}`,
  `MINIO_ACCESS_KEY=${shellQuote(mockup.MINIO_ACCESS_KEY || '')}`,
  `MINIO_SECRET_KEY=${shellQuote(mockup.MINIO_SECRET_KEY || '')}`,
  `MINIO_BUCKET=${shellQuote(mockup.MINIO_BUCKET || 'wego-mockup')}`,
  'MINIO_PUBLIC_BASE=',
  'MINIO_PROXY=1',
  `MINIO_PROXY_TARGET=${shellQuote(`${minioScheme}://${minioEndpoint}:${minioPort}`)}`,
  '',
  '# App',
  `SSO_API_URL=${shellQuote(mockup.SSO_API_URL || 'http://127.0.0.1:3001')}`,
  `JWT_EXPIRES=${shellQuote('12h')}`,
  `QUIZ_TOKEN_SECRET=${shellQuote(quiz.QUIZ_TOKEN_SECRET || '')}`,
  'RUN_SEED=0',
  'FORCE_INSTALL=0',
  'PM2_CMD=pm2',
  '',
];

fs.writeFileSync(path.join(here, 'deploy.env'), lines.join('\n'), { mode: 0o600 });
console.log('已生成 deploy/deploy.env（含本机数据库/MinIO 配置，已设为仅当前用户可读）。');
console.log('请编辑 BASE_DOMAIN、ENABLE_TLS、LETSENCRYPT_EMAIL，再运行 deploy.sh。');
