import fs from 'fs';
import path from 'path';
import express from 'express';
import { createServer } from 'http';
import cors from 'cors';
import morgan from 'morgan';
import { env } from './config/env';
import { prisma } from './utils/prisma';
import { initializeFirebase } from './utils/firebase';
import { initializeSocket } from './socket';

import authRoutes from './routes/auth';
import organizationRoutes from './routes/organization';
import memberRoutes from './routes/member';
import scheduleRoutes from './routes/schedule';
import reservationRoutes from './routes/reservation';
import packageRoutes from './routes/package';
import sessionRoutes from './routes/session';
import reportRoutes from './routes/report';
import notificationRoutes from './routes/notification';
import chatRoutes from './routes/chat';
import centerRoutes from './routes/center';
import adminRoutes from './routes/admin';

const app = express();
const webBuildPath = path.resolve(__dirname, '../../app/build/web');
const webIndexPath = path.join(webBuildPath, 'index.html');
const hasWebBuild = fs.existsSync(webIndexPath);

// Middleware
app.use(cors());
app.use(morgan('dev'));
app.use(express.json({ limit: '10mb' }));

// Health check
app.get('/api/health', (_req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// Routes
app.use('/api/auth', authRoutes);
app.use('/api/organizations', organizationRoutes);
app.use('/api/members', memberRoutes);
app.use('/api/schedules', scheduleRoutes);
app.use('/api/reservations', reservationRoutes);
app.use('/api/packages', packageRoutes);
app.use('/api/sessions', sessionRoutes);
app.use('/api/reports', reportRoutes);
app.use('/api/notifications', notificationRoutes);
app.use('/api/chat', chatRoutes);
app.use('/api/centers', centerRoutes);
app.use('/api/admin', adminRoutes);

if (hasWebBuild) {
  app.use(express.static(webBuildPath));
  app.get(/^\/(?!api(?:\/|$)).*/, (_req, res) => {
    res.sendFile(webIndexPath);
  });
}

// Start server
const httpServer = createServer(app);
initializeSocket(httpServer);

async function main() {
  try {
    await prisma.$connect();
    console.log('Database connected');

    initializeFirebase();

    httpServer.listen(env.PORT, '0.0.0.0', () => {
      console.log(`CoachDesk server running on http://0.0.0.0:${env.PORT}`);
    });
  } catch (err) {
    console.error('Failed to start server:', err);
    process.exit(1);
  }
}

main();
