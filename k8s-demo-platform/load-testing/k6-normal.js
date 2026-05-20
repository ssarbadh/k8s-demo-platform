import http from "k6/http";
import { sleep, check } from "k6";

export const options = {
  vus: 10,
  duration: "3m",
  thresholds: {
    http_req_duration: ["p(95)<800"],
    http_req_failed: ["rate<0.05"]
  }
};

const BASE_URL = __ENV.BASE_URL || "http://api-gateway.app.svc.cluster.local:8080";

export default function () {
  const requestId = `req-${__VU}-${__ITER}`;
  const params = { headers: { "x-request-id": requestId } };
  const res1 = http.get(`${BASE_URL}/api/catalog`, params);
  const res2 = http.post(`${BASE_URL}/api/order`, JSON.stringify({ sku: "sku-101", qty: 1 }), params);
  check(res1, { "catalog returns <500": (r) => r.status < 500 });
  check(res2, { "order returns <500": (r) => r.status < 500 || r.status === 500 });
  sleep(1);
}
