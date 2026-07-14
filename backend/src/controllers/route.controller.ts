import { Response } from "express";
import { prisma } from "../config/prisma";
import { AuthenticatedRequest } from "../middlewares/auth";
import { calculateDistanceKM } from "../utils/distance";
import axios from "axios";

// Nearest Neighbor Traveling Salesperson (TSP) Solver
const solveMockTsp = (
  startLat: number,
  startLng: number,
  locations: Array<{ id: string; type: "OUTLET" | "LEAD"; name: string; lat: number; lng: number }>
) => {
  const unvisited = [...locations];
  const orderedRoute = [];
  let currentLat = startLat;
  let currentLng = startLng;
  let totalDistanceKm = 0;
  let currentTime = new Date();

  const AVG_SPEED_KMH = 30; // Average city speed 30 KM/h

  let sequenceOrder = 1;

  while (unvisited.length > 0) {
    let nearestIdx = -1;
    let minDistance = Infinity;

    for (let i = 0; i < unvisited.length; i++) {
      const dist = calculateDistanceKM(currentLat, currentLng, unvisited[i].lat, unvisited[i].lng);
      if (dist < minDistance) {
        minDistance = dist;
        nearestIdx = i;
      }
    }

    if (nearestIdx !== -1) {
      const nextStop = unvisited.splice(nearestIdx, 1)[0];
      totalDistanceKm += minDistance;

      // Calculate travel time in minutes: (distance / speed) * 60 minutes
      const travelTimeMin = Math.round((minDistance / AVG_SPEED_KMH) * 60);

      // Add travel time and spending time (e.g. 15 mins per outlet visit)
      const spendingTimeMin = 15;
      currentTime = new Date(currentTime.getTime() + (travelTimeMin + spendingTimeMin) * 60000);

      orderedRoute.push({
        id: nextStop.id,
        type: nextStop.type,
        name: nextStop.name,
        latitude: nextStop.lat,
        longitude: nextStop.lng,
        eta: currentTime.toISOString(),
        order: sequenceOrder++,
        distanceFromLastKm: Number(minDistance.toFixed(2)),
        travelTimeMin,
      });

      currentLat = nextStop.lat;
      currentLng = nextStop.lng;
    }
  }

  const totalTravelTimeMin = Math.round((totalDistanceKm / AVG_SPEED_KMH) * 60) + orderedRoute.length * 15;

  return {
    orderedRoute,
    estimatedDistanceKm: Number(totalDistanceKm.toFixed(2)),
    estimatedTravelTimeMin: totalTravelTimeMin,
  };
};

