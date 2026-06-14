# Deploying a 3-Tier App on Kubernetes (k3s)
### A Complete Beginner's Guide — Watchlist App on AWS EC2

---

> This guide documents exactly what we built, how it works, and why every
> decision was made. Read the flowcharts first, then the practical steps.

---

## PART 1 — HOW EVERYTHING CONNECTS (FLOWCHARTS)

---

### FLOWCHART 1 — Your Physical Setup (What Exists on AWS)

```
                         AWS CLOUD
  ┌─────────────────────────────────────────────────────────────┐
  │                                                             │
  │   ┌─────────────────────────────────────────────────────┐   │
  │   │                  VPC (Private Network)              │   │
  │   │                                                     │   │
  │   │  ┌──────────────────┐                               │   │
  │   │  │  EC2: master-k3s │  IP: 10.0.1.122               │   │
  │   │  │  (t3.small)      │  ← THE BRAIN                  │   │
  │   │  │                  │  Runs: k3s server             │   │
  │   │  │  Does NOT run    │  Accepts: kubectl commands    │   │
  │   │  │  your app pods   │  Decides: which worker runs   │   │
  │   │  └────────┬─────────┘           what                │   │
  │   │           │                                         │   │
  │   │           │ gives orders via private network        │   │
  │   │           │                                         │   │
  │   │    ┌──────┴──────────────────────┐                  │   │
  │   │    │                             │                  │   │
  │   │    ▼                             ▼                  │   │
  │   │  ┌──────────────────┐  ┌──────────────────┐         │   │
  │   │  │ EC2: worker-k3s-1│  │ EC2: worker-k3s-2│         │   │
  │   │  │ IP: 10.0.1.159   │  │ IP: 10.0.1.87    │         │   │
  │   │  │ (t3.small)       │  │ (t3.small)       │         │   │
  │   │  │                  │  │                  │         │   │
  │   │  │ Runs: k3s agent  │  │ Runs: k3s agent  │         │   │
  │   │  │ Runs: your pods  │  │ Runs: your pods  │         │   │
  │   │  └──────────────────┘  └──────────────────┘         │   │
  │   └─────────────────────────────────────────────────────┘   │
  └─────────────────────────────────────────────────────────────┘

  Master = Manager. Workers = Doers.
  You only ever talk to the master. Workers just follow orders.
```

---

### FLOWCHART 2 — What Runs Inside the Cluster (All Pods)

```
  NAMESPACE: watchlist  (a virtual folder inside Kubernetes)
  ┌───────────────────────────────────────────────────────────────────┐
  │                                                                   │
  │   ┌─────────────────────────────────────────────────────────┐     │
  │   │  WORKER NODE 1 (10.0.1.159)                             │     │
  │   │                                                         │     │
  │   │  ┌──────────────────────┐  ┌──────────────────────┐     │     │
  │   │  │ frontend Pod #1      │  │ backend Pod #1        │    │     │
  │   │  │ Nginx on port 80     │  │ Node.js on port 5000  │    │     │
  │   │  │ raj8875/watchlist-   │  │ raj8875/watchlist-    │    │     │
  │   │  │ frontend:latest      │  │ backend:latest        │    │     │
  │   │  └──────────────────────┘  └──────────────────────┘     │     │
  │   └─────────────────────────────────────────────────────────┘     │
  │                                                                   │
  │   ┌─────────────────────────────────────────────────────────┐     │
  │   │  WORKER NODE 2 (10.0.1.87)                              │     │
  │   │                                                         │     │
  │   │  ┌──────────────────────┐  ┌──────────────────────┐     │     │
  │   │  │ frontend Pod #2      │  │ backend Pod #2        │    │     │
  │   │  │ Nginx on port 80     │  │ Node.js on port 5000  │    │     │
  │   │  └──────────────────────┘  └──────────────────────┘     │     │
  │   │                                                         │     │
  │   │  ┌──────────────────────┐                               │     │
  │   │  │ postgres Pod #1      │  ← only 1 replica (must be)   │     │
  │   │  │ Postgres on port 5432│                               │     │
  │   │  │ raj8875/watchlist-   │                               │     │
  │   │  │ db:15-alpine         │                               │     │
  │   │  └──────────┬───────────┘                               │     │
  │   │             │ writes data to                            │     │
  │   │  ┌──────────▼───────────┐                               │     │
  │   │  │ PersistentVolume     │  ← 1GB on worker node's disk  │     │
  │   │  │ /var/lib/postgresql  │    survives pod restarts      │     │
  │   │  └──────────────────────┘                               │     │
  │   └─────────────────────────────────────────────────────────┘     │
  └───────────────────────────────────────────────────────────────────┘

  Total pods: 5
  frontend × 2  |  backend × 2  |  postgres × 1
```

