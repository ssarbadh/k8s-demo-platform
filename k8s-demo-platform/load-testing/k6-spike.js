import http from "k6/http";
import { sleep } from "k6";

export const options = {
  stages: [
    { duration: "30s", target: 20 },
    { duration: "1m", target: 120 },
    { duration: "2m", target: 120 },
    { duration: "30s", target: 20 },
    { duration: "30s", target: 0 }
  ]
};

const BASE_URL = __ENV.BASE_URL || "http://api-gateway.app.svc.cluster.local:8080";

export default function () {
  http.get(`${BASE_URL}/api/catalog`);
  http.post(`${BASE_URL}/api/order`, JSON.stringify({ sku: "sku-102", qty: 2 }), {
    headers: { "Content-Type": "application/json" }
  });
  sleep(0.2);
}
