# ghactions-gcloud-art-registry

Repository for testing CI/CD for deployment of docker image to artifact registry on google cloud using official gcp actions.

## Instructions for deployment on GCP with custom script

1. **Clone your repository**
   ```bash
   git clone https://github.com/ezemriv/your-repo-name.git
   cd your-repo-name
   ```

2. **Make the script executable**
   ```bash
   chmod +x deploy-gcp-scheduled-job.sh
   ```

3. **Export the project number and run deployment**
   ```bash
   export PROJECT_NUMBER=$(gcloud projects describe $(grep PROJECT_ID config.env | cut -d'=' -f2) --format="value(projectNumber)") && ./deploy-gcp-scheduled-job.sh
   ```

4. **Verify deployment**
   ```bash
   # Test scheduler manually
   gcloud scheduler jobs run logger-job-scheduler --location=europe-west1

   # Check logs
   gcloud logging read 'resource.type="cloud_run_job"' --limit=10
   ```

## Build and run locally using
```bash

docker build -t flask-cloudrun .

docker run -e APP_TITLE="My Local Flask App with custom env" -p 8080:8080 flask-cloudrun
```

---
# OLD

# GCP Project Setup for Cloud Run Job Deployment (POC)

This guide documents the setup of a new GCP project for deploying containerized jobs using GitHub Actions and Cloud Run. It is tailored for the `deploy-playground` project but can be reused for future production setups.

