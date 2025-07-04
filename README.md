# DnHRegistrySynchronizer
A test project to synchronize select Helm and Docker registries from public ones - to private ones.

## running project

local registry
```
docker compose --profile local-registry up -d
```

tools
```
docker compose --profile tools<nr> up -d
```

shut down
```
docker compose --profile local-registry --profile tools down
```

## some scripts for later / script history

```
helm create hello-world-h
```

start docker and kubernetes

```
docker build -t hello-world-d -f hello-world-d/Dockerfile .
docker run --rm hello-world-d
```

```
helm upgrade --install hello-world-h ./hello-world-h
kubectl logs deployment/hello-world-h
```

shut down everything \

```
helm uninstall hello-world-h
kubectl delete pods --all
kubectl delete all --all

docker image prune -a
docker container prune
docker volume prune

verify:

kubectl config get-contexts
kubectl config current-context
```

# Project Completion Checklist

## ...
- [ ] Clone the repository
- [ ] Install prerequisites: Docker, Helm, Azure CLI, Skopeo/Crane / etc
- [ ] Authenticate with Azure using `scripts/auth-azure.sh`

## Configuration
- [ ] Define images and charts in `config/sync-config.yaml`
- [ ] Add public Docker images for testing (e.g., Alpine, NGINX)
- [ ] Add Helm charts for testing (optional)

## Synchronization, will likely switch to Go/Python
- [ ] Implement `scripts/sync-images.sh` using Skopeo / Crane / etc
- [ ] Implement `scripts/sync-helm.sh` using Helm CLI / chart-syncer / etc
- [ ] Test manual sync locally

## Deployment
- [ ] Build and tag Docker example (`hello-world-d`)
- [ ] Deploy Helm chart (`hello-world-h`)
- [ ] Automate with GitHub Actions or Azure Pipelines

## Testing
- [ ] Verify images exist in ACR
- [ ] Verify Helm chart is deployable from ACR