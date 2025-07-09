# helm repo add bitnami https://charts.bitnami.com/bitnami
# helm repo update
# helm pull bitnami/nginx --version 15.14.0
# helm push nginx-15.14.0.tgz oci://localhost:5000/charts/

# # test
# helm pull oci://localhost:5000/charts/nginx
# helm pull oci://localhost:5000/charts/nginx --version 15.14.0