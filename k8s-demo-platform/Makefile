SHELL := /bin/bash

.PHONY: deploy cleanup health load-normal load-spike load-cascade
.PHONY: chaos-crashloop chaos-latency chaos-500 chaos-redis-down chaos-postgres-down chaos-reset

deploy:
	./scripts/deploy.sh

cleanup:
	./scripts/cleanup.sh

health:
	./scripts/health-check.sh

load-normal:
	k6 run ./load-testing/k6-normal.js

load-spike:
	k6 run ./load-testing/k6-spike.js

load-cascade:
	k6 run ./load-testing/k6-cascade.js

chaos-crashloop:
	./chaos/fault-injection.sh crashloop api-gateway

chaos-latency:
	./chaos/fault-injection.sh high-latency order-service

chaos-500:
	./chaos/fault-injection.sh http-500-spike api-gateway

chaos-redis-down:
	./chaos/fault-injection.sh redis-down

chaos-postgres-down:
	./chaos/fault-injection.sh postgres-down

chaos-reset:
	./chaos/fault-injection.sh reset api-gateway
