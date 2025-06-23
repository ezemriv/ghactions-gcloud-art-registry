Go to --> https://github.com/google-github-actions/example-workflows/blob/main/workflows/deploy-cloudrun/cloudrun-docker.yml

```yaml
name: Build and Deploy to Cloud Run

on:
  push:
    branches:
      - $default-branch

env:
  PROJECT_ID: YOUR_PROJECT_ID # TODO: update Google Cloud project id
  GAR_LOCATION: YOUR_GAR_LOCATION # TODO: update Artifact Registry location
  REPOSITORY: YOUR_REPOSITORY_NAME # TODO: update Artifact Registry repository name
  SERVICE: YOUR_SERVICE_NAME # TODO: update Cloud Run service name
  REGION: YOUR_SERVICE_REGION # TODO: update Cloud Run service region

jobs:
  deploy:
    # Add 'id-token' with the intended permissions for workload identity federation
    permissions:
      contents: 'read'
      id-token: 'write'

    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v2

      - name: Google Auth
        id: auth
        uses: 'google-github-actions/auth@v0'
        with:
          token_format: 'access_token'
          workload_identity_provider: '${{ vars.WIF_PROVIDER }}' # e.g. - projects/123456789/locations/global/workloadIdentityPools/my-pool/providers/my-provider
          service_account: '${{ vars.WIF_SERVICE_ACCOUNT }}' # e.g. - my-service-account@my-project.iam.gserviceaccount.com

      # NOTE: Alternative option - authentication via credentials json
      # - name: Google Auth
      #   id: auth
      #   uses: 'google-github-actions/auth@v0'
      #   with:
      #     credentials_json: '${{ secrets.GCP_CREDENTIALS }}'
      #     token_format: 'access_token'

      # BEGIN - Docker auth and build (NOTE: If you already have a container image, these Docker steps can be omitted)

      # Authenticate Docker to Google Cloud Artifact Registry
      - name: Docker Auth
        id: docker-auth
        uses: 'docker/login-action@v1'
        with:
          username: 'oauth2accesstoken'
          password: '${{ steps.auth.outputs.access_token }}'
          registry: '${{ env.GAR_LOCATION }}-docker.pkg.dev'

      # NOTE: Alternative option - authentication via credentials json
      # - name: Docker Auth
      # id: docker-auth
      # uses: 'docker/login-action@v1'
      # with:
      #   registry: ${{ env.GAR_LOCATION }}-docker.pkg.dev
      #   username: _json_key
      #   password: ${{ secrets.GCP_CREDENTIALS }}

      - name: Build and Push Container
        run: |-
          docker build -t "${{ env.GAR_LOCATION }}-docker.pkg.dev/${{ env.PROJECT_ID }}/${{ env.REPOSITORY }}/${{ env.SERVICE }}:${{ github.sha }}" ./
          docker push "${{ env.GAR_LOCATION }}-docker.pkg.dev/${{ env.PROJECT_ID }}/${{ env.REPOSITORY }}/${{ env.SERVICE }}:${{ github.sha }}"

      # END - Docker auth and build

      - name: Deploy to Cloud Run
        id: deploy
        uses: google-github-actions/deploy-cloudrun@v0
        with:
          service: ${{ env.SERVICE }}
          region: ${{ env.REGION }}
          # NOTE: If using a pre-built image, update the image name here
          image: ${{ env.GAR_LOCATION }}-docker.pkg.dev/${{ env.PROJECT_ID }}/${{ env.REPOSITORY }}/${{ env.SERVICE }}:${{ github.sha }}
          # NOTE: You can also set env variables here:
          #  env_vars: |
          #  NODE_ENV=production
          #  TOKEN_EXPIRE=6400

      # If required, use the Cloud Run url output in later steps
      - name: Show Output
        run: echo ${{ steps.deploy.outputs.url }}
```
