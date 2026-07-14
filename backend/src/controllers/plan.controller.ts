import { Response } from "express";
import { prisma } from "../config/prisma";
import { AuthenticatedRequest } from "../middlewares/auth";

// Predefined routes/areas (can be fetched dynamically or mocked based on user region)
const PREDEFINED_ROUTES = [
  { id: "route-downtown", name: "Downtown Retail Zone", region: "North" },
  { id: "route-westside", name: "Westside Commercial Hub", region: "West" },
  { id: "route-suburbs", name: "East Suburban Markets", region: "East" },
  { id: "route-south", name: "Southside Shopping Districts", region: "South" },
];

export const getRoutes = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    const userRegion = req.user?.region || "North";
    // Filter routes by user region if set, otherwise return all
    const filteredRoutes = PREDEFINED_ROUTES.filter(
      (r) => !req.user?.region || r.region.toLowerCase() === userRegion.toLowerCase()
    );

    res.status(200).json({ routes: filteredRoutes });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
};

export const getRouteOutlets = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const routeId = req.params.routeId as string;

  try {
    // Find outlets. In a real system, outlets are linked to routes.
    // For now, we query outlets that match the areaName or just return all available outlets
    // as a fallback if the database is empty.
    const route = PREDEFINED_ROUTES.find((r) => r.id === routeId);
    if (!route) {
      res.status(404).json({ error: "Route not found." });
      return;
    }

    const outlets = await prisma.outlet.findMany({
      where: {
        address: { contains: route.name.split(" ")[0], mode: "insensitive" },
      },
    });

    // If no specific outlets are found for this mock route, return some outlets (or all)
    if (outlets.length === 0) {
      const allOutlets = await prisma.outlet.findMany({ take: 10 });
      res.status(200).json({ routeId, routeName: route.name, outlets: allOutlets });
      return;
    }

    res.status(200).json({ routeId, routeName: route.name, outlets });
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

    // Check if plan already exists for today
    const existingPlan = await prisma.dailyPlan.findFirst({
      where: {
        userId,
        planDate: targetDate,
      },
    });

    let plan;
    if (existingPlan) {
      // Update existing plan
      plan = await prisma.dailyPlan.update({
        where: { id: existingPlan.id },
        data: {
          routeId,
          areaName,
          plannedVisits,
        },
      });
    } else {
      // Create new plan
      plan = await prisma.dailyPlan.create({
        data: {
          userId,
          routeId,
          areaName,
          plannedVisits,
          planDate: targetDate,
        },
      });
    }

    res.status(200).json({
      message: "Daily plan saved successfully",
      plan,
    });
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
      where: {
        userId,
        planDate: today,
      },
    });

    if (!plan) {
      res.status(200).json({
        plan: null,
        outlets: [],
        progress: { planned: 0, completed: 0, percentage: 0 },
      });
      return;
    }

    // Load outlets for this plan's area.
    // In our simplified setup, we can fetch all outlets in this area or just the first few
    const outlets = await prisma.outlet.findMany({
      take: 10,
    });

    // Check visit status for each outlet today
    const todayStart = new Date(today);
    todayStart.setHours(0, 0, 0, 0);
    const todayEnd = new Date(today);
    todayEnd.setHours(23, 59, 59, 999);

    const visits = await prisma.visit.findMany({
      where: {
        userId,
        checkinTime: { gte: todayStart, lte: todayEnd },
      },
    });

    const completedOutletIds = new Set(visits.map((v) => v.outletId));

    const outletsWithStatus = outlets.map((o) => ({
      ...o,
      visitStatus: completedOutletIds.has(o.id) ? "COMPLETED" : "PLANNED",
      visit: visits.find((v) => v.outletId === o.id) || null,
    }));

    const completedVisits = outletsWithStatus.filter((o) => o.visitStatus === "COMPLETED").length;

    // Update completed count in the daily plan if it has changed
    if (plan.completedVisits !== completedVisits) {
      await prisma.dailyPlan.update({
        where: { id: plan.id },
        data: { completedVisits },
      });
      plan.completedVisits = completedVisits;
    }

    res.status(200).json({
      plan,
      outlets: outletsWithStatus,
      progress: {
        planned: plan.plannedVisits,
        completed: completedVisits,
        percentage: plan.plannedVisits > 0 ? Number(((completedVisits / plan.plannedVisits) * 100).toFixed(1)) : 0,
      },
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
};
