import path from 'node:path';
import { createRequire } from 'node:module';

const appRoot = process.env.APP_ROOT;
if (!appRoot) {
  console.error('缺少 APP_ROOT');
  process.exit(1);
}

const require = createRequire(path.join(appRoot, 'wego_sso/backend/package.json'));
const mysql = require('mysql2/promise');

const config = {
  host: process.env.MYSQL_HOST,
  port: Number(process.env.MYSQL_PORT || 3306),
  user: process.env.MYSQL_USER,
  password: process.env.MYSQL_PASSWORD,
  database: process.env.SSO_DB,
};

const apps = [
  ['wego-mockup', process.env.MOCKUP_PUBLIC_URL],
  ['wego-cad', process.env.CAD_PUBLIC_URL],
  ['wego-quiz', process.env.QUIZ_PUBLIC_URL],
];

let connection;
try {
  connection = await mysql.createConnection(config);
  for (const [code, url] of apps) {
    if (!url) continue;
    const entryUrl = `${url.replace(/\/$/, '')}/`;
    const [result] = await connection.execute(
      'UPDATE sys_app SET entry_url = ? WHERE code = ?',
      [entryUrl, code],
    );
    console.log(`${code}: ${result.affectedRows} 行 -> ${entryUrl}`);
  }
} catch (error) {
  if (error.code === 'ER_NO_SUCH_TABLE' || error.code === 'ER_BAD_DB_ERROR') {
    console.warn('sys_app 表不存在，跳过应用入口更新；请先运行 seed。');
    process.exitCode = 0;
  } else {
    throw error;
  }
} finally {
  await connection?.end().catch(() => {});
}
