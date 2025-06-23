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
   export PROJECT_NUMBER=$(gcloud projects describe $(grep PROJECT_ID config.env | cut -d'=' -f2 | tr -d '"') --format="value(projectNumber)") && ./deploy-gcp-scheduled-job.sh
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
