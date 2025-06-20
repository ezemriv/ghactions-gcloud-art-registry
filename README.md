# ghactions-gcloud-art-registry
Repository for testing CI/CD for deployment of docker image to artifact registry on google cloud using official gcp actions

## Build and run locally using
```bash

docker build -t flask-cloudrun .

docker run -e APP_TITLE="My Local Flask App with custom env" -p 8080:8080 flask-cloudrun
````

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

Proceed to the Flask “Hello World” app, Dockerfile, and the GitHub Actions workflow.