---

### FLOWCHART 3 — Why 2 Replicas? How Does That Work?

```
  WITHOUT REPLICAS (replicas: 1)
  ================================
  User request
      │
      ▼
  [frontend Pod #1]  ← if this pod crashes, app is DOWN
                       user gets error until pod restarts


  WITH REPLICAS (replicas: 2)
  ============================
  User request
      │
      ▼
  [frontend-service]  ← Service load balances between healthy pods
      │
      ├──► [frontend Pod #1 on Worker 1]  ← Pod 1 gets some requests
      │
      └──► [frontend Pod #2 on Worker 2]  ← Pod 2 gets other requests

  If Pod #1 crashes:
      │
      ▼
  [frontend-service]  ← automatically stops sending to crashed pod
      │
      └──► [frontend Pod #2]  ← all traffic goes here, zero downtime
                                 meanwhile master restarts Pod #1


  WHY POSTGRES STAYS AT 1 REPLICA:
  ==================================
  Postgres Pod #1 ──► writes to disk at /var/lib/postgresql/data
  Postgres Pod #2 ──► also writes to SAME disk
                       = DATA CORRUPTION ❌

  Two database processes cannot safely write to the same files.
  Always keep Postgres at 1 replica.
  (Clustered Postgres exists but is advanced — not needed here)
```

---

### FLOWCHART 4 — How the Master Controls Everything

```
  YOU (on your laptop or master SSH session)
      │
      │  kubectl apply -f deployment.yaml
      ▼
  ┌─────────────────────────────────────────┐
  │  MASTER NODE                            │
  │                                         │
  │  API Server (port 6443)                 │
  │  "Got a new deployment request"         │
  │       │                                 │
  │       ▼                                 │
  │  etcd/SQLite (internal database)        │
  │  "Storing desired state:                │
  │   2 frontend pods must run"             │
  │       │                                 │
  │       ▼                                 │
  │  Scheduler                              │
  │  "Worker 1 has space → put pod 1 there" │
  │  "Worker 2 has space → put pod 2 there" │
  │       │                                 │
  │       ▼                                 │
  │  Controller                             │
  │  "Watching... are 2 pods running?       │
  │   Yes ✅. Still watching..."            │
  └──────┬──────────────────────────────────┘
         │ sends pod spec to workers
         │
    ┌────┴────────────────────┐
    │                         │
    ▼                         ▼
  Worker 1                 Worker 2
  kubelet receives order   kubelet receives order
  pulls image from         pulls image from
  DockerHub                DockerHub
  starts container         starts container
  reports back to master   reports back to master

  SELF HEALING:
  =============
  Master checks every few seconds: "Are my 2 pods running?"
  Pod crashes on Worker 1
      │
      ▼
  Master detects: "Only 1 pod running, I want 2"
      │
      ▼
  Master schedules new pod on Worker 1 or Worker 2
      │
      ▼
  New pod starts automatically ← you didn't do anything
```

---

### FLOWCHART 5 — Complete Network Flow (User Request Journey)

```
  USER OPENS BROWSER: http://43.205.215.76:30080
  ================================================

  [User Browser]
       │
       │ HTTP request to Worker public IP on port 30080
       ▼
  ┌─────────────────────────────────────────────────────┐
  │  AWS Security Group                                 │
  │  Port 30080 open ✅ → traffic allowed in           │
  └──────────────────────┬──────────────────────────────┘
                         │
                         ▼
  ┌─────────────────────────────────────────────────────┐
  │  frontend-service (NodePort: 30080)                 │
  │  Type: NodePort                                     │
  │  "I receive traffic on port 30080"                  │
  │  "I load balance to pods with label: app=frontend"  │
  └──────────────┬──────────────────────────────────────┘
                 │
         ┌───────┴───────┐
         │               │
         ▼               ▼
  [frontend Pod #1]  [frontend Pod #2]
  Nginx on port 80   Nginx on port 80
         │
         │ User requests /api/movies
         │ Nginx sees /api/ → proxy to backend
         │ (configured in nginx.conf inside the image)
         ▼
  ┌─────────────────────────────────────────────────────┐
  │  watchlist-backend service (ClusterIP)              │
  │  Type: ClusterIP (NOT reachable from internet)      │
  │  "I receive traffic on port 5000 from inside only"  │
  │  "I route to pods with label: app=backend"          │
  └──────────────┬──────────────────────────────────────┘
                 │
         ┌───────┴───────┐
         │               │
         ▼               ▼
  [backend Pod #1]  [backend Pod #2]
  Node.js port 5000  Node.js port 5000
         │
         │ needs data → connects to postgres
         │ uses hostname: postgres-db (the service name)
         │ on port: 5432
         ▼
  ┌─────────────────────────────────────────────────────┐
  │  postgres-db service (ClusterIP)                    │
  │  Type: ClusterIP (NOT reachable from internet)      │
  │  "Only pods inside cluster can reach me"            │
  └──────────────┬──────────────────────────────────────┘
                 │
                 ▼
         [postgres Pod #1]
         Postgres port 5432
                 │
                 │ reads/writes
                 ▼
         [PersistentVolume]
         1GB on worker node disk
         /var/lib/postgresql/data

  Results travel back up:
  postgres → backend pod → backend service
  → frontend pod (Nginx) → User's browser ✅
```

---

### FLOWCHART 6 — Ports Reference (What Opens Where)

```
  PORT MAP
  =========

  FROM INTERNET:
  ┌──────────┬─────────┬──────────────────────────────────────────┐
  │ Port     │ Open?   │ Purpose                                  │
  ├──────────┼─────────┼──────────────────────────────────────────┤
  │ 30080    │ ✅ YES  │ Frontend app (NodePort → Nginx → port 80)│
  │ 22       │ ✅ YES  │ SSH to manage EC2 instances              │
  │ 5000     │ ❌ NO   │ Backend — internal only                  │
  │ 5432     │ ❌ NO   │ Postgres — internal only                 │
  └──────────┴─────────┴──────────────────────────────────────────┘

  INSIDE THE CLUSTER ONLY:
  ┌──────────────────────────┬───────┬──────────────────────────────┐
  │ Service                  │ Port  │ Who uses it                  │
  ├──────────────────────────┼───────┼──────────────────────────────┤
  │ frontend-service         │ 80    │ Receives proxied traffic      │
  │ watchlist-backend        │ 5000  │ Nginx proxies /api/ here      │
  │ postgres-db              │ 5432  │ Backend connects here for DB  │
  └──────────────────────────┴───────┴──────────────────────────────┘

  K3s CLUSTER PORTS (EC2 Security Group):
  ┌───────┬──────┬────────────────────────────────────────────────┐
  │ Port  │ Type │ Purpose                                        │
  ├───────┼──────┼────────────────────────────────────────────────┤
  │ 6443  │ TCP  │ k3s API server (kubectl talks here)            │
  │ 10250 │ TCP  │ kubelet (master checks worker health)          │
  │ 8472  │ UDP  │ Flannel VXLAN (pod networking across nodes)    │
  └───────┴──────┴────────────────────────────────────────────────┘
```

---

### FLOWCHART 7 — How Services Find Pods (Labels & Selectors)

```
  THE LABEL SYSTEM
  =================

  Every pod gets a label when created:

  frontend pods  → label: app=frontend
  backend pods   → label: app=backend
  postgres pod   → label: app=postgres

  Every service has a selector — it finds pods by matching labels:

  frontend-service:
    selector: app=frontend  ──finds──► [frontend Pod #1] [frontend Pod #2]

  watchlist-backend:
    selector: app=backend   ──finds──► [backend Pod #1]  [backend Pod #2]

  postgres-db:
    selector: app=postgres  ──finds──► [postgres Pod #1]


  WHY THIS MATTERS:
  =================
  Pod gets a random IP when created  e.g. 10.42.1.5
  Pod crashes and restarts           new IP: 10.42.1.9

  If backend hardcoded 10.42.1.5 → broken after restart ❌

  Backend uses service name "postgres-db" → always works ✅
  Service finds the pod by label, not by IP.
  This is why services exist.
```

---

### FLOWCHART 8 — How Data is Kept Safe (PersistentVolume)

