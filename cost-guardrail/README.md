# GCP Cost Guardrail — automatic budget kill-switch

A serverless safety net that **stops cloud spend before a runaway bill happens.**
When a project's Cloud Billing budget is exceeded, a Cloud Run function automatically
**detaches billing** from the project, halting all paid resources.

```
Cloud Billing Budget ──▶ Pub/Sub topic ──▶ Eventarc ──▶ Cloud Run Function ──▶ Cloud Billing API
   (100% reached)         (spend message)               (this code)            (disable billing)
```

> ⚠️ This is a **hard stop** — detaching billing takes every paid resource on the project
> offline. Use it on **sandbox / experiment projects only.** For production, prefer
> **alert-only** budgets (threshold emails) and act manually.

---

## Files
- `index.js` — the function (Node.js, ESM, Functions Framework `cloudEvent` handler)
- `package.json` — dependencies (`@google-cloud/functions-framework`, `@google-cloud/billing`)

## How it works
1. A **Cloud Billing budget** publishes spend updates to a **Pub/Sub topic**.
2. **Eventarc** delivers each message to the Cloud Run function as a CloudEvent.
3. The function decodes the budget payload; if `costAmount > budgetAmount`, it calls
   `updateProjectBillingInfo` with an empty billing account to **disable billing**.

## Deploy (sanitized — replace placeholders)

```bash
PROJECT_ID=your-sandbox-project
BILLING_ACCOUNT_ID=XXXXXX-XXXXXX-XXXXXX
REGION=asia-south1

gcloud config set project "$PROJECT_ID"

# 1. Enable APIs
gcloud services enable cloudbilling.googleapis.com cloudfunctions.googleapis.com \
  cloudbuild.googleapis.com pubsub.googleapis.com run.googleapis.com

# 2. Pub/Sub topic the budget publishes to
gcloud pubsub topics create stop-billing

# 3. Service account that runs the function (needs billing-admin to disable billing)
gcloud iam service-accounts create stop-billing-fn --display-name="Stop Billing Function"
gcloud billing accounts add-iam-policy-binding "$BILLING_ACCOUNT_ID" \
  --member="serviceAccount:stop-billing-fn@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/billing.admin"

# 4. Deploy (Eventarc Pub/Sub trigger on the topic)
gcloud functions deploy stop-billing \
  --gen2 --runtime=nodejs20 --region="$REGION" \
  --trigger-topic=stop-billing --entry-point=stopBilling \
  --service-account="stop-billing-fn@$PROJECT_ID.iam.gserviceaccount.com"
```

Then create a **Cloud Billing budget** scoped to the project and connect it to the
`stop-billing` Pub/Sub topic (Budgets & alerts → Manage notifications → Connect a Pub/Sub topic).

## Test safely
```bash
# Dry run — under budget, logs "No action", billing untouched:
gcloud pubsub topics publish stop-billing \
  --message='{"costAmount":1,"budgetAmount":999}'

# Real run — over budget, DISABLES billing on the project:
gcloud pubsub topics publish stop-billing \
  --message='{"costAmount":999,"budgetAmount":1}'

# Re-enable afterwards:
gcloud billing projects link "$PROJECT_ID" --billing-account="$BILLING_ACCOUNT_ID"
```
