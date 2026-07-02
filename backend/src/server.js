import express from 'express';
import cors from 'cors';
import './db/schema.js';
import authRoutes from './routes/auth.js';
import apiRoutes from './routes/api.js';

const app = express();
app.use(cors());
app.use(express.json());

app.get('/health', (req, res) => res.json({ ok: true, service: 'work-hours-tracker', time: new Date().toISOString() }));

app.use('/auth', authRoutes);
app.use('/', apiRoutes);

app.use((err, req, res, next) => {
  console.error(err);
  res.status(500).json({ error: 'internal error', detail: String(err.message || err) });
});

const PORT = process.env.PORT || 4000;
app.listen(PORT, () => console.log(`Work Hours Tracker API listening on http://localhost:${PORT}`));