export const optimizeRoute = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const userId = req.user?.id;
  const { outletIds, leadIds, startLat, startLng } = req.body;

  if (!userId || startLat === undefined || startLng === undefined) {
    res.status(400).json({ error: "startLat and startLng are required." });
    return;
  }

  try {
    const outlets = outletIds && Array.isArray(outletIds) && outletIds.length > 0
      ? await prisma.outlet.findMany({ where: { id: { in: outletIds } } })
      : [];

    const leads = leadIds && Array.isArray(leadIds) && leadIds.length > 0
      ? await prisma.lead.findMany({ where: { id: { in: leadIds } } })
      : [];

    const locations = [
      ...outlets.map((o) => ({
        id: o.id,
        type: "OUTLET" as const,
        name: o.name,
        lat: Number(o.gpsLat),
        lng: Number(o.gpsLng),
      })),
      ...leads.map((l) => ({
        id: l.id,
        type: "LEAD" as const,
        name: l.businessName,
        lat: Number(l.gpsLat),
        lng: Number(l.gpsLng),
      })),
    ];

    if (locations.length === 0) {
      res.status(400).json({ error: "No outlets or leads provided to optimize." });
      return;
    }

    const apiKey = process.env.GOOGLE_MAPS_API_KEY;

    // Standard Google Waypoint Optimization
    if (apiKey && apiKey !== "AIzaSyYourKeyHere" && locations.length <= 25) {
      try {
        const origin = `${startLat},${startLng}`;
        const destination = `${startLat},${startLng}`; // Return to start
        const waypoints = `optimize:true|` + locations.map((l) => `${l.lat},${l.lng}`).join("|");

        const url = `https://maps.googleapis.com/maps/api/directions/json?origin=${origin}&destination=${destination}&waypoints=${waypoints}&key=${apiKey}`;
        const response = await axios.get(url);

        if (response.data.status === "OK") {
          const routeData = response.data.routes[0];
          const waypointOrder = routeData.waypoint_order; // [2, 0, 1] meaning locations[2] is first stop, etc.

          let totalDist = 0;
          let totalTime = 0;
          const legs = routeData.legs;

          const orderedRoute = waypointOrder.map((index: number, seq: number) => {
            const leg = legs[seq];
            const loc = locations[index];
            totalDist += leg.distance.value / 1000;
            totalTime += leg.duration.value / 60;

            const etaTime = new Date(Date.now() + totalTime * 60000);

            return {
              id: loc.id,
              type: loc.type,
              name: loc.name,
              latitude: loc.lat,
              longitude: loc.lng,
              eta: etaTime.toISOString(),
              order: seq + 1,
              distanceFromLastKm: Number((leg.distance.value / 1000).toFixed(2)),
              travelTimeMin: Math.round(leg.duration.value / 60),
            };
          });

          const optimizedRoute = await prisma.optimizedRoute.create({
            data: {
              userId,
              totalStops: locations.length,
              estimatedDistanceKm: Number((totalDist).toFixed(2)),
              estimatedTravelTimeMin: Math.round(totalTime),
              stopSequence: orderedRoute as any,
            },
          });

          res.status(200).json({
            message: "Optimized route generated via Google Directions",
            route: optimizedRoute,
          });
          return;
        }
      } catch (err: any) {
        console.warn("Google Directions optimization failed, falling back to TSP solver", err.message);
      }
    }

    // Math Fallback (Nearest Neighbor TSP) if Google is unconfigured, failed, or has > 25 stops
    const tspResult = solveMockTsp(parseFloat(startLat), parseFloat(startLng), locations);

    const optimizedRoute = await prisma.optimizedRoute.create({
      data: {
        userId,
        totalStops: locations.length,
        estimatedDistanceKm: tspResult.estimatedDistanceKm,
        estimatedTravelTimeMin: tspResult.estimatedTravelTimeMin,
        stopSequence: tspResult.orderedRoute as any,
      },
    });

    res.status(200).json({
      message: "Optimized route generated via TSP Nearest-Neighbor Solver",
      route: optimizedRoute,
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
};

export const getOptimizedRoute = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const routeId = req.params.routeId as string;

  try {
    const route = await prisma.optimizedRoute.findUnique({
      where: { id: routeId },
    });

    if (!route) {
      res.status(404).json({ error: "Optimized route not found." });
      return;
    }

    res.status(200).json({ route });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
};

export const skipStop = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const routeId = req.params.routeId as string;
  const stopId = req.params.stopId as string;

  try {
    const route = await prisma.optimizedRoute.findUnique({
      where: { id: routeId },
    });

    if (!route) {
      res.status(404).json({ error: "Optimized route not found." });
      return;
    }

    const sequence = route.stopSequence as any[];
    const filteredSequence = sequence.filter((stop: any) => stop.id !== stopId);

    if (filteredSequence.length === sequence.length) {
      res.status(404).json({ error: "Stop ID not found in route sequence." });
      return;
    }

    // Re-index the sequence order
    const updatedSequence = filteredSequence.map((stop: any, idx: number) => ({
      ...stop,
      order: idx + 1,
    }));

    // Recompute estimations
    const totalStops = updatedSequence.length;
    const totalDistance = updatedSequence.reduce((sum: number, stop: any) => sum + (stop.distanceFromLastKm || 0), 0);
    const totalTravelTime = updatedSequence.reduce((sum: number, stop: any) => sum + (stop.travelTimeMin || 0), 0) + (totalStops * 15);

    const updatedRoute = await prisma.optimizedRoute.update({
      where: { id: routeId },
      data: {
        totalStops,
        estimatedDistanceKm: Number(totalDistance.toFixed(2)),
        estimatedTravelTimeMin: totalTravelTime,
        stopSequence: updatedSequence as any,
      },
    });

    res.status(200).json({
      message: "Stop skipped. Route recalculated.",
      route: updatedRoute,
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
};
