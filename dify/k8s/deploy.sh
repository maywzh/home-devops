#!/bin/bash

# Dify Kubernetes Deployment Script
# This script deploys Dify services to a Kubernetes cluster in the correct order

set -e  # Exit immediately if a command exits with a non-zero status

echo "Starting Dify Kubernetes deployment..."

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null
then
    echo "kubectl is not installed. Please install kubectl and try again."
    exit 1
fi

# Set the Kubernetes context (replace with your actual context)
echo "Setting Kubernetes context..."
kubectl config use-context $(kubectl config current-context)

# Create namespace if it doesn't exist
echo "Creating namespace 'dify' if it doesn't exist..."
kubectl create namespace dify --dry-run=client -o yaml | kubectl apply -f -

# Deploy ConfigMap
echo "Deploying ConfigMap..."
kubectl apply -f 01-configmap.yaml

# Deploy Secrets
echo "Deploying Secrets..."
kubectl apply -f 02-secrets.yaml

# Deploy PersistentVolumeClaims for storage
echo "Deploying storage resources..."
kubectl apply -f 03-pvc.yaml
kubectl apply -f 05-plugin-pvc.yaml

# Deploy SSRF Proxy ConfigMap
echo "Deploying SSRF Proxy ConfigMap..."
kubectl apply -f 04-ssrf-proxy-configmap.yaml

# Deploy API service
echo "Deploying API service..."
kubectl apply -f 10-api-deployment.yaml
kubectl apply -f 11-api-service.yaml

# Deploy Worker service
echo "Deploying Worker service..."
kubectl apply -f 20-worker-deployment.yaml

# Deploy Web service
echo "Deploying Web service..."
kubectl apply -f 30-web-deployment.yaml
kubectl apply -f 31-web-service.yaml

# Deploy Sandbox service
echo "Deploying Sandbox service..."
kubectl apply -f 12-sandbox-deployment.yaml

# Deploy Plugin Daemon service
echo "Deploying Plugin Daemon service..."
kubectl apply -f 13-plugin-daemon-deployment.yaml

# Deploy SSRF Proxy service
echo "Deploying SSRF Proxy service..."
kubectl apply -f 14-ssrf-proxy-deployment.yaml

# Deploy Ingresses (web and api hosts)
echo "Deploying Ingresses..."
kubectl apply -f 40-web-ingress.yaml
kubectl apply -f 41-api-ingress.yaml

echo "Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod -l app=dify-api -n dify --timeout=300s
kubectl wait --for=condition=ready pod -l app=dify-worker -n dify --timeout=300s
kubectl wait --for=condition=ready pod -l app=dify-web -n dify --timeout=300s

echo "Deployment completed successfully!"
echo "Web: http://dify.maywzh.com/console"
echo "API: http://dify-api.maywzh.com"
echo "Check the status of your deployment with: kubectl get pods,svc,ingress -n dify"