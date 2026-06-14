# Kubernetes Learning Guide (with k3s on EC2)
### Your Setup: 1 Master + 2 Worker EC2 Nodes | Frontend + Backend + PostgreSQL

---

> **How to use this guide:**
> This is your step-by-step companion. Each section ends with a checkpoint.
> Confirm with your guide before moving to the next section.
> Text diagrams are used throughout — read them top-to-bottom like a flowchart.

---

## TABLE OF CONTENTS

1. [What is Kubernetes? Why k3s?](#1-what-is-kubernetes-why-k3s)
2. [Your Physical Setup (EC2 Topology)](#2-your-physical-setup-ec2-topology)
3. [Core Kubernetes Concepts (The Vocabulary)](#3-core-kubernetes-concepts-the-vocabulary)
4. [How Master and Workers Connect](#4-how-master-and-workers-connect)
5. [How Network Flows Inside Kubernetes](#5-how-network-flows-inside-kubernetes)
6. [How Data Flows (Request Lifecycle)](#6-how-data-flows-request-lifecycle)
7. [Namespaces — What Are They and Do You Need 3?](#7-namespaces--what-are-they-and-do-you-need-3)
8. [Persistent Volumes — Keeping Your Database Data Safe](#8-persistent-volumes--keeping-your-database-data-safe)
9. [Your Full Application Architecture](#9-your-full-application-architecture)
10. [Step-by-Step: What You Will Actually Do](#10-step-by-step-what-you-will-actually-do)
11. [Glossary Quick Reference](#11-glossary-quick-reference)

---

## 1. What is Kubernetes? Why k3s?


Think of Kubernetes (K8s) as a **smart manager for your Docker containers**.

Without Kubernetes:
- You SSH into a server and run `docker run ...` manually
- If the container crashes, you restart it manually
- You manage which server runs what yourself

With Kubernetes:
- You *declare* what you want ("I want 2 copies of my frontend running")
- Kubernetes figures out where to run them
- If a container crashes, Kubernetes restarts it automatically
- Scaling up/down is one command

### What is k3s?

k3s = Kubernetes but **lightweight**. Normal Kubernetes is heavy (designed for large enterprise clusters). k3s removes unnecessary components and is perfect for:
- Learning
- Small servers (like EC2 t2/t3 instances)
- Edge environments

```
KUBERNETES vs K3s
=================

Normal Kubernetes:
  [Master Node]
    ├── kube-apiserver     (large)
    ├── etcd               (separate database)
    ├── kube-scheduler     (separate)
    ├── kube-controller    (separate)
    └── cloud-manager      (separate)

k3s (what you're using):
  [Master Node]
    └── k3s server         (ONE binary = all of the above)
                           (uses SQLite instead of etcd)
                           (much lighter!)
```

**Bottom line:** k3s IS Kubernetes. Everything you learn here applies to real Kubernetes too.



---

## 2. Your Physical Setup (EC2 Topology)

### What You Have

```
YOUR EC2 SERVERS (Physical/Virtual Machines)
============================================

  AWS Cloud
  ┌─────────────────────────────────────────────────────────┐
  │                                                         │
  │   ┌──────────────────┐                                  │
  │   │   EC2 Instance 1 │  ◄── This is your MASTER NODE    │
  │   │   (e.g. t3.small)│     (also called Control Plane)  │
  │   │                  │                                  │
  │   │  Runs: k3s server│                                  │
  │   └──────────────────┘                                  │
  │           │                                             │
  │           │  (network communication via private IP)     │
  │           │                                             │
  │   ┌───────┴────────────────────────┐                    │
  │   │                                │                    │
  │   ▼                                ▼                    │
  │  ┌──────────────────┐  ┌──────────────────┐             │
  │  │  EC2 Instance 2  │  │  EC2 Instance 3  │             │
  │  │  WORKER NODE 1   │  │  WORKER NODE 2   │             │
  │  │                  │  │                  │             │
  │  │  Runs: k3s agent │  │  Runs: k3s agent │             │
  │  └──────────────────┘  └──────────────────┘             │
  │                                                         │
  └─────────────────────────────────────────────────────────┘


  [ You / Admin ]
           │
           │ (kubectl commands / Port 6443)
           ▼
┌────────────────────────────────────────────────────────┐
│ MASTER NODE (master-k3s)                               │
│                                                        │
│  ┌────────────────┐       ┌────────────────────────┐   │
│  │  k3s Server    │◄──────┤ SQLite / KINE Database │   │
│  │  (API Server)  │       │ (Stores Cluster State) │   │
│  └───────┬────────┘       └────────────────────────┘   │
└──────────┼─────────────────────────────────────────────┘
           │
           ├──────────────────────────────────────┐
           │ (Port 10250 / Management)            │ (Port 10250 / Management)
           ▼                                      ▼
┌─────────────────────────────┐        ┌─────────────────────────────┐
│ WORKER NODE 1               │        │ WORKER NODE 2               │
│ (worker-k3s-1)              │        │ (worker-k3s-2)              │
│                             │        │                             │
│  ┌───────────────────────┐  │        │  ┌───────────────────────┐  │
│  │  k3s Agent (Kubelet)  │  │        │  │  k3s Agent (Kubelet)  │  │
│  └───────────────────────┘  │        │  └───────────────────────┘  │
└─────────────────────────────┘        └─────────────────────────────┘

The MASTER tells the workers what to run.
The WORKERS actually run your containers.
```

### Who Does What?

```
MASTER NODE responsibilities:
==============================
  ┌─────────────────────────────────────┐
  │           MASTER NODE               │
  │                                     │
  │  1. API Server  ──► Receives your   │
  │                     kubectl commands│
  │                                     │
  │  2. Scheduler   ──► Decides which   │
  │                     worker runs what│
  │                                     │
  │  3. Controller  ──► Watches if pods │
  │                     are healthy     │
  │                                     │
  │  4. etcd/SQLite ──► Stores cluster  │
  │                     state/config    │
  └─────────────────────────────────────┘
  
  ⚠️  Master usually does NOT run your app containers
      (by default in k3s it can, but best practice = don't)


WORKER NODE responsibilities:
==============================
  ┌─────────────────────────────────────┐
  │           WORKER NODE               │
  │                                     │
  │  1. kubelet     ──► Agent that talks│
  │                     to master       │
  │                                     │
  │  2. kube-proxy  ──► Handles network │
  │                     routing         │
  │                                     │
  │  3. Container   ──► Actually runs   │
  │     Runtime         your containers │
  │     (containerd)                    │
  └─────────────────────────────────────┘
```

---
**✅ CHECKPOINT 2:** Are you clear on which EC2 instance is master and which are workers? Do you have all 3 EC2 instances running?
---

---

## 3. Core Kubernetes Concepts (The Vocabulary)

This is the most important section. Learn these terms — everything else builds on them.

### 3.1 Pod

The **smallest unit** in Kubernetes. A Pod wraps one (or sometimes a few) Docker containers.

```
POD
===

  ┌──────────────────────────────────┐
  │              POD                 │
  │                                  │
  │  ┌────────────────────────────┐  │
  │  │    Docker Container        │  │
  │  │    (e.g. your frontend)    │  │
  │  └────────────────────────────┘  │
  │                                  │
  │  Has its own:                    │
  │   - IP address (internal)        │
  │   - Storage mounts               │
  │   - Environment variables        │
  └──────────────────────────────────┘

⚠️  Pods are TEMPORARY. They can die and get replaced.
    A new pod gets a NEW IP address.
    That's why you need "Services" (explained next).
```

### 3.2 Deployment

A **Deployment** manages Pods. You tell it:
- Which Docker image to use
- How many copies (replicas) to run
- How to update them

```
DEPLOYMENT
==========

  You say: "Run 2 copies of my frontend image"
                    │
                    ▼
  ┌─────────────────────────────────────────┐
  │              DEPLOYMENT                 │
  │              (frontend)                 │
  │                                         │
  │  Manages ──► Pod 1 [frontend container] │
  │              Pod 2 [frontend container] │
  │                                         │
  │  If Pod 1 dies → auto-creates Pod 3     │
  │  Always maintains desired count         │
  └─────────────────────────────────────────┘
```

### 3.3 Service

A **Service** gives a stable network address to reach your Pods. Since Pods come and go with changing IPs, a Service acts like a permanent door.

```
SERVICE
=======

  Outside world / other pods
          │
          │  (stable address: e.g. "frontend-service")
          ▼
  ┌──────────────────────┐
  │       SERVICE        │
  │   (Load Balancer)    │
  │                      │
  │  Knows about all     │
  │  healthy pods with   │
  │  label: app=frontend │
  └──────────────────────┘
          │
     ┌────┴────┐
     ▼         ▼
  [Pod 1]   [Pod 2]   ◄── Traffic is split between healthy pods
  frontend  frontend
```

**Types of Services:**

```
SERVICE TYPES
=============

ClusterIP (default):
  ┌────────────────────────────────────┐
  │  Only reachable INSIDE the cluster │
  │  Used for: backend ↔ database      │
  │  No external access                │
  └────────────────────────────────────┘

NodePort:
  ┌────────────────────────────────────┐
  │  Opens a port on EVERY node        │
  │  EC2_IP:30080 → reaches your pod   │
  │  Used for: testing/learning        │
  └────────────────────────────────────┘

LoadBalancer:
  ┌────────────────────────────────────┐
  │  Creates an AWS Load Balancer      │
  │  (costs money on AWS)              │
  │  Used for: production              │
  └────────────────────────────────────┘
```

### 3.4 Namespace

A **Namespace** is a virtual divider inside your cluster — like folders on a computer.

```
NAMESPACE
=========

  One Physical Cluster
  ┌─────────────────────────────────────────────┐
  │                                             │
  │  Namespace: default                         │
  │  ┌────────────────────────────────────┐     │
  │  │  (stuff without a namespace goes   │     │
  │  │   here automatically)              │     │
  │  └────────────────────────────────────┘     │
  │                                             │
  │  Namespace: kube-system                     │
  │  ┌────────────────────────────────────┐     │
  │  │  (Kubernetes own internal stuff)   │     │
  │  └────────────────────────────────────┘     │
  │                                             │
  │  Namespace: myapp  (you create this)        │
  │  ┌────────────────────────────────────┐     │
  │  │  frontend pods                     │     │
  │  │  backend pods                      │     │
  │  │  postgres pods                     │     │
  │  └────────────────────────────────────┘     │
  └─────────────────────────────────────────────┘
```

**Answer to your question: Do you need 3 separate namespaces for 3 images?**

```
OPTION A: 3 Namespaces (overkill for beginners)
================================================
  namespace: frontend  → frontend pods
  namespace: backend   → backend pods
  namespace: database  → postgres pods

  Problem: Cross-namespace communication is harder.
           You need to use full DNS names.
           More complex for no real benefit at this scale.


OPTION B: 1 Namespace (RECOMMENDED for you) ✅
================================================
  namespace: myapp
    ├── frontend pods
    ├── backend pods
    └── postgres pods

  Benefit: Simple. All pods talk to each other easily.
           You can still separate them logically with labels.
```

**For your setup: Use ONE namespace called `myapp`**

### 3.5 ConfigMap and Secret

```
CONFIGMAP
=========
  Stores non-sensitive config as key-value pairs.
  Examples: DATABASE_HOST=postgres-service
            APP_PORT=3000

SECRET
======
  Like ConfigMap but BASE64 encoded (for sensitive data).
  Examples: DB_PASSWORD=mysecretpass
            JWT_SECRET=abc123

  ⚠️  Secrets are not truly encrypted in k3s by default.
      For learning purposes they're fine.
      In production: use AWS Secrets Manager or Vault.
```

### 3.6 PersistentVolume and PersistentVolumeClaim

```
PERSISTENT VOLUME (PV) + CLAIM (PVC)
=====================================

  Problem: Pods are temporary. When Postgres pod dies,
           all database data is LOST if stored inside pod.

  Solution: Store data on the NODE's disk, outside the pod.

  ┌──────────────────────────────────────────────────────┐
  │  EC2 Worker Node Disk                                │
  │  ┌─────────────────────────────────┐                │
  │  │   /mnt/data/postgres  (on disk) │  ◄─ PV         │
  │  └─────────────────────────────────┘                │
  │            ▲                                         │
  │            │ "claimed by"                            │
  │  ┌─────────┴────────────┐                           │
  │  │   PVC (your request) │  ◄─ PVC                   │
  │  └──────────────────────┘                           │
  │            ▲                                         │
  │            │ "mounted by"                            │
  │  ┌─────────┴────────────┐                           │
  │  │   Postgres Pod       │                           │
  │  │   /var/lib/postgresql│  ◄─ reads/writes here     │
  │  └──────────────────────┘                           │
  └──────────────────────────────────────────────────────┘

  Pod dies → data stays on disk → new pod mounts same disk
  Data is SAFE!
```

---
**✅ CHECKPOINT 3:** Do you understand these 6 core concepts: Pod, Deployment, Service, Namespace, ConfigMap/Secret, PersistentVolume? Any confusion before we proceed?
---

---

## 4. How Master and Workers Connect

### The Bootstrap Process

```
HOW K3s MASTER AND WORKERS CONNECT
====================================

STEP 1: You start k3s on the master EC2
  ┌──────────────────┐
  │   EC2 Master     │
  │                  │
  │  $ k3s server    │
  │                  │
  │  → API Server    │
  │    starts on     │
  │    port 6443     │
  │                  │
  │  → Generates a   │
  │    TOKEN         │
  │    (K3S_TOKEN)   │
  └──────────────────┘
          │
          │ You copy this TOKEN
          ▼
STEP 2: You start k3s on each worker with the token
  ┌──────────────────┐    ┌──────────────────┐
  │  EC2 Worker 1    │    │  EC2 Worker 2    │
  │                  │    │                  │
  │  $ k3s agent     │    │  $ k3s agent     │
  │    --server      │    │    --server      │
  │    https://      │    │    https://      │
  │    MASTER_IP:    │    │    MASTER_IP:    │
  │    6443          │    │    6443          │
  │    --token TOKEN │    │    --token TOKEN │
  └──────────────────┘    └──────────────────┘
          │                        │
          └──────────┬─────────────┘
                     │ both connect to master
                     ▼
STEP 3: Cluster is formed!
  ┌──────────────────────────────────────────┐
  │              CLUSTER                     │
  │                                          │
  │  Master ◄──────────────────────────────► │
  │           │              │               │
  │       Worker 1       Worker 2            │
  │                                          │
  │  $ kubectl get nodes   ← you run this   │
  │                          on master       │
  │  NAME       STATUS                       │
  │  master     Ready                        │
  │  worker-1   Ready                        │
  │  worker-2   Ready                        │
  └──────────────────────────────────────────┘
```

### Ongoing Communication

```
MASTER ↔ WORKER COMMUNICATION (ongoing)
=========================================

  Every few seconds:

  Worker:   "Hey master, I'm alive. Here's my resource usage."
  Master:   "OK. Run this new pod on you. Pod spec below..."
  Worker:   "Got it. Pod is now running."
  Master:   "OK I recorded that in my state store."

  If Worker goes silent:
  Master:   "Worker 1 is not responding. I'll reschedule
             its pods to Worker 2."
             (This is called self-healing!)

  PORT REFERENCE:
  ┌─────────────────────────────────────────────┐
  │  6443  : API Server (kubectl + workers use) │
  │  10250 : kubelet (worker reports to master) │
  │  2379  : etcd (internal, master only)       │
  │  8472  : Flannel/VXLAN (pod networking)     │
  └─────────────────────────────────────────────┘
```

---
**✅ CHECKPOINT 4:** Is the master-worker connection process clear? Do you understand the TOKEN concept and why port 6443 matters for your EC2 security groups?
---

---

## 5. How Network Flows Inside Kubernetes

### The 3 Levels of Networking

```
KUBERNETES NETWORKING — 3 LEVELS
==================================

LEVEL 1: Pod-to-Pod (within a node)
  Worker Node
  ┌─────────────────────────────┐
  │  Pod A (IP: 10.42.1.2)      │
  │       ▼                     │
  │  virtual bridge (cbr0)      │
  │       ▼                     │
  │  Pod B (IP: 10.42.1.3)      │
  └─────────────────────────────┘
  Direct communication via bridge. Fast.


LEVEL 2: Pod-to-Pod (across nodes)
  Worker Node 1                   Worker Node 2
  ┌──────────────────┐            ┌──────────────────┐
  │  Pod A           │            │  Pod B           │
  │  (10.42.1.2)     │            │  (10.42.2.5)     │
  └────────┬─────────┘            └────────▲─────────┘
           │                               │
           │  VXLAN tunnel (Flannel CNI)   │
           └───────────────────────────────┘
  
  k3s uses Flannel (a CNI plugin) to create a virtual network
  overlay so all pods can talk to each other regardless of
  which physical node they're on.


LEVEL 3: Pod to Service
  Pod A ──► Service (stable DNS name) ──► Pod B or Pod C
  
  Services use iptables rules on each node.
  kube-proxy manages these rules.
```

### DNS Inside Kubernetes

```
KUBERNETES DNS
==============

  Every Service gets a DNS name automatically:
  
  Format:  <service-name>.<namespace>.svc.cluster.local
  
  Examples for your app (namespace = myapp):
  
  ┌────────────────────────────────────────────────────┐
  │  Service Name    │  DNS Name                        │
  ├────────────────────────────────────────────────────┤
  │  frontend-svc    │  frontend-svc.myapp.svc.cluster.local │
  │  backend-svc     │  backend-svc.myapp.svc.cluster.local  │
  │  postgres-svc    │  postgres-svc.myapp.svc.cluster.local │
  └────────────────────────────────────────────────────┘
  
  ✅ SHORTCUT: Within the SAME namespace, you can just use:
     "backend-svc"   instead of the full DNS name
     "postgres-svc"  instead of the full DNS name
  
  So your backend container connects to Postgres using:
  DATABASE_HOST = postgres-svc
  DATABASE_PORT = 5432
```

---
**✅ CHECKPOINT 5:** Does the networking make sense? Especially the DNS shortcut — your backend will connect to Postgres via hostname "postgres-svc", not an IP address. Is that clear?
---

---

## 6. How Data Flows (Request Lifecycle)

### A User Visits Your App

```
USER REQUEST FLOW — Full Journey
==================================

  [User's Browser]
       │
       │  HTTP request to your EC2's public IP
       │  e.g. http://3.80.100.200:30080
       ▼
  ┌─────────────────────────────────────────────────┐
  │  EC2 Worker Node (any node, NodePort opens on all)│
  │                                                 │
  │  iptables rule: port 30080 → frontend-service   │
  │                                                 │
  │  ┌───────────────────────┐                      │
  │  │   FRONTEND SERVICE    │  (ClusterIP/NodePort) │
  │  │   Selector: app=front │                      │
  │  └───────────┬───────────┘                      │
  │              │  load balances to                │
  │              ▼                                  │
  │  ┌──────────────────────┐                       │
  │  │  Frontend Pod        │                       │
  │  │  (React / HTML/CSS)  │                       │
  │  └──────────┬───────────┘                       │
  └─────────────│───────────────────────────────────┘
                │
                │ API call: /api/users
                │ (via backend-svc DNS name)
                ▼
  ┌─────────────────────────────────────────────────┐
  │  Same or Different Worker Node                  │
  │                                                 │
  │  ┌───────────────────────┐                      │
  │  │   BACKEND SERVICE     │  (ClusterIP only)    │
  │  │   Selector: app=back  │                      │
  │  └───────────┬───────────┘                      │
  │              ▼                                  │
  │  ┌──────────────────────┐                       │
  │  │  Backend Pod         │                       │
  │  │  (Node.js / FastAPI  │                       │
  │  │   etc)               │                       │
  │  └──────────┬───────────┘                       │
  └─────────────│───────────────────────────────────┘
                │
                │ DB query via postgres-svc:5432
                ▼
  ┌─────────────────────────────────────────────────┐
  │  Worker Node (wherever Postgres pod is running) │
  │                                                 │
  │  ┌───────────────────────┐                      │
  │  │   POSTGRES SERVICE    │  (ClusterIP only)    │
  │  │   Selector: app=pg    │                      │
  │  └───────────┬───────────┘                      │
  │              ▼                                  │
  │  ┌──────────────────────┐                       │
  │  │  Postgres Pod        │                       │
  │  │  (postgres:15 image) │                       │
  │  └──────────┬───────────┘                       │
  │             │ reads/writes                      │
  │             ▼                                   │
  │  ┌──────────────────────┐                       │
  │  │  PersistentVolume    │                       │
  │  │  /mnt/data/postgres  │                       │
  │  │  (disk on this node) │                       │
  │  └──────────────────────┘                       │
  └─────────────────────────────────────────────────┘
                │
                │ Results flow back up the chain:
                │ PG → Backend Pod → Backend Svc
                │ → Frontend Pod → User's Browser
                ▼
  [User sees data in browser] ✅
```

---
**✅ CHECKPOINT 6:** Does the full request flow make sense? Notice how Postgres is NEVER directly accessible from outside — only the backend can talk to it.
---

---

## 7. Namespaces — What Are They and Do You Need 3?

### The Analogy

Think of namespaces like **folders** in your computer:

```
WITHOUT NAMESPACES:
===================
  /home/
    ├── my-project-frontend-pod
    ├── my-project-backend-pod
    ├── my-project-postgres-pod
    ├── some-other-app-pod
    └── kube-dns-pod             ← Kubernetes internals mixed in!
    
  Everything is mixed together. Hard to manage.


WITH NAMESPACES:
================
  kube-system/
    ├── kube-dns-pod             ← Kubernetes internals
    └── metrics-server-pod
    
  myapp/                        ← YOUR application
    ├── frontend-pod
    ├── backend-pod
    └── postgres-pod
    
  monitoring/                   ← Future: monitoring tools
    └── prometheus-pod
```

### Namespace Decision for Your Setup

```
YOUR DECISION: ONE namespace = "myapp"
========================================

  Reasons:
  ✅ All 3 components (frontend, backend, DB) are ONE application
  ✅ They NEED to talk to each other (simpler within same namespace)
  ✅ You're learning — keep it simple
  ✅ You can still label pods differently: app=frontend, app=backend

  When would you use multiple namespaces?
  - Different TEAMS working on different apps on same cluster
  - Strict isolation requirements (security/compliance)
  - dev / staging / production environments on same cluster

  For your case:
  ┌─────────────────────────────────────┐
  │  namespace: myapp                   │
  │                                     │
  │  ┌───────────┐  ┌───────────┐       │
  │  │ frontend  │  │  backend  │       │
  │  │   pod(s)  │  │   pod(s)  │       │
  │  └───────────┘  └───────────┘       │
  │                                     │
  │  ┌───────────┐                      │
  │  │ postgres  │                      │
  │  │   pod     │                      │
  │  └───────────┘                      │
  └─────────────────────────────────────┘
```

---
**✅ CHECKPOINT 7:** Clear on why 1 namespace is better for your setup? Any questions about namespaces?
---

---

## 8. Persistent Volumes — Keeping Your Database Data Safe

### Why This Matters

```
WITHOUT PERSISTENT VOLUME (DANGER!)
=====================================

  Postgres Pod running
       │
       │ stores data inside container
       ▼
  Pod crashes or gets restarted
       │
       ▼
  NEW Postgres Pod starts
       │
       ▼
  ❌ ALL DATA GONE — container filesystem was wiped!


WITH PERSISTENT VOLUME (SAFE!) ✅
===================================

  Postgres Pod running
       │
       │ stores data to /var/lib/postgresql
       │ which is MOUNTED from node disk
       ▼
  /mnt/k3s-data/postgres  (on Worker Node's disk)
  
  Pod crashes → data stays on disk
  New pod starts → mounts same disk location
  ✅ DATA SAFE!
```

### PV, PVC, StorageClass Relationship

```
STORAGE CONCEPTS
=================

  STORAGECLASS  ──►  defines HOW storage is provisioned
       │              (k3s has a built-in "local-path"
       │               StorageClass — uses node disk)
       │
       ▼
  PERSISTENTVOLUME (PV)  ──►  actual storage resource
       │                       (e.g. 5GB on Worker Node disk)
       │
       ▼
  PERSISTENTVOLUMECLAIM (PVC)  ──►  your request for storage
       │                             "I want 5GB for Postgres"
       │
       ▼
  POSTGRES POD  ──►  uses the PVC as a mounted volume


FLOW:
=====

  You create PVC: "I need 5GB"
       │
       ▼
  k3s StorageClass (local-path) automatically creates PV
       │
       ▼
  PVC is "bound" to PV
       │
       ▼
  Postgres pod mounts PVC at /var/lib/postgresql/data
       │
       ▼
  Data written to /var/lib/postgresql/data
  = actually written to Worker Node disk at
    /var/lib/rancher/k3s/storage/<pvc-name>/
```

### Only Postgres Needs PV

```
WHICH COMPONENTS NEED PERSISTENT STORAGE?
==========================================

  ┌────────────────┬──────────────────────────────────┐
  │  Component     │  Needs PV?  │  Reason             │
  ├────────────────┼─────────────┼─────────────────────┤
  │  Frontend      │  ❌ NO      │  Serves static files │
  │                │             │  from image itself   │
  ├────────────────┼─────────────┼─────────────────────┤
  │  Backend       │  ❌ NO      │  Stateless API.      │
  │                │             │  State is in the DB  │
  ├────────────────┼─────────────┼─────────────────────┤
  │  PostgreSQL    │  ✅ YES     │  Must persist data   │
  │                │             │  across pod restarts │
  └────────────────┴─────────────┴─────────────────────┘
```

---
**✅ CHECKPOINT 8:** Clear on why only Postgres needs a PV? And on how the PV/PVC mechanism works?
---

---

## 9. Your Full Application Architecture

### Everything Together

```
COMPLETE ARCHITECTURE DIAGRAM
================================

  Internet
     │
     │  (public IP of any EC2, port 30080)
     ▼
  ┌─────────────────────────────────────────────────────────────────┐
  │                    K3s CLUSTER                                  │
  │                                                                 │
  │  ┌─────────────────────────────────────────────────────────┐   │
  │  │                   namespace: myapp                      │   │
  │  │                                                         │   │
  │  │  ┌─────────────────────────────────────────────────┐   │   │
  │  │  │               FRONTEND                          │   │   │
  │  │  │                                                 │   │   │
  │  │  │  [NodePort Service :30080]                      │   │   │
  │  │  │       │                                         │   │   │
  │  │  │       ▼                                         │   │   │
  │  │  │  [Deployment] ──► [Pod: frontend-container]     │   │   │
  │  │  │                   DockerHub: yourname/frontend   │   │   │
  │  │  └─────────────────────────┬───────────────────────┘   │   │
  │  │                            │ API calls to               │   │
  │  │                            │ http://backend-svc:8000    │   │
  │  │                            ▼                            │   │
  │  │  ┌─────────────────────────────────────────────────┐   │   │
  │  │  │               BACKEND                           │   │   │
  │  │  │                                                 │   │   │
  │  │  │  [ClusterIP Service: backend-svc]               │   │   │
  │  │  │       │                                         │   │   │
  │  │  │       ▼                                         │   │   │
  │  │  │  [Deployment] ──► [Pod: backend-container]      │   │   │
  │  │  │                   DockerHub: yourname/backend    │   │   │
  │  │  │                   Env: DB_HOST=postgres-svc      │   │   │
  │  │  └─────────────────────────┬───────────────────────┘   │   │
  │  │                            │ DB queries to              │   │
  │  │                            │ postgres-svc:5432          │   │
  │  │                            ▼                            │   │
  │  │  ┌─────────────────────────────────────────────────┐   │   │
  │  │  │               POSTGRES                          │   │   │
  │  │  │                                                 │   │   │
  │  │  │  [ClusterIP Service: postgres-svc :5432]        │   │   │
  │  │  │       │                                         │   │   │
  │  │  │       ▼                                         │   │   │
  │  │  │  [StatefulSet/Deployment]                       │   │   │
  │  │  │       │                                         │   │   │
  │  │  │       ▼                                         │   │   │
  │  │  │  [Pod: postgres-container]                      │   │   │
  │  │  │  DockerHub: postgres:15                         │   │   │
  │  │  │       │                                         │   │   │
  │  │  │       │ mounts volume                           │   │   │
  │  │  │       ▼                                         │   │   │
  │  │  │  [PVC: postgres-pvc] ──► [PV: 5GB on disk]     │   │   │
  │  │  └─────────────────────────────────────────────────┘   │   │
  │  │                                                         │   │
  │  │  [Secret: postgres-secret]  DB_PASSWORD=***            │   │
  │  │  [ConfigMap: app-config]    DB_HOST=postgres-svc        │   │
  │  └─────────────────────────────────────────────────────────┘   │
  │                                                                 │
  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
  │  │ EC2 Master   │  │ EC2 Worker 1 │  │ EC2 Worker 2 │         │
  │  │ (control     │  │ (runs pods)  │  │ (runs pods)  │         │
  │  │  plane)      │  │              │  │              │         │
  │  └──────────────┘  └──────────────┘  └──────────────┘         │
  └─────────────────────────────────────────────────────────────────┘


  NOTES:
  ● Frontend uses NodePort → accessible from internet
  ● Backend uses ClusterIP → ONLY accessible from within cluster
  ● Postgres uses ClusterIP → ONLY accessible from within cluster
  ● Only backend can talk to postgres (by configuration)
```

### Kubernetes Files You Will Create

```
FILES YOU'LL WRITE (YAML manifests)
=====================================

  k8s/
  ├── namespace.yaml            ← Create "myapp" namespace
  │
  ├── postgres/
  │   ├── secret.yaml           ← DB password (base64)
  │   ├── pvc.yaml              ← Storage claim (5GB)
  │   ├── deployment.yaml       ← Postgres pod spec
  │   └── service.yaml          ← postgres-svc ClusterIP
  │
  ├── backend/
  │   ├── configmap.yaml        ← DB_HOST, DB_PORT etc
  │   ├── deployment.yaml       ← Backend pod spec
  │   └── service.yaml          ← backend-svc ClusterIP
  │
  └── frontend/
      ├── deployment.yaml       ← Frontend pod spec
      └── service.yaml          ← frontend-svc NodePort :30080
```

---
**✅ CHECKPOINT 9:** Does the complete architecture make sense? Do you see how all pieces fit together?
---

---

## 10. Step-by-Step: What You Will Actually Do

This is your roadmap. Each step will be expanded with actual commands when you're ready.

```
YOUR JOURNEY ROADMAP
=====================

PHASE 1: CLUSTER SETUP
  Step 1.1  ► Install k3s on Master EC2
  Step 1.2  ► Get join token from master
  Step 1.3  ► Install k3s agent on Worker 1 + 2
  Step 1.4  ► Verify: kubectl get nodes (all 3 = Ready)
             ✅ Checkpoint: 3 nodes showing Ready
  
PHASE 2: NAMESPACE & STORAGE
  Step 2.1  ► Create namespace "myapp"
  Step 2.2  ► Create Postgres Secret (DB password)
  Step 2.3  ► Create PVC for Postgres (5GB)
             ✅ Checkpoint: PVC shows Bound status

PHASE 3: DEPLOY POSTGRES
  Step 3.1  ► Write postgres Deployment YAML
  Step 3.2  ► Write postgres Service YAML (ClusterIP)
  Step 3.3  ► Apply: kubectl apply -f postgres/
  Step 3.4  ► Verify: pod is Running, PV is mounted
             ✅ Checkpoint: DB accessible within cluster

PHASE 4: DEPLOY BACKEND
  Step 4.1  ► Push backend Docker image to DockerHub
  Step 4.2  ► Write backend ConfigMap (DB connection info)
  Step 4.3  ► Write backend Deployment YAML
  Step 4.4  ► Write backend Service YAML (ClusterIP)
  Step 4.5  ► Apply and verify
             ✅ Checkpoint: Backend can connect to Postgres

PHASE 5: DEPLOY FRONTEND
  Step 5.1  ► Push frontend Docker image to DockerHub
  Step 5.2  ► Write frontend Deployment YAML
  Step 5.3  ► Write frontend Service YAML (NodePort :30080)
  Step 5.4  ► Apply and verify
             ✅ Checkpoint: App accessible in browser!

PHASE 6: VERIFY END-TO-END
  Step 6.1  ► Open browser: http://EC2_IP:30080
  Step 6.2  ► Test data flow: frontend → backend → postgres
  Step 6.3  ► Kill a pod manually, watch it self-heal
  Step 6.4  ► Check logs: kubectl logs <pod-name>
             ✅ Final Checkpoint: Everything working!
```

### Useful Commands Reference

```
KUBECTL CHEAT SHEET (you'll use these constantly)
==================================================

  # See all nodes
  kubectl get nodes

  # See all pods in your namespace
  kubectl get pods -n myapp

  # See all pods everywhere
  kubectl get pods --all-namespaces

  # See pod details / troubleshoot
  kubectl describe pod <pod-name> -n myapp

  # See pod logs
  kubectl logs <pod-name> -n myapp

  # Apply a YAML file
  kubectl apply -f filename.yaml

  # Delete a resource
  kubectl delete -f filename.yaml

  # Get into a running pod (like SSH)
  kubectl exec -it <pod-name> -n myapp -- /bin/bash

  # See services
  kubectl get services -n myapp

  # See persistent volumes
  kubectl get pv
  kubectl get pvc -n myapp

  # Watch pods in real time
  kubectl get pods -n myapp -w
```

---
**✅ CHECKPOINT 10:** Does the roadmap make sense? Are you ready to start Phase 1 (cluster setup)?
---

---

## 11. Glossary Quick Reference

```
GLOSSARY
=========

  Term              │ Simple Meaning
  ──────────────────┼──────────────────────────────────────────
  Cluster           │ All your EC2s working together as one system
  Node              │ A single EC2 server in the cluster
  Master/Control    │ The EC2 that manages the cluster
  Plane             │
  Worker Node       │ EC2 that actually runs your app containers
  Pod               │ Smallest unit; wraps one Docker container
  Container         │ Your Docker image running as a process
  Deployment        │ Manages pods; ensures N copies are running
  Service           │ Stable network address to reach pods
  ClusterIP         │ Service only reachable inside cluster
  NodePort          │ Service reachable from outside via EC2 port
  Namespace         │ Virtual folder to group related resources
  ConfigMap         │ Key-value config (non-sensitive)
  Secret            │ Key-value config (sensitive, base64)
  PV                │ PersistentVolume — actual disk storage
  PVC               │ PersistentVolumeClaim — your storage request
  StorageClass      │ Defines how to automatically create PVs
  kubectl           │ CLI tool to talk to Kubernetes
  YAML manifest     │ Config file describing what K8s should run
  kubelet           │ Agent on each worker that talks to master
  kube-proxy        │ Handles network routing on each node
  CNI               │ Container Network Interface (Flannel in k3s)
  Flannel           │ k3s default network plugin for pod networking
  etcd/SQLite       │ Database where K8s stores cluster state
  k3s server        │ Master node process in k3s
  k3s agent         │ Worker node process in k3s
  StatefulSet       │ Like Deployment but for stateful apps (DBs)
  ReplicaSet        │ Internal mechanism Deployment uses for copies
  Image Pull Policy │ When K8s checks DockerHub for new image
  Labels            │ Key-value tags on pods used by Services to
                    │ find the right pods
  Selectors         │ How Services find pods (match by labels)
  Ingress           │ HTTP router (for later: path-based routing)
  ──────────────────┴──────────────────────────────────────────
```

---

## Summary: Your Mental Model

```
THE BIG PICTURE
================

  You write YAML files (intentions/declarations)
       │
       ▼
  kubectl apply → sends to API Server on Master
       │
       ▼
  Master stores desired state in SQLite/etcd
       │
       ▼
  Scheduler: "Which worker has room? → Worker 1"
       │
       ▼
  kubelet on Worker 1 receives pod spec
       │
       ▼
  Worker 1 pulls Docker image from DockerHub
       │
       ▼
  Container starts running on Worker 1
       │
       ▼
  Service makes it reachable via stable DNS name
       │
       ▼
  NodePort service exposes it to the internet
       │
       ▼
  Your app is live! 🎉

  And if anything fails → K8s fixes it automatically.
  That's the magic of Kubernetes.
```

---

*This guide was created for hands-on learning with k3s on 3 EC2 instances.*
*Follow checkpoints in order. Ask questions at each checkpoint before proceeding.*

*Version 1.0 | Your Kubernetes Learning Journey*