```
  WITHOUT PERSISTENTVOLUME (DANGEROUS)
  ======================================
  Postgres Pod starts
       │ stores data INSIDE container filesystem
       ▼
  Pod crashes / restarts
       │
       ▼
  New pod starts with FRESH container ← all data wiped ❌


  WITH PERSISTENTVOLUME (WHAT WE BUILT)
  ========================================
  You created: PersistentVolumeClaim (PVC) → requests 1GB
       │
       ▼
  k3s StorageClass (local-path) → automatically creates
  PersistentVolume on worker node disk
       │
       ▼
  Postgres Pod mounts PVC at /var/lib/postgresql/data
       │
       │ writes movie data here
       ▼
  Actual location on Worker Node disk:
  /var/lib/rancher/k3s/storage/<pvc-name>/

  Pod crashes → disk untouched
  New pod starts → mounts same disk → data still there ✅


  WHAT NEEDS PERSISTENT STORAGE?
  ================================
  Frontend  ❌  serves static files from image — nothing to save
  Backend   ❌  stateless API — saves nothing itself
  Postgres  ✅  stores all your app data — must survive restarts
```

---

## PART 2 — THE KUBERNETES OBJECTS WE USED

---

### What is a Namespace?

A namespace is a virtual folder inside Kubernetes. Without it everything
goes into `default` mixed with Kubernetes' own internal stuff.

We created namespace `watchlist` so all our resources are grouped together,
easy to view, easy to delete, isolated from other apps.

```
kubectl get pods -n watchlist       ← only shows our app's pods
kubectl get pods -n kube-system     ← shows Kubernetes internal pods
```

### What is a Secret?

Stores sensitive values like passwords. You write plain text, Kubernetes
encodes it. The encoded value is injected as environment variables into
your pods at runtime. Never hardcode passwords in your YAML files.

### What is a ConfigMap?

Same as Secret but for non-sensitive config. Database hostname, port
numbers, app settings. Plain text, no encoding.

### What is a PVC?

A request for disk storage. You say "I want 1GB". k3s automatically
creates that space on a worker node's disk and hands it to your pod.

### What is a Deployment?

Tells Kubernetes: run this image, this many copies, with these env vars.
Kubernetes keeps that many pods running at all times. If one dies, a new
one starts automatically.

### What is a Service?

A permanent address to reach pods. Pods have random IPs that change.
A service has a stable DNS name. Other pods use the service name to talk
to each other — never raw IPs.

Three types we used:
- ClusterIP — internal only (backend, postgres)
- NodePort — opens a port on every worker's public IP (frontend)

---

## PART 3 — PRACTICAL STEPS (WHAT WE ACTUALLY DID)

---

### Step 0 — Verify the Cluster

```bash
kubectl get nodes -o wide
```

Expected output: 3 nodes all showing STATUS = Ready

```
NAME           STATUS   ROLES           VERSION
master-k3s     Ready    control-plane   v1.35.5+k3s1
worker-k3s-1   Ready    <none>          v1.35.5+k3s1
worker-k3s-2   Ready    <none>          v1.35.5+k3s1
```

---

### Step 1 — Create Folder Structure

```bash
mkdir -p ~/k8s/{postgres,backend,frontend}
```

Why: Keeps all config files organized by component. You can apply or
delete one component at a time without touching others.

```
~/k8s/
├── namespace.yaml
├── postgres/
│   ├── secret.yaml
│   ├── pvc.yaml
│   ├── deployment.yaml
│   └── service.yaml
├── backend/
│   ├── configmap.yaml
│   ├── deployment.yaml
│   └── service.yaml
└── frontend/
    ├── deployment.yaml
    └── service.yaml
```

---

### Step 2 — Create Namespace

**File: ~/k8s/namespace.yaml**
```yaml
apiVersion: v1          # core Kubernetes API version
kind: Namespace         # resource type we are creating
metadata:
  name: watchlist       # name of our namespace
```

```bash
kubectl apply -f ~/k8s/namespace.yaml
```

Every resource after this lives in namespace `watchlist`.

---

### Step 3 — Postgres Secret

**File: ~/k8s/postgres/secret.yaml**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: postgres-secret
  namespace: watchlist
type: Opaque            # generic key-value secret (not TLS, not docker)
stringData:             # write plain text — k8s encodes automatically
  POSTGRES_DB: watchlistdb
  POSTGRES_USER: watchlistuser
  POSTGRES_PASSWORD: watchlistpass123
