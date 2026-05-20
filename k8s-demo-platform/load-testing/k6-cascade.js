import http from "k6/http";
import { sleep } from "k6";

export const options = {
  vus: 60,
  duration: "4m"
};

const BASE_URL = __ENV.BASE_URL || "http://api-gateway.app.svc.cluster.local:8080";

export default function () {
  const payload = JSON.stringify({ sku: "sku-103", qty: 1 });
  const params = { headers: { "Content-Type": "application/json" } };
  http.post(`${BASE_URL}/api/order`, payload, params);
  http.get(`${BASE_URL}/api/dependencies`);
  sleep(0.1);
}
