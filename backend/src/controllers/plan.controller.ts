import { Response } from "express";
import { prisma } from "../config/prisma";
import { AuthenticatedRequest } from "../middlewares/auth";

export const getRoutes = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    const userRegion = req.user?.region;

    const routes = await prisma.territoryRoute.findMany({
      where: userRegion
        ? { region: { equals: userRegion, mode: "insensitive" } }
        : undefined,
      include: { _count: { select: { outlets: true } } },
      orderBy: { name: "asc" },
    });

    res.status(200).json({
      routes: routes.map((r) => ({
        id: r.id,
        name: r.name,
        region: r.region,
        outletCount: r._count.outlets,
      })),
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
};

export const getRouteOutlets = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const routeId = req.params.routeId as string;

  try {
    const route = await prisma.territoryRoute.findUnique({
      where: { id: routeId },
      include: { outlets: { orderBy: { name: "asc" } } },
    });

    if (!route) {
      res.status(404).json({ error: "Route not found." });
      return;
    }

    res.status(200).json({
      routeId: route.id,
      routeName: route.name,
      outlets: route.outlets.map((o) => ({
        id: o.id,
        name: o.name,
        address: o.address,
        latitude: Number(o.gpsLat),
        longitude: Number(o.gpsLng),
        gpsLat: Number(o.gpsLat),
        gpsLng: Number(o.gpsLng),
        grade: o.grade,
        overallRating: o.overallRating ? Number(o.overallRating) : null,
        contactPhone: o.contactPhone,
        contactEmail: o.contactEmail,
      })),
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
};

export const createOrUpdatePlan = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const userId = req.user?.id;
  const { routeId, areaName, plannedVisits, planDate } = req.body;

  if (!userId || !areaName || plannedVisits === undefined) {
    res.status(400).json({ error: "areaName and plannedVisits are required." });
    return;
  }

  try {
    const targetDate = planDate ? new Date(planDate) : new Date();
    targetDate.setHours(0, 0, 0, 0);

    const existingPlan = await prisma.dailyPlan.findFirst({
      where: { userId, planDate: targetDate },
    });

    const plan = existingPlan
      ? await prisma.dailyPlan.update({
          where: { id: existingPlan.id },
          data: { routeId: routeId || null, areaName, plannedVisits },
        })
      : await prisma.dailyPlan.create({
          data: {
            userId,
            routeId: routeId || null,
            areaName,
            plannedVisits,
            planDate: targetDate,
          },
        });

    res.status(200).json({ message: "Daily plan saved successfully", plan });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
};

export const getTodayPlan = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const userId = req.params.userId as string;

  try {
    if (req.user?.id !== userId && req.user?.role === "SALES_EXECUTIVE") {
      res.status(403).json({ error: "Access denied." });
      return;
    }

    const today = new Date();
    today.setHours(0, 0, 0, 0);

    const plan = await prisma.dailyPlan.findFirst({
      where: { userId, planDate: today },
    });

    if (!plan) {
      res.status(200).json({
        plan: null,
        outlets: [],
        progress: { planned: 0, completed: 0, percentage: 0 },
      });
      return;
    }

    const outlets = plan.routeId
      ? await prisma.outlet.findMany({
          where: { routeId: plan.routeId },
          orderBy: { name: "asc" },
        })
      : await prisma.outlet.findMany({ take: 50, orderBy: { name: "asc" } });

    const todayStart = new Date(today);
    const todayEnd = new Date(today);
    todayEnd.setHours(23, 59, 59, 999);

    const visits = await prisma.visit.findMany({
      where: {
        userId,
        checkinTime: { gte: todayStart, lte: todayEnd },
      },
    });

    const visitByOutlet = new Map(visits.map((v) => [v.outletId, v]));

    const outletsWithStatus = outlets.map((o) => {
      const visit = visitByOutlet.get(o.id);
      let visitStatus = "PENDING";
      if (visit?.checkoutTime) visitStatus = "COMPLETED";
      else if (visit) visitStatus = "IN_PROGRESS";

      return {
        id: o.id,
        name: o.name,
        address: o.address,
        latitude: Number(o.gpsLat),
        longitude: Number(o.gpsLng),
        gpsLat: Number(o.gpsLat),
        gpsLng: Number(o.gpsLng),
        grade: o.grade,
        overallRating: o.overallRating ? Number(o.overallRating) : null,
        visitStatus,
      };
    });

    const completed = outletsWithStatus.filter((o) => o.visitStatus === "COMPLETED").length;
    const planned = plan.plannedVisits || outletsWithStatus.length;

    res.status(200).json({
      plan,
      outlets: outletsWithStatus,
      progress: {
        planned,
        completed,
        percentage: planned > 0 ? Number(((completed / planned) * 100).toFixed(1)) : 0,
      },
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
};
