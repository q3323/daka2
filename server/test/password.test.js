const test = require('node:test');
const assert = require('node:assert/strict');
const { hashPassword, verifyPassword } = require('../src/password');

test('password hash verifies the correct password', async () => {
  const hash = await hashPassword('correct-horse-battery');
  assert.match(hash, /^scrypt\$/);
  assert.equal(await verifyPassword('correct-horse-battery', hash), true);
});

test('password hash rejects an incorrect password', async () => {
  const hash = await hashPassword('correct-horse-battery');
  assert.equal(await verifyPassword('wrong-password', hash), false);
  assert.equal(await verifyPassword('correct-horse-battery', ''), false);
});

test('password hashes use unique salts', async () => {
  const first = await hashPassword('same-password');
  const second = await hashPassword('same-password');
  assert.notEqual(first, second);
});
