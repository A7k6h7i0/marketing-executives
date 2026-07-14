import { Response } from "express";
import { prisma } from "../config/prisma";
import { AuthenticatedRequest } from "../middlewares/auth";
import { calculateDistanceKM } from "../utils/distance";
import { TrackingStartPoint } from "@prisma/client";

export const pingGps = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const userId = req.user?.id;
  const { latitude, longitude, timestamp, trackingStartPoint } = req.body;

  if (!userId || latitude === undefined || longitude === undefined || !trackingStartPoint) {
    res.status(400).json({ error: "userId, latitude, longitude, and trackingStartPoint are required." });
    return;
  }

  try {
    const pingTime = timestamp ? new Date(timestamp) : new Date();

    // Enforce rate limit: store no more than one GPS ping every 30 seconds
    const lastPing = await prisma.gpsPing.findFirst({
      where: { userId },
      orderBy: { timestamp: "desc" },
    });

    if (lastPing) {
      const secondsSinceLastPing = (pingTime.getTime() - lastPing.timestamp.getTime()) / 1000;
      if (secondsSinceLastPing < 30) {
        res.status(200).json({
          message: "Ping ignored (rate limit: 30s)",
          ping: lastPing,
        });
        return;
      }
    }

    // Calculate distance from previous ping
    let distanceFromPrev = 0;
    if (lastPing) {
      // Check if the previous ping was today (to avoid calculating distance from yesterday's last location)
      const lastPingDate = lastPing.timestamp.toISOString().split("T")[0];
      const currentPingDate = pingTime.toISOString().split("T")[0];

      if (lastPingDate === currentPingDate) {
        distanceFromPrev = calculateDistanceKM(
          Number(lastPing.latitude),
          Number(lastPing.longitude),
          Number(latitude),
          Number(longitude)
        );
      }
    }

    const newPing = await prisma.gpsPing.create({
      data: {
        userId,
        latitude: Number(latitude),
        longitude: Number(longitude),
        timestamp: pingTime,
        distanceFromPrev: Number(distanceFromPrev.toFixed(3)),
        trackingStartPoint: trackingStartPoint as TrackingStartPoint,
      },
    });

    res.status(201).json({
      message: "GPS ping recorded",
      ping: newPing,
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
};

export const getRoute = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const userId = req.params.userId as string;
  const date = req.params.date as string;

  try {
    if (req.user?.id !== userId && req.user?.role === "SALES_EXECUTIVE") {
      res.status(403).json({ error: "Access denied." });
      return;
    }

    const startOfDay = new Date(date);
    startOfDay.setHours(0, 0, 0, 0);
    const endOfDay = new Date(date);
    endOfDay.setHours(23, 59, 59, 999);

    const pings = await prisma.gpsPing.findMany({
      where: {
        userId,
        timestamp: { gte: startOfDay, lte: endOfDay },
      },
      orderBy: { timestamp: "asc" },
    });

    // Mark segments as "Signal Lost" if the gap between consecutive pings is > 5 minutes
    const routeSegments = [];
    for (let i = 0; i < pings.length; i++) {
      const current = pings[i];
      let signalLost = false;

      if (i > 0) {
        const prev = pings[i - 1];
        const gapMinutes = (current.timestamp.getTime() - prev.timestamp.getTime()) / (1000 * 60);
        if (gapMinutes > 5) {
          signalLost = true;
        }
      }

      routeSegments.push({
        id: current.id,
        latitude: Number(current.latitude),
        longitude: Number(current.longitude),
        timestamp: current.timestamp,
        distanceFromPrev: Number(current.distanceFromPrev),
        trackingStartPoint: current.trackingStartPoint,
        signalLost,
      });
    }

    res.status(200).json({ route: routeSegments });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
};

export const getGpsSummary = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const userId = req.params.userId as string;
  const date = req.params.date as string;

  try {
    if (req.user?.id !== userId && req.user?.role === "SALES_EXECUTIVE") {
      res.status(403).json({ error: "Access denied." });
      return;
    }

    const startOfDay = new Date(date);
    startOfDay.setHours(0, 0, 0, 0);
    const endOfDay = new Date(date);
    endOfDay.setHours(23, 59, 59, 999);

    const pings = await prisma.gpsPing.findMany({
      where: {
        userId,
        timestamp: { gte: startOfDay, lte: endOfDay },
      },
      orderBy: { timestamp: "asc" },
    });

    if (pings.length === 0) {
      res.status(200).json({
        totalDistanceKm: 0,
        travelTimeMinutes: 0,
        startPoint: null,
        endPoint: null,
        pingCount: 0,
      });
      return;
    }

    const totalDistance = pings.reduce((acc, p) => acc + Number(p.distanceFromPrev), 0);

    const firstPing = pings[0];
    const lastPing = pings[pings.length - 1];
    const travelTimeMinutes = Math.floor((lastPing.timestamp.getTime() - firstPing.timestamp.getTime()) / (1000 * 60));

    res.status(200).json({
      totalDistanceKm: Number(totalDistance.toFixed(3)),
      travelTimeMinutes,
      startPoint: {
        latitude: Number(firstPing.latitude),
        longitude: Number(firstPing.longitude),
        timestamp: firstPing.timestamp,
        type: firstPing.trackingStartPoint,
      },
      endPoint: {
        latitude: Number(lastPing.latitude),
        longitude: Number(lastPing.longitude),
        timestamp: lastPing.timestamp,
      },
      pingCount: pings.length,
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
};
