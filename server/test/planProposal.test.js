const test = require('node:test');
const assert = require('node:assert/strict');
const { PlanFormatError, normalizePlanProposal } = require('../src/planProposal');

test('normalizes a fenced JSON plan proposal', () => {
  const proposal = normalizePlanProposal(
    '可以这样安排：\n```json\n' +
    '{"summary":"一周计划","plans":[{"name":"晨跑","timesPerDay":1,"totalDays":7,"remark":"慢跑"}]}' +
    '\n```'
  );
  assert.equal(proposal.summary, '一周计划');
  assert.equal(proposal.plans.length, 1);
  assert.equal(proposal.plans[0].action, 'add');
  assert.equal(proposal.plans[0].name, '晨跑');
});

test('normalizes field aliases and updates an existing plan', () => {
  const proposal = normalizePlanProposal(
    JSON.stringify({
      message: '调整节奏',
      plans: [{
        planId: 'plan_1720000000000_1',
        title: '背单词',
        times_per_day: '2',
        days: 14,
        description: '每天两组'
      }]
    }),
    ['plan_1720000000000_1']
  );
  assert.equal(proposal.plans[0].action, 'update');
  assert.equal(proposal.plans[0].timesPerDay, 2);
  assert.equal(proposal.plans[0].totalDays, 14);
});

test('rejects plans outside the allowed limits', () => {
  assert.throws(
    () => normalizePlanProposal(JSON.stringify({
      plans: [{ name: '熬夜', timesPerDay: 21, totalDays: 7 }]
    })),
    PlanFormatError
  );
});

test('rejects non-JSON AI output', () => {
  assert.throws(
    () => normalizePlanProposal('建议你每天跑步。'),
    PlanFormatError
  );
});

test('rejects updates to an unknown plan id', () => {
  assert.throws(
    () => normalizePlanProposal(JSON.stringify({
      plans: [{
        action: 'update',
        planId: 'plan_missing',
        name: '晨跑',
        timesPerDay: 1,
        totalDays: 7
      }]
    }), ['plan_existing']),
    PlanFormatError
  );
});

test('rejects unsupported plan actions', () => {
  assert.throws(
    () => normalizePlanProposal(JSON.stringify({
      plans: [{
        action: 'delete',
        name: '晨跑',
        timesPerDay: 1,
        totalDays: 7
      }]
    })),
    PlanFormatError
  );
});
