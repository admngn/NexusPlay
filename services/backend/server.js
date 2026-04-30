const express = require('express');

const app = express();
const PORT = process.env.PORT || 8080;

app.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});

app.get('/hello', (req, res) => {
  res.json({
    message: 'Hello depuis le backend NexusPlay',
    hostname: require('os').hostname(),
    timestamp: new Date().toISOString()
  });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(JSON.stringify({ event: 'startup', port: PORT }));
});
