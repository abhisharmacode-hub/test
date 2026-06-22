import { cloudEvent } from '@google-cloud/functions-framework';
import { CloudBillingClient } from '@google-cloud/billing';

const billing = new CloudBillingClient();
const PROJECT_ID = process.env.GOOGLE_CLOUD_PROJECT;
const PROJECT_NAME = `projects/${PROJECT_ID}`;

// Triggered (via Eventarc) by Cloud Billing budget Pub/Sub messages. When actual
// spend passes the budget amount, it detaches the billing account from this
// project — a hard stop on all paid resources. Use ONLY on sandbox/non-prod
// projects; production should keep alert-only budgets.
cloudEvent('stopBilling', async (event) => {
  const raw = event?.data?.message?.data;
  const note = raw ? JSON.parse(Buffer.from(raw, 'base64').toString()) : {};
  console.log('Budget message:', JSON.stringify(note));

  // Only act once spend has actually exceeded the budget.
  if (!note.costAmount || note.costAmount <= note.budgetAmount) {
    console.log(`No action. cost=${note.costAmount} budget=${note.budgetAmount}`);
    return;
  }

  const [info] = await billing.getProjectBillingInfo({ name: PROJECT_NAME });
  if (!info.billingEnabled) {
    console.log('Billing already disabled — nothing to do.');
    return;
  }

  // Empty billingAccountName disassociates billing = spend stops.
  await billing.updateProjectBillingInfo({
    name: PROJECT_NAME,
    resource: { billingAccountName: '' },
  });
  console.log(`Billing DISABLED for ${PROJECT_NAME}`);
});
