import http from 'k6/http';
import { check } from 'k6';

const URL = __ENV.BASE_URL || 'http://44.202.153.219';

export const options = {
  vus: 3,
  duration: '20s',
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<500'],
  },
};

export default function () {
  const res = http.get(`${URL}/api/hello`);
  check(res, { 'status 200': (r) => r.status === 200 });
}
