# Kubernetes Deployment Guide — `kubernetes/`

> **Who is this for?** Anyone new to Kubernetes who wants to understand how this e-commerce app is deployed on EKS, what each manifest does, and in what order to apply them.

---

## Table of Contents

1. [What does this folder do?](#1-what-does-this-folder-do)
2. [Files in this folder](#2-files-in-this-folder)
3. [Prerequisites](#3-prerequisites)
4. [Big-picture architecture](#4-big-picture-architecture)
5. [Apply order — step by step](#5-apply-order--step-by-step)
   - [Step 1 — Namespace](#step-1--namespace-01-namespaceyml)
   - [Step 2 — MongoDB storage](#step-2--mongodb-storage-02-mongodb-pvyml-03-mongodb-pvcyml)
   - [Step 3 — App configuration](#step-3--app-configuration-04-configmapyml-05-secretsyml)
   - [Step 4 — MongoDB workload](#step-4--mongodb-workload-06-mongodb-serviceyml-07-mongodb-statefulsetyml)
   - [Step 5 — Next.js application](#step-5--nextjs-application-08-easyshop-deploymentyml-09-easyshop-serviceyml)
   - [Step 6 — External access](#step-6--external-access-10-ingressyml)
   - [Step 7 — Autoscaling](#step-7--autoscaling-11-hpayml)
   - [Step 8 — Database migration job](#step-8--database-migration-job-12-migration-jobyml)
6. [How traffic reaches the app](#6-how-traffic-reaches-the-app)
7. [How CI/CD updates these manifests](#7-how-cicd-updates-these-manifests)
8. [Deploying with kubectl](#8-deploying-with-kubectl)
9. [Verifying the deployment](#9-verifying-the-deployment)
10. [Tearing down](#10-tearing-down)
11. [Quick reference diagram](#11-quick-reference-diagram)

---

## 1. What does this folder do?

The `kubernetes/` folder contains **YAML manifests** that describe how the EasyShop e-commerce app runs on a Kubernetes cluster (in this project, **Amazon EKS** — `Lucifer-eks-cluster`).

Everything lives in one namespace: **`easyshop`**.

| Layer | What runs there |
|-------|-----------------|
| **Data** | MongoDB (StatefulSet + persistent volume) |
| **App** | Next.js frontend/API (Deployment, 2+ replicas) |
| **Networking** | Services, Ingress, TLS |
| **Ops** | HPA (autoscaling), one-off migration Job |

Manifests are numbered `01`–`12` so you apply them in a logical order: namespace → storage → config → database → app → ingress → scaling → migration.

---

## 2. Files in this folder

```
kubernetes/
├── 01-namespace.yml              ← Isolated namespace: easyshop
├── 02-mongodb-pv.yml             ← Cluster storage volume for MongoDB
├── 03-mongodb-pvc.yml            ← Claims storage inside the namespace
├── 04-configmap.yml              ← Non-secret app config (URLs, env)
├── 05-secrets.yml                ← Sensitive values (JWT, NextAuth)
├── 06-mongodb-service.yml        ← Internal DNS for MongoDB
├── 07-mongodb-statefulset.yml    ← MongoDB pod(s)
├── 08-easyshop-deployment.yml    ← Next.js app pods (main workload)
├── 09-easyshop-service.yml       ← Exposes app inside the cluster
├── 10-ingress.yml                ← HTTPS + domain routing from internet
├── 11-hpa.yml                    ← CPU-based autoscaling (2–5 pods)
├── 12-migration-job.yml          ← One-time DB seed/migration
└── K8s.readme.md                 ← This guide
```

All namespaced resources use **`namespace: easyshop`**, matching `01-namespace.yml`.

---

## 3. Prerequisites

Before applying these manifests:

1. **EKS cluster** running (see `terraform/eks.README.md`)
2. **`kubectl` configured** for the cluster:
   ```bash
   aws eks update-kubeconfig --region eu-west-1 --name Lucifer-eks-cluster
   ```
3. **Cluster add-ons** (from project README):
   - **NGINX Ingress Controller** (Helm) — required for `10-ingress.yml`
   - **cert-manager** (Helm) — for TLS certificates on Ingress
4. **Docker images** built and pushed (Jenkins pipeline or manual):
   - App: `trainwithshubham/easyshop-app:<tag>` (update to your Docker Hub user in `08`)
   - Migration: `trainwithshubham/easyshop-migration:<tag>` (update in `12`)
5. **DNS** pointing your domain (e.g. `easyshop.letsdeployit.com`) to the Ingress load balancer

---

## 4. Big-picture architecture

```
Internet
    │
    ▼
┌─────────────────────────────────────────────────────────────┐
│  Ingress (10) — easyshop.letsdeployit.com + TLS             │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  Service easyshop-service (09) — port 80 → app :3000        │
└──────────────────────────┬──────────────────────────────────┘
                           │
          ┌────────────────┼────────────────┐
          ▼                ▼                ▼
   ┌────────────┐  ┌────────────┐  ┌────────────┐
   │ easyshop   │  │ easyshop   │  │ easyshop   │  Deployment (08)
   │ pod        │  │ pod        │  │ pod        │  HPA scales 2–5
   └─────┬──────┘  └─────┬──────┘  └─────┬──────┘
         │               │               │
         └───────────────┼───────────────┘
                         │ MONGODB_URI
                         ▼
              ┌─────────────────────┐
              │ mongodb-service (06)│
              └──────────┬──────────┘
                         ▼
              ┌─────────────────────┐
              │ StatefulSet (07)    │
              │ mongo:latest        │
              │ + PVC (03) → PV (02)│
              └─────────────────────┘

ConfigMap (04) + Secret (05) ──env──► App pods (08)
Migration Job (12) ──one-shot──► MongoDB (seed data)
```

---

## 5. Apply order — step by step

Apply files in numeric order. Each step builds on the previous one.

```bash
kubectl apply -f kubernetes/01-namespace.yml
kubectl apply -f kubernetes/02-mongodb-pv.yml
# ... continue through 12
```

Or apply the whole folder at once (Kubernetes sorts by dependency where possible):

```bash
kubectl apply -f kubernetes/
```

---

### Step 1 — Namespace (`01-namespace.yml`)

```yaml
kind: Namespace
metadata:
  name: easyshop
```

**What it does:** Creates a logical boundary for all EasyShop resources. Namespaces isolate RBAC, quotas, and DNS (`<service>.easyshop.svc.cluster.local`).

**Why first:** Every other namespaced object references `easyshop`.

---

### Step 2 — MongoDB storage (`02-mongodb-pv.yml`, `03-mongodb-pvc.yml`)

| File | Kind | Purpose |
|------|------|---------|
| `02-mongodb-pv.yml` | PersistentVolume | 5 GiB volume on node path `/data/mongodb` (hostPath) |
| `03-mongodb-pvc.yml` | PersistentVolumeClaim | Binds the PV for use in namespace `easyshop` |

**Flow:** PVC requests storage → Kubernetes binds it to the matching PV → StatefulSet mounts it at `/data/db`.

**Note:** `hostPath` suits dev/single-node setups. Production often uses EBS volumes via a StorageClass instead.

---

### Step 3 — App configuration (`04-configmap.yml`, `05-secrets.yml`)

| File | Kind | Holds |
|------|------|-------|
| `04-configmap.yml` | ConfigMap `easyshop-config` | `MONGODB_URI`, `NODE_ENV`, `NEXT_PUBLIC_API_URL`, `NEXTAUTH_URL`, and related keys |
| `05-secrets.yml` | Secret `easyshop-secrets` | `JWT_SECRET`, `NEXTAUTH_SECRET` (override defaults before production) |

**What it does:** Injects environment variables into app containers without baking secrets into the Docker image.

**Important:** Replace placeholder secrets in `05-secrets.yml` before going live. Prefer Sealed Secrets or AWS Secrets Manager for production.

---

### Step 4 — MongoDB workload (`06-mongodb-service.yml`, `07-mongodb-statefulset.yml`)

| File | Kind | Purpose |
|------|------|---------|
| `06-mongodb-service.yml` | Service `mongodb-service` | Stable DNS name + port 27017 inside the cluster |
| `07-mongodb-statefulset.yml` | StatefulSet `mongodb` | Runs `mongo:latest`, 1 replica, mounts `mongodb-pvc` |

**Connection string used by the app:**

```text
mongodb://mongodb-service:27017/easyshop
```

`mongodb-service` resolves inside the `easyshop` namespace only.

---

### Step 5 — Next.js application (`08-easyshop-deployment.yml`, `09-easyshop-service.yml`)

**Deployment (`08`):**

| Setting | Value | Meaning |
|---------|-------|---------|
| `replicas` | 2 | Two app pods for availability |
| `image` | `trainwithshubham/easyshop-app:1` | Docker image (Jenkins updates the tag) |
| `containerPort` | 3000 | Next.js listens here |
| Probes | startup / readiness / liveness | HTTP GET `/` on port 3000 |
| `envFrom` | ConfigMap + Secret | Loads `04` and `05` |

**Service (`09`):**

| Setting | Value | Meaning |
|---------|-------|---------|
| `type` | NodePort | Exposes app on each node (also used behind Ingress) |
| `port` / `targetPort` | 80 → 3000 | Service port 80 forwards to container 3000 |
| `nodePort` | 30000 | Optional direct node access for debugging |

---

### Step 6 — External access (`10-ingress.yml`)

**What it does:** Routes public HTTPS traffic from `easyshop.letsdeployit.com` to `easyshop-service:80`.

| Annotation | Purpose |
|------------|---------|
| `kubernetes.io/ingress.class: nginx` | Use NGINX Ingress Controller |
| `nginx.ingress.kubernetes.io/ssl-redirect: "true"` | Force HTTPS |
| `nginx.ingress.kubernetes.io/proxy-body-size: "50m"` | Allow larger uploads |
| TLS `secretName: easyshop-tls-secret` | TLS cert (often issued by cert-manager) |

**Requires:** NGINX Ingress installed on the cluster and DNS pointing to the Ingress load balancer.

---

### Step 7 — Autoscaling (`11-hpa.yml`)

```yaml
kind: HorizontalPodAutoscaler
minReplicas: 2
maxReplicas: 5
target: CPU 70%
```

**What it does:** When average CPU across `easyshop` pods exceeds 70%, Kubernetes adds pods (up to 5). When load drops, it scales back down (minimum 2).

**Requires:** Metrics Server installed on the cluster.

---

### Step 8 — Database migration job (`12-migration-job.yml`)

```yaml
kind: Job
image: trainwithshubham/easyshop-migration:1
```

**What it does:** Runs **once** to seed/migrate MongoDB data (`scripts/migrate-data.ts` in the migration image). Uses the same `MONGODB_URI` as the app.

**When to run:** After MongoDB is up and before or after the app Deployment — typically once per environment or after schema changes.

```bash
kubectl apply -f kubernetes/12-migration-job.yml
kubectl logs -n easyshop job/db-migration
```

To re-run, delete the job first: `kubectl delete job db-migration -n easyshop`

---

## 6. How traffic reaches the app

```
User browser
    │  https://easyshop.letsdeployit.com
    ▼
AWS Load Balancer (NGINX Ingress Controller)
    │
    ▼
Ingress easyshop-ingress (10)
    │  TLS termination (cert-manager / easyshop-tls-secret)
    ▼
Service easyshop-service (09) :80
    │
    ▼
Deployment easyshop (08) pods :3000
    │
    ▼
Service mongodb-service (06) :27017
    │
    ▼
StatefulSet mongodb (07)
```

---

## 7. How CI/CD updates these manifests

The **Jenkins pipeline** (`Jenkinsfile`) builds Docker images and updates image tags in Git:

| Manifest | Updated field |
|----------|----------------|
| `08-easyshop-deployment.yml` | `image: <user>/e-commerce-app:<BUILD_NUMBER>` |
| `12-migration-job.yml` | `image: <user>/e-commerce-app-migration:<BUILD_NUMBER>` |

After Jenkins commits and pushes, **Argo CD** (if configured per project README) syncs the cluster to match the repo — new image tags roll out to pods without manual `kubectl apply`.

**GitOps flow:**

```
Code push → Jenkins build → Docker push → Update 08 & 12 in Git → Argo CD sync → Rolling update on EKS
```

---

## 8. Deploying with kubectl

From the repository root, with `kubectl` pointed at `Lucifer-eks-cluster`:

```bash
# Apply everything
kubectl apply -f kubernetes/

# Or step by step
for f in kubernetes/0*.yml kubernetes/1*.yml; do
  kubectl apply -f "$f"
done
```

**Suggested first-time sequence:**

1. `01` → `07` — namespace, storage, config, MongoDB
2. Wait for MongoDB: `kubectl get pods -n easyshop -w`
3. `12` — migration job (optional, for seed data)
4. `08` → `11` — app, service, ingress, HPA

---

## 9. Verifying the deployment

```bash
# Namespace and all resources
kubectl get all -n easyshop

# Pod status
kubectl get pods -n easyshop

# App logs
kubectl logs -n easyshop -l app=easyshop --tail=50

# Ingress and external URL
kubectl get ingress -n easyshop

# HPA status
kubectl get hpa -n easyshop

# Migration job
kubectl get jobs -n easyshop
```

**Healthy state:**

| Resource | Expected |
|----------|----------|
| `mongodb` pod | `Running` |
| `easyshop` pods | `Running` (2+, ready) |
| `easyshop-ingress` | Address / hostname assigned |
| `easyshop-hpa` | Targets Deployment `easyshop` |
| `db-migration` job | `Complete` (after first run) |

---

## 10. Tearing down

Remove all EasyShop resources:

```bash
kubectl delete namespace easyshop
```

Remove the cluster-scoped PV if you no longer need the data:

```bash
kubectl delete pv mongodb-pv
```

> Deleting the namespace removes PVCs, pods, services, ingress, and jobs inside `easyshop`. The PV may remain if `persistentVolumeReclaimPolicy: Retain`.

---

## 11. Quick reference diagram

```
01-namespace.yml          →  easyshop namespace
02-mongodb-pv.yml         →  mongodb-pv (cluster)
03-mongodb-pvc.yml        →  mongodb-pvc (namespace)
04-configmap.yml          →  easyshop-config
05-secrets.yml            →  easyshop-secrets
06-mongodb-service.yml    →  mongodb-service:27017
07-mongodb-statefulset.yml→  mongodb pod + volume
08-easyshop-deployment.yml→  easyshop app (×2, HPA → ×5)
09-easyshop-service.yml   →  easyshop-service:80
10-ingress.yml            →  HTTPS + domain
11-hpa.yml                →  CPU autoscale 2–5
12-migration-job.yml      →  DB seed (one-shot)
```

---

*Read manifests in numeric order (`01` through `12`). Each file adds one piece until the full e-commerce stack is running on EKS.*