```

Why: The backend server.js reads POSTGRES_USER, POSTGRES_PASSWORD,
POSTGRES_DB from environment variables. This Secret injects them.
Keeping passwords out of code and YAML files is good practice.

```bash
kubectl apply -f ~/k8s/postgres/secret.yaml
```

---

### Step 4 — Postgres PVC (Storage)

**File: ~/k8s/postgres/pvc.yaml**
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-pvc
  namespace: watchlist
spec:
  accessModes:
    - ReadWriteOnce       # one pod reads and writes at a time (correct for postgres)
  storageClassName: local-path  # k3s built-in storage using worker node disk
  resources:
    requests:
      storage: 1Gi        # 1GB of disk space
```

Why: Without this, postgres data is lost every time the pod restarts.
This creates 1GB of permanent storage on a worker node's disk.

```bash
kubectl apply -f ~/k8s/postgres/pvc.yaml
```

---

### Step 5 — Postgres Deployment

**File: ~/k8s/postgres/deployment.yaml**
```yaml
apiVersion: apps/v1       # deployments live in the apps API group
kind: Deployment
metadata:
  name: postgres
  namespace: watchlist
spec:
  replicas: 1             # MUST be 1 — two postgres writing same disk = corruption
  selector:
    matchLabels:
      app: postgres       # this deployment owns pods with this label
  template:               # blueprint for every pod this deployment creates
    metadata:
      labels:
        app: postgres     # pods get this label — must match matchLabels above
    spec:
      containers:
        - name: postgres
          image: raj8875/watchlist-db:15-alpine   # image from DockerHub
          ports:
            - containerPort: 5432                 # postgres default port
          envFrom:
            - secretRef:
                name: postgres-secret   # injects DB, USER, PASSWORD into container
          volumeMounts:
            - name: postgres-storage
              mountPath: /var/lib/postgresql/data  # where postgres stores data
      volumes:
        - name: postgres-storage
          persistentVolumeClaim:
            claimName: postgres-pvc    # link to the 1GB disk we created
```

```bash
kubectl apply -f ~/k8s/postgres/deployment.yaml
```

---

### Step 6 — Postgres Service

**File: ~/k8s/postgres/service.yaml**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: postgres-db        # THIS NAME IS CRITICAL
  namespace: watchlist     # backend code has host: 'postgres-db' hardcoded
spec:
  type: ClusterIP          # not reachable from internet — internal only
  selector:
    app: postgres          # routes traffic to pods labeled app=postgres
  ports:
    - port: 5432           # port other pods use to connect
      targetPort: 5432     # port inside the postgres container
```

Why the name `postgres-db`: The backend's server.js has
`host: 'postgres-db'` hardcoded. The service name must match exactly.
Instead of changing the code and rebuilding the image, we named the
service to match the existing code.

```bash
kubectl apply -f ~/k8s/postgres/service.yaml
```

---

### Step 7 — Backend ConfigMap

**File: ~/k8s/backend/configmap.yaml**
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: backend-config
  namespace: watchlist
data:                     # plain text key-value pairs (not sensitive)
  DB_HOST: postgres-db   # hostname = service name of postgres
  DB_PORT: "5432"        # must be quoted string in configmap
```

Why ConfigMap and not Secret: DB_HOST and DB_PORT are not sensitive.
Only passwords go in Secrets. The actual credentials come from
postgres-secret which is referenced in the backend deployment.

```bash
kubectl apply -f ~/k8s/backend/configmap.yaml
```

---

### Step 8 — Backend Deployment

**File: ~/k8s/backend/deployment.yaml**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  namespace: watchlist
spec:
  replicas: 2             # 2 copies — backend is stateless so this is safe
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
    spec:
      containers:
        - name: backend
          image: raj8875/watchlist-backend:latest
          ports:
            - containerPort: 5000    # Node.js runs on port 5000
          envFrom:
            - configMapRef:
                name: backend-config   # injects DB_HOST, DB_PORT
            - secretRef:
                name: postgres-secret  # injects POSTGRES_USER, PASSWORD, DB
```

Why 2 replicas: Backend is stateless (stores nothing itself). Running
2 copies means if one crashes, the other keeps serving requests with
zero downtime. Master automatically restarts the crashed one.

```bash
kubectl apply -f ~/k8s/backend/deployment.yaml
```

---

### Step 9 — Backend Service

**File: ~/k8s/backend/service.yaml**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: watchlist-backend   # must match nginx.conf: proxy_pass http://watchlist-backend:5000
  namespace: watchlist
spec:
  type: ClusterIP           # internal only — internet cannot reach backend directly
  selector:
    app: backend            # routes to pods labeled app=backend (both replicas)
  ports:
    - port: 5000
      targetPort: 5000
```

