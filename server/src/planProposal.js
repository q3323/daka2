const MAX_CONTENT_LENGTH = 20000;
const MAX_PLANS = 10;
const MAX_NAME_LENGTH = 100;
const MAX_REMARK_LENGTH = 500;
const MAX_SUMMARY_LENGTH = 500;
const MIN_TIMES_PER_DAY = 1;
const MAX_TIMES_PER_DAY = 20;
const MIN_TOTAL_DAYS = 1;
const MAX_TOTAL_DAYS = 365;
const PLAN_ID_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;

class PlanFormatError extends Error {
  constructor(message) {
    super(message);
    this.name = 'PlanFormatError';
  }
}

function textOf(value, maxLength) {
  if (typeof value !== 'string') {
    return '';
  }
  return value.trim().slice(0, maxLength);
}

function firstText(values, maxLength) {
  for (const value of values) {
    const text = textOf(value, maxLength);
    if (text) {
      return text;
    }
  }
  return '';
}

function integerOf(value) {
  if (typeof value === 'number') {
    return Number.isInteger(value) ? value : NaN;
  }
  if (typeof value === 'string' && /^\d+$/.test(value.trim())) {
    return Number(value.trim());
  }
  return NaN;
}

function firstInteger(values) {
  for (const value of values) {
    const parsed = integerOf(value);
    if (Number.isInteger(parsed)) {
      return parsed;
    }
  }
  return NaN;
}

function extractJsonText(content) {
  if (typeof content !== 'string') {
    throw new PlanFormatError('AI 计划内容为空');
  }
  const raw = content.replace(/^\uFEFF/, '').trim();
  if (raw.length === 0 || raw.length > MAX_CONTENT_LENGTH) {
    throw new PlanFormatError('AI 计划内容为空或过长');
  }

  const fenced = raw.match(/```(?:json)?\s*([\s\S]*?)```/i);
  if (fenced && fenced[1]) {
    return fenced[1].trim();
  }

  const start = raw.indexOf('{');
  const end = raw.lastIndexOf('}');
  if (start >= 0 && end > start) {
    return raw.slice(start, end + 1);
  }
  return raw;
}

function normalizePlan(rawPlan, index) {
  if (!rawPlan || typeof rawPlan !== 'object' || Array.isArray(rawPlan)) {
    throw new PlanFormatError(`第 ${index + 1} 个计划格式不正确`);
  }

  const planId = firstText([rawPlan.planId, rawPlan.id], 64);
  const rawAction = firstText([rawPlan.action], 16).toLowerCase();
  if (rawAction && rawAction !== 'add' && rawAction !== 'update') {
    throw new PlanFormatError(`第 ${index + 1} 个计划包含不支持的操作`);
  }
  const action = rawAction === 'update' || (!rawAction && planId.length > 0)
    ? 'update'
    : 'add';
  if (action === 'update' && !PLAN_ID_PATTERN.test(planId)) {
    throw new PlanFormatError(`第 ${index + 1} 个计划缺少有效的计划编号`);
  }

  const name = firstText(
    [rawPlan.name, rawPlan.title, rawPlan.planName],
    MAX_NAME_LENGTH
  );
  const timesPerDay = firstInteger([
    rawPlan.timesPerDay,
    rawPlan.times_per_day,
    rawPlan.dailyTimes,
    rawPlan.frequency
  ]);
  const totalDays = firstInteger([
    rawPlan.totalDays,
    rawPlan.total_days,
    rawPlan.days,
    rawPlan.durationDays
  ]);
  const remark = firstText(
    [rawPlan.remark, rawPlan.description, rawPlan.note],
    MAX_REMARK_LENGTH
  );

  if (!name) {
    throw new PlanFormatError(`第 ${index + 1} 个计划缺少名称`);
  }
  if (!Number.isInteger(timesPerDay)
    || timesPerDay < MIN_TIMES_PER_DAY
    || timesPerDay > MAX_TIMES_PER_DAY) {
    throw new PlanFormatError(`第 ${index + 1} 个计划每天次数必须在 1 到 20 之间`);
  }
  if (!Number.isInteger(totalDays)
    || totalDays < MIN_TOTAL_DAYS
    || totalDays > MAX_TOTAL_DAYS) {
    throw new PlanFormatError(`第 ${index + 1} 个计划总天数必须在 1 到 365 之间`);
  }

  return {
    action,
    planId: action === 'update' ? planId : '',
    name,
    timesPerDay,
    totalDays,
    remark
  };
}

function normalizePlanProposal(content, existingPlanIds) {
  const jsonText = extractJsonText(content);
  let parsed;
  try {
    parsed = JSON.parse(jsonText);
  } catch (err) {
    throw new PlanFormatError('AI 返回的内容不是有效 JSON，请重试');
  }

  const root = Array.isArray(parsed) ? { plans: parsed } : parsed;
  if (!root || typeof root !== 'object' || !Array.isArray(root.plans)) {
    throw new PlanFormatError('AI 返回内容缺少 plans 数组');
  }
  if (root.plans.length === 0) {
    throw new PlanFormatError('AI 没有生成任何计划');
  }
  if (root.plans.length > MAX_PLANS) {
    throw new PlanFormatError(`一次最多应用 ${MAX_PLANS} 个计划`);
  }

  const plans = root.plans.map(normalizePlan);
  const allowedUpdateIds = Array.isArray(existingPlanIds)
    ? new Set(existingPlanIds.filter((value) => typeof value === 'string'))
    : null;
  const updateIds = new Set();
  for (const plan of plans) {
    if (plan.action !== 'update') {
      continue;
    }
    if (updateIds.has(plan.planId)) {
      throw new PlanFormatError('AI 重复修改了同一个计划');
    }
    if (allowedUpdateIds && !allowedUpdateIds.has(plan.planId)) {
      throw new PlanFormatError('AI 尝试修改一个不存在的计划');
    }
    updateIds.add(plan.planId);
  }

  const summary = firstText(
    [root.summary, root.message, root.reply],
    MAX_SUMMARY_LENGTH
  );
  return {
    summary: summary || `已生成 ${plans.length} 项计划调整`,
    plans
  };
}

module.exports = {
  PlanFormatError,
  normalizePlanProposal
};