> ✅ **Recommended Environment:** Use [Google Cloud Shell](https://shell.cloud.google.com/) for all commands. It ships with the Google Cloud SDK, Docker, and your account already authenticated. When working on your local machine you’ll need to install & authenticate `gcloud` first.

---

## 1 · Set the Active Project

```bash
PROJECT_ID="deploy-playground"
gcloud config set project $PROJECT_ID
```

## 2 · Authenticate (local only)

```bash
# Skip this in Cloud Shell
gcloud auth login
```

## 3 · Enable Required APIs

We enable the core services needed for container deployment **and** BigQuery, so the project is ready if you decide to persist data later (enabling the API itself is free until you store/query).

```bash
gcloud services enable \
  artifactregistry.googleapis.com \
  run.googleapis.com \
  cloudscheduler.googleapis.com \
  iam.googleapis.com \
  bigquery.googleapis.com \
  bigquerystorage.googleapis.com
```

(Optional) If you later move your CI build into Google Cloud you may also want **Cloud Build**:

```bash
# gcloud services enable cloudbuild.googleapis.com
```

## 4 · Create Artifact Registry (Docker)

```bash
REGION="europe-southwest1"
REPO_NAME="tradelab"
gcloud artifacts repositories create $REPO_NAME \
  --repository-format=docker \
  --location=$REGION \
  --description="Docker repo for POC deployments"
```

## 5 · Create Service Accounts (Minimal Permissions)

### 5.1 Cloud Run Job Service Account (runtime)

Our hello‑world job only prints a message, so **no extra roles** are required right now. However, to allow this service account to execute Cloud Run Jobs and be invoked by Cloud Scheduler, assign minimal permissions:

```bash
SERVICE_ACCOUNT="ingest-job-sa"
gcloud iam service-accounts create $SERVICE_ACCOUNT \
  --description="SA for running Cloud Run Jobs" \
  --display-name="Ingest Job SA"

# Allow this SA to run jobs (required for manual or scheduler-triggered executions)
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SERVICE_ACCOUNT@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/run.invoker"
```

You can also reuse this SA for Cloud Scheduler's OIDC identity. If doing so, ensure Cloud Scheduler is authorized to impersonate it when calling the job.

### 5.2 GitHub Actions Push Service Account (CI)

GitHub Actions needs to push the image; grant the minimum role for Artifact Registry.

```bash
CI_SA="ci-image-push-sa"
gcloud iam service-accounts create $CI_SA \
  --description="SA for GitHub Actions to push images" \
  --display-name="CI Image Push SA"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$CI_SA@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.writer"
```

Use **Workload Identity Federation** or a short‑lived key for GitHub Actions—*avoid long‑lived JSON keys*.

---

## 6 · Next Steps

Your project can now:

1. Accept Docker images pushed from GitHub Actions.
2. Deploy Cloud Run Jobs.
3. Schedule those jobs with Cloud Scheduler.

### Step 3: Grant IAM Binding to Allow GitHub to Impersonate Service Account

```bash
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")

# Bind GitHub OIDC identity to impersonate CI SA
gcloud iam service-accounts add-iam-policy-binding ci-image-push-sa@$PROJECT_ID.iam.gserviceaccount.com \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/github-pool/attribute.repository/ezemriv/ghactions-gcloud-art-registry"
```

### Step 4: Add GitHub Secrets

In your GitHub repository:

* Go to Settings → Secrets → Actions
* Add these:

```
Name: WIF_PROVIDER
Value: projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/github-pool/providers/github-provider

Name: WIF_SERVICE_ACCOUNT
Value: ci-image-push-sa@$PROJECT_ID.iam.gserviceaccount.com
```

Now you can push from GitHub Actions to Artifact Registry securely.

Proceed to the next step: Flask app scaffold and GitHub Actions CI workflow.

---

## 6.1 · Configure Workload Identity Federation (WIF) for GitHub Actions

To let GitHub Actions push to Artifact Registry without using service account keys, configure Workload Identity Federation with GitHub OIDC.

To let GitHub Actions push to Artifact Registry without using service account keys, configure Workload Identity Federation with GitHub OIDC.

### Step 1: Create a Workload Identity Pool

```bash
gcloud iam workload-identity-pools create "github-pool" \
  --location="global" \
  --display-name="GitHub Actions Pool"
```

### Step 2: Create a GitHub OIDC Provider inside that Pool

Replace the `attribute-condition` with your exact GitHub repo:

```bash
gcloud iam workload-identity-pools providers create-oidc "github-provider" \
  --location="global" \
  --workload-identity-pool="github-pool" \
  --display-name="GitHub OIDC Provider" \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
  --attribute-condition="attribute.repository == 'ezemriv/ghactions-gcloud-art-registry'"
```

> This will allow GitHub Actions workflows in that repo to impersonate a GCP service account securely.
> Your project can now:

1. Accept Docker images pushed from GitHub Actions.
2. Deploy Cloud Run Jobs.
3. Schedule those jobs with Cloud Scheduler.

Proceed to the Flask “Hello World” app, Dockerfile, and the GitHub Actions workflow.

---

## 7 · Build and Test Flask App Locally

We'll now scaffold and test a minimal Flask app locally before deploying.

### 7.1 Create Project Files

Directory structure:

```bash
deploy-playground/
├── app.py
├── Dockerfile
├── requirements.txt
```

#### `app.py`

```python
import os
from flask import Flask

app = Flask(__name__)
title = os.getenv("APP_TITLE", "Default Title")

@app.route("/")
def hello():
    return f"<h1>{title}</h1><p>Hello from Cloud Run!</p>"

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
```

#### `requirements.txt`

```
flask
```

#### `Dockerfile`

```Dockerfile
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
CMD ["python", "app.py"]
```

### 7.2 Build Docker Image Locally

```bash
docker build -t flask-hello-world .
```

### 7.3 Run the Container Locally

```bash
docker run -e APP_TITLE="My Local Flask App" -p 8080:8080 flask-hello-world
```

Then open your browser and visit: [http://localhost:8080](http://localhost:8080)

---

## 8 · GitHub Actions Workflow to Build and Push

Create a GitHub Actions workflow file at `.github/workflows/docker-build.yml`:

```yaml
name: Build & Push to Artifact Registry

on:
  push:
    branches: [main]

env:
  PROJECT_ID: deploy-playground
  GAR_LOCATION: europe-southwest1
  REPOSITORY: tradelab
  IMAGE: flask-cloudrun

jobs:
  build:
    runs-on: ubuntu-latest

    permissions:
      contents: read
      id-token: write  # Required for OIDC

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Authenticate to Google Cloud
        uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: ${{ secrets.WIF_PROVIDER }}
          service_account: ${{ secrets.WIF_SERVICE_ACCOUNT }}

      - name: Configure Docker for Artifact Registry
        run: gcloud auth configure-docker $GAR_LOCATION-docker.pkg.dev

      - name: Build Docker image
        run: | SEE REALL WORKFLOW WITH VERSION::LATEST TAGS
```

Once pushed, GitHub Actions will build and publish your container image.

---

# 9. Cloud Run Job Scheduling Tutorial

## 1. Deploy Cloud Run Job

```bash
gcloud run jobs deploy logger-job \
  --project=deploy-playground \
  --region=europe-southwest1 \
  --image=europe-southwest1-docker.pkg.dev/deploy-playground/tradelab/flask-cloudrun:0.2.0 \
  --service-account=demoapp-job-sa@deploy-playground.iam.gserviceaccount.com \
  --quiet
```

### Key Parameters:
- **`--project`**: Your GCP project ID
- **`--region`**: Where to deploy the Cloud Run job
- **`--image`**: Full path to your container image in Artifact Registry
- **`--service-account`**: Service account for the job execution (needs appropriate permissions)
- **`--quiet`**: Suppresses confirmation prompts

## 2. Create Cloud Scheduler

```bash
gcloud scheduler jobs create http logger-job-scheduler \
  --project=deploy-playground \
  --location=europe-west1 \
  --schedule="* * * * *" \
  --uri="https://europe-southwest1-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/deploy-playground/jobs/logger-job:run" \
  --http-method=POST \
  --oauth-service-account-email=demoapp-job-sa@deploy-playground.iam.gserviceaccount.com \
  --headers="Content-Type=application/json"
```

### Key Parameters:
- **`--location`**: Cloud Scheduler region (use `europe-west1` since Cloud Scheduler is not available in `europe-southwest1`)
- **`--schedule`**: Cron expression (`"* * * * *"` = every minute)
- **`--uri`**: Cloud Run job execution endpoint (note: uses `europe-southwest1` in URI even though scheduler is in `europe-west1`)
- **`--oauth-service-account-email`**: Service account for authentication
- **`--headers`**: HTTP headers for the request

## Important Notes:
- **Region Mismatch**: Cloud Scheduler may not be available in all regions where Cloud Run is available
- **Service Account**: Must have `roles/run.invoker` permission
- **Cron Schedule**: Use standard cron format (minute hour day month day-of-week)

## Verification:
```bash
# Test scheduler manually
gcloud scheduler jobs run logger-job-scheduler --location=europe-west1

# Check scheduler status
gcloud scheduler jobs list --location=europe-west1
```