Why the name `watchlist-backend`: The frontend's nginx.conf has
`proxy_pass http://watchlist-backend:5000` — the service name must
match what Nginx is configured to proxy to.

```bash
kubectl apply -f ~/k8s/backend/service.yaml
```

---

### Step 10 — Frontend Deployment

**File: ~/k8s/frontend/deployment.yaml**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: watchlist
spec:
  replicas: 2             # 2 copies of Nginx serving the frontend
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
        - name: frontend
          image: raj8875/watchlist-frontend:latest
          ports:
            - containerPort: 80   # Nginx listens on port 80 inside container
```

Why no env vars for frontend: Frontend is just Nginx serving static
HTML/JS files. It has no database connection. The JS in the browser
calls /api/ which Nginx proxies to the backend service internally.

```bash
kubectl apply -f ~/k8s/frontend/deployment.yaml
```

---

### Step 11 — Frontend Service (NodePort)

**File: ~/k8s/frontend/service.yaml**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: frontend-service
  namespace: watchlist
spec:
  type: NodePort          # the ONLY service exposed to the internet
  selector:
    app: frontend         # routes to both frontend pods
  ports:
    - port: 80            # internal cluster port
      targetPort: 80      # port inside Nginx container
      nodePort: 30080     # external port on every worker's public IP
```

Why NodePort only for frontend: This is the security model.
Only one door to the internet — the frontend. Everything else
(backend, postgres) is locked inside the cluster. Users can never
directly reach your database or API server from the internet.

```bash
kubectl apply -f ~/k8s/frontend/service.yaml
```

---

### Verify Everything

```bash
# All pods running?
kubectl get pods -n watchlist

# All services created?
kubectl get svc -n watchlist

# Storage bound?
kubectl get pvc -n watchlist
```

Expected pod output:
```
NAME                        READY   STATUS    RESTARTS
backend-xxx-xxx             1/1     Running   0
backend-xxx-xxx             1/1     Running   0
frontend-xxx-xxx            1/1     Running   0
frontend-xxx-xxx            1/1     Running   0
postgres-xxx-xxx            1/1     Running   0
```

---

### Access the App

```
http://<ANY_WORKER_PUBLIC_IP>:30080
```

Both worker IPs work because NodePort opens port 30080 on every node.

---

## PART 4 — USEFUL COMMANDS TO KNOW

```bash
# See all pods in your namespace
kubectl get pods -n watchlist

# Watch pods in real time (updates live)
kubectl get pods -n watchlist -w

# See logs from a pod
kubectl logs -n watchlist -l app=backend

# Describe a pod (detailed info + events — use when pod won't start)
kubectl describe pod <pod-name> -n watchlist

# SSH into a running pod
kubectl exec -it <pod-name> -n watchlist -- /bin/bash

# See all services
kubectl get svc -n watchlist

# See storage
kubectl get pvc -n watchlist

# Delete everything in namespace and start fresh
kubectl delete namespace watchlist

# Apply all files in a folder at once
kubectl apply -f ~/k8s/postgres/
```

---

## PART 5 — SUMMARY: THE SECURITY MODEL

```
  INTERNET
     │
     │ only port 30080 is open
     ▼
  [frontend-service NodePort]
     │
     ▼
  [Nginx pod]  ← serves HTML/JS to browser
     │           proxies /api/ calls internally
     │
     │ internal cluster traffic only
     ▼
  [watchlist-backend ClusterIP]  ← internet CANNOT reach this
     │
     ▼
  [Node.js pod]  ← runs business logic
     │
     │ internal cluster traffic only
     ▼
  [postgres-db ClusterIP]  ← internet CANNOT reach this
     │
     ▼
  [Postgres pod]  ← stores data
     │
     ▼
  [PersistentVolume on disk]  ← data survives pod restarts

  One public door. Everything else hidden. ✅
```

---

*Built on: k3s v1.35.5 | Ubuntu 24.04 | AWS EC2 ap-south-1*
*Namespace: watchlist | Images: raj8875/watchlist-frontend, backend, db*
