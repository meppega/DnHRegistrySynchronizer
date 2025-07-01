# DnHRegistrySynchronizer
A test project to synchronize select Helm and Docker registries from public ones - to private ones.

## some scripts for later / script history

```
helm create hello-world-h
```

start docker and kubernetes

```
kubectl config current-context
docker build -t hello-world-d -f Dockerfile .
docker run --rm hello-world-d
```

```
helm upgrade --install hello-world-h ./hello-world-h
kubectl logs deployment/hello-world-h
```

shut down everything
'''

helm uninstall hello-world-h
kubectl delete pods --all
kubectl delete all --all


docker image prune -a
docker container prune
docker volume prune


verify:

kubectl config get-contexts
kubectl config current-context

'''
