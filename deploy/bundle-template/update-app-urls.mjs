import path from 'node:path';
import { createRequire } from 'node:module';

const root = process.cwd();
const require = createRequire(path.join(root, 'backend/sso/package.json'));
const mysql = require('mysql2/promise');

const base = process.env.BASE_DOMAIN;
if (!base) {
  console.warn('缺少 BASE_DOMAIN，跳过 SSO 应用入口更新。');
  process.exit(0);
}
const scheme = process.env.ENABLE_TLS === '1' ? 'https' : 'http';
const sso = process.env.SSO_DOMAIN || `sso.${base}`;
const mockup = process.env.MOCKUP_DOMAIN || `mockup.${base}`;
const cad = process.env.CAD_DOMAIN || `cad.${base}`;
const quiz = process.env.QUIZ_DOMAIN || `quiz.${base}`;

const connection = await mysql.createConnection({
  host: process.env.MYSQL_HOST,
  port: Number(process.env.MYSQL_PORT || 3306),
  user: process.env.MYSQL_USER,
  password: process.env.MYSQL_PASSWORD,
  database: process.env.SSO_DB,
});

try {
  const rows = [
    ['wego-mockup', `${scheme}://${mockup}/`],
    ['wego-cad', `${scheme}://${cad}/`],
    ['wego-quiz', `${scheme}://${quiz}/`],
  ];
  for (const [code, url] of rows) {
    const [result] = await connection.execute(
      'UPDATE sys_app SET entry_url = ? WHERE code = ?',
      [url, code],
    );
    console.log(`${code}: ${result.affectedRows} 行 -> ${url}`);
  }
  console.log(`SSO 入口：${scheme}://${sso}`);
} catch (error) {
  if (error.code === 'ER_NO_SUCH_TABLE' || error.code === 'ER_BAD_DB_ERROR') {
    console.warn('sys_app 不存在，跳过；请先运行 seed。');
  } else {
    throw error;
  }
} finally {
  await connection.end().catch(() => {});
}
