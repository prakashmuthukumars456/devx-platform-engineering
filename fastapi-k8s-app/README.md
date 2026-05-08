# fastapi-k8s-app — Phase 1: Docker

This app is the foundation for a 4-phase project:
- **Phase 1** → Docker Compose (you are here)
- **Phase 2** → Kubernetes on Docker Desktop
- **Phase 3** → Terraform (AWS VPC, EC2, RDS)
- **Phase 4** → EKS with Terraform

## Project Structure

```
fastapi-k8s-app/
├── app/
│   ├── core/
│   │   └── config.py        # pydantic-settings — reads from .env
│   ├── models/
│   │   └── item.py          # SQLAlchemy ORM model
│   ├── routers/
│   │   ├── health.py        # /health, /health/live, /health/ready
│   │   └── items.py         # CRUD endpoints
│   ├── database.py          # async engine + session
│   └── main.py              # FastAPI app + lifespan
├── Dockerfile               # multi-stage, non-root user
├── docker-compose.yml       # app + postgres + redis
├── .env.example             # copy this to .env
└── requirements.txt
```

---

## Phase 1 — Getting Started

### 1. Create your .env

```bash
cp .env.example .env
```

The defaults work out of the box. No changes needed for local dev.

### 2. Build and start everything

```bash
docker compose up --build
```

First run takes ~2 min (downloads images, installs packages).
Subsequent runs are fast because of Docker layer caching.

### 3. Verify it's running

```bash
# All three containers should show healthy
docker compose ps

# Tail logs
docker compose logs -f app
```

### 4. Hit the endpoints

```bash
# Simple health (no DB/Redis dependency)
curl http://localhost:8000/health

# Readiness — checks DB + Redis
curl http://localhost:8000/health/ready

# Liveness — just process alive check
curl http://localhost:8000/health/live

# Swagger UI (DEBUG=true required)
open http://localhost:8000/docs
```

### 5. Test the CRUD API

```bash
# Create an item
curl -X POST http://localhost:8000/api/v1/items \
  -H "Content-Type: application/json" \
  -d '{"name": "My first item", "description": "testing phase 1"}'

# List items
curl http://localhost:8000/api/v1/items

# Get by ID (replace <id> with the id from create response)
curl http://localhost:8000/api/v1/items/<id>
```

### 6. Watch hot-reload in action

```bash
# Start with watch mode
docker compose watch

# Now edit any file in ./app — changes sync to the container instantly
# No rebuild needed during development
```

### 7. Tear down

```bash
# Stop containers (keeps volumes)
docker compose down

# Stop AND delete the postgres volume (full reset)
docker compose down -v
```

---

## Key Concepts in This Setup

### Why multi-stage Dockerfile?
Stage 1 (`builder`) installs gcc and build tools to compile C extensions like asyncpg.
Stage 2 (`final`) copies only the installed packages — no compiler, no cache.
Result: ~200MB image instead of ~800MB.

### Why non-root user?
Running as root inside a container means a container escape = root on the host.
Kubernetes `SecurityContext.runAsNonRoot: true` enforces this in production.
Practicing it from Phase 1 means no surprises in Phase 4.

### Why separate /health/live and /health/ready?
- **Liveness**: K8s kills and restarts the pod if this fails
- **Readiness**: K8s stops routing traffic but doesn't restart
Different problems, different responses. A slow DB shouldn't kill your pod.

### Why `depends_on: condition: service_healthy`?
Without this, docker-compose starts all containers simultaneously.
Your app crashes because postgres isn't ready yet.
This is the same problem that K8s `initContainers` solves in Phase 2.

---

## Connect to Postgres Directly

```bash
# From your host machine (port 5432 is exposed)
psql -h localhost -U appuser -d appdb
# password: apppassword

# Or exec into the postgres container
docker exec -it k8s_postgres psql -U appuser -d appdb
```

## Connect to Redis Directly

```bash
docker exec -it k8s_redis redis-cli -a redispassword
> PING   # should return PONG
> KEYS * # see all keys
```
