import http from 'k6/http';
import { check } from 'k6';

const URL = __ENV.BASE_URL || 'http://3.84.37.64';

export const options = {
  vus: 30,
  duration: '2m',
  thresholds: {
    http_req_failed: ['rate<0.05'],
  },
};

export default function () {
  const res = http.get(`${URL}/api/hello`);
  check(res, { 'status 200': (r) => r.status === 200 });
}
