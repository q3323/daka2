const express = require('express');
const { requireAuth } = require('../auth');
const { PlanFormatError, normalizePlanProposal } = require('../planProposal');
const { asyncHandler } = require('../utils');

const router = express.Router();

router.post('/normalize', requireAuth, asyncHandler(async (req, res) => {
  try {
    const planIds = Array.isArray(req.body.planIds)
      ? req.body.planIds.filter((value) => typeof value === 'string').slice(0, 50)
      : [];
    const proposal = normalizePlanProposal(req.body.content, planIds);
    return res.json({ proposal });
  } catch (err) {
    if (err instanceof PlanFormatError) {
      return res.status(422).json({ message: err.message });
    }
    throw err;
  }
}));

module.exports = router;
