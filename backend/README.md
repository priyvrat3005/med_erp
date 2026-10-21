# Backend (NestJS + PostgreSQL)

Cloud API for sync, backup, messaging, GST, licensing and AI gateway. Multi-tenant with Postgres RLS.

## Run locally
```bash
cp .env.example .env
docker compose up -d          # Postgres 16 + Redis
npm install
npm run migrate               # applies db/migrations/*.sql as the owner role
npm run start:dev             # GET http://localhost:3000/health
```

## Layout
```
db/migrations/   forward-only SQL (001 schema, 002 RLS + immutability + runtime role)
scripts/migrate.ts
src/common/      DbService.withTenant (RLS context), AuthGuard (DEV ONLY), decorators
src/sync/        push/pull endpoints, DTOs, projectors (entity -> tables)
src/health/
openapi.yaml     API contract (shared with the desktop app)
```

## Rules (see ../AGENTS.md)
- Touch tenant data only through `DbService.withTenant`.
- `tenant_id` comes from the token, never from the request.
- App connects as `pharmacy_app` (no BYPASSRLS). Migrations use the owner role.
- The shipped `AuthGuard` is a dev placeholder: replace in task T4.1.

## Generate a dev token (for manual testing)
```bash
node -e "console.log(require('jsonwebtoken').sign({tid:'<tenant-uuid>',sub:'<user-uuid>',did:'<device-uuid>',role:'owner'},process.env.JWT_SECRET,{expiresIn:'1h'}))"
```
You must first insert a tenant, store, device row (see tasks T4.2) or temporarily seed via SQL as the owner role.

## Next backend tasks
T0.2, T4.1 to T4.6, T5.x, T6.x in `../tasks.md`.
