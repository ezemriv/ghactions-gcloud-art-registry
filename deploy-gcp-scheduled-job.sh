#!/bin/bash

# Load configuration from shared file
if [ -f "config.env" ]; then
    echo "📄 Loading configuration from config.env..."
    set -a  # automatically export all variables
    source config.env
    set +a
else
    echo "❌ config.env file not found!"
    exit 1
fi

# =============================================================================
# DERIVED VARIABLES - DO NOT MODIFY
# =============================================================================

FULL_IMAGE="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY}/${IMAGE_NAME}:${IMAGE_TAG}"
JOB_SA_EMAIL="${JOB_SA}@${PROJECT_ID}.iam.gserviceaccount.com"
CI_SA_EMAIL="${CI_SA}@${PROJECT_ID}.iam.gservaceaccount.com"

# =============================================================================
# DEPLOYMENT SCRIPT
# =============================================================================

echo "🚀 Starting deployment for project: $PROJECT_ID"
echo "📦 Image: $FULL_IMAGE"
echo ""

# Set the active project
gcloud config set project $PROJECT_ID

echo "1️⃣ Enabling required APIs..."
gcloud services enable \
  artifactregistry.googleapis.com \
  run.googleapis.com \
  cloudscheduler.googleapis.com \
  iam.googleapis.com \
  bigquery.googleapis.com \
  bigquerystorage.googleapis.com

echo "2️⃣ Creating Artifact Registry repository..."
# Check if repository exists first
if gcloud artifacts repositories describe $REPOSITORY --location=$REGION &>/dev/null; then
  echo "   ✅ Repository $REPOSITORY already exists"
else
  gcloud artifacts repositories create $REPOSITORY \
    --repository-format=docker \
    --location=$REGION \
    --description="Docker repo for POC deployments"
  echo "   ✅ Repository $REPOSITORY created"
fi

echo "3️⃣ Creating service accounts..."
# Job execution service account
if gcloud iam service-accounts describe $JOB_SA_EMAIL &>/dev/null; then
  echo "   ✅ Service account $JOB_SA already exists"
else
  gcloud iam service-accounts create $JOB_SA \
    --description="SA for running Cloud Run Jobs" \
    --display-name="Job Execution SA"
  echo "   ✅ Service account $JOB_SA created"
fi

# CI service account
if gcloud iam service-accounts describe $CI_SA_EMAIL &>/dev/null; then
  echo "   ✅ CI service account $CI_SA already exists"
else
  gcloud iam service-accounts create $CI_SA \
    --description="SA for GitHub Actions to push images" \
    --display-name="CI Image Push SA"
  echo "   ✅ CI service account $CI_SA created"
fi

echo "4️⃣ Setting up IAM permissions..."
# Job execution permissions
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$JOB_SA_EMAIL" \
  --role="roles/run.invoker" \
  --quiet

# CI permissions
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$CI_SA_EMAIL" \
  --role="roles/artifactregistry.writer" \
  --quiet

echo "5️⃣ Setting up Workload Identity for GitHub Actions..."
# Check if workload identity pool exists
if gcloud iam workload-identity-pools describe github-pool --location=global &>/dev/null; then
  echo "   ✅ Workload identity pool already exists"
else
  gcloud iam workload-identity-pools create "github-pool" \
    --location="global" \
    --display-name="GitHub Actions Pool"
  echo "   ✅ Workload identity pool created"
fi

# Check if provider exists
if gcloud iam workload-identity-pools providers describe github-provider --location=global --workload-identity-pool=github-pool &>/dev/null; then
  echo "   ✅ Workload identity provider already exists"
else
  gcloud iam workload-identity-pools providers create-oidc "github-provider" \
    --location="global" \
    --workload-identity-pool="github-pool" \
    --display-name="GitHub OIDC Provider" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
    --attribute-condition="attribute.repository == '$GITHUB_REPO'"
    # --attribute-condition="assertion.repository_owner == 'ezemriv'"
    # --attribute-condition="assertion.repository_owner == 'ezemriv' || assertion.repository_owner == 'emr-tradelab'"
    # --attribute-condition="assertion.repository_owner in ['ezemriv', 'emr-tradelab']"
  echo "   ✅ Workload identity provider created"
fi

# Bind service account to workload identity
gcloud iam service-accounts add-iam-policy-binding $CI_SA_EMAIL \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/github-pool/attribute.repository/$GITHUB_REPO" \
  --quiet

echo "6️⃣ Deploying Cloud Run Job..."
gcloud run jobs deploy $JOB_NAME \
  --project=$PROJECT_ID \
  --region=$REGION \
  --image=$FULL_IMAGE \
  --service-account=$JOB_SA_EMAIL \
  --quiet

echo "7️⃣ Creating Cloud Scheduler..."
# Delete existing scheduler if it exists
if gcloud scheduler jobs describe $SCHEDULER_NAME --location=$SCHEDULER_REGION &>/dev/null; then
  echo "   🗑️ Deleting existing scheduler..."
  gcloud scheduler jobs delete $SCHEDULER_NAME --location=$SCHEDULER_REGION --quiet
fi

gcloud scheduler jobs create http $SCHEDULER_NAME \
  --project=$PROJECT_ID \
  --location=$SCHEDULER_REGION \
  --schedule="$SCHEDULE" \
  --uri="https://${REGION}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${PROJECT_ID}/jobs/${JOB_NAME}:run" \
  --http-method=POST \
  --oauth-service-account-email=$JOB_SA_EMAIL \
  --headers="Content-Type=application/json"

echo ""
echo "✅ Deployment completed successfully!"
echo ""
echo "📋 Summary:"
echo "   Project: $PROJECT_ID"
echo "   Cloud Run Job: $JOB_NAME (region: $REGION)"
echo "   Scheduler: $SCHEDULER_NAME (region: $SCHEDULER_REGION)"
echo "   Schedule: $SCHEDULE"
echo "   Image: $FULL_IMAGE"
echo ""
echo "🧪 Test the scheduler manually:"
echo "   gcloud scheduler jobs run $SCHEDULER_NAME --location=$SCHEDULER_REGION"
echo ""
echo "📊 View logs:"
echo "   gcloud logging read 'resource.type=\"cloud_run_job\"' --limit=50"
