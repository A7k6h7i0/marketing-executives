import { Response } from "express";
import bcrypt from "bcryptjs";
import { prisma } from "../config/prisma";
import { AuthenticatedRequest } from "../middlewares/auth";
import { Role, AttendanceStatus, ResolutionStatus, LeadStatus, Grade } from "@prisma/client";

// Get role-based filtering scope
const getRoleScopeFilter = (user?: { id: string; role: Role; region: string | null }) => {
  if (!user) return {};
  if (user.role === Role.SUPER_ADMIN) return {};
  if (user.role === Role.REGIONAL_MANAGER || user.role === Role.SALES_MANAGER) {
    return user.region ? { region: user.region } : {};
  }
  return { id: user.id }; // Sales Executive can only access their own data
};

export const getKpis = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    const scope = getRoleScopeFilter(req.user);

    const now = new Date();
    const todayStart = new Date(now);
    todayStart.setHours(0, 0, 0, 0);
    const todayEnd = new Date(now);
    todayEnd.setHours(23, 59, 59, 999);

    // 1. Active Executives: Count of users with active attendance today (logoutTime is null)
    const activeExecutives = await prisma.attendance.count({
      where: {
        logoutTime: null,
        loginTime: { gte: todayStart, lte: todayEnd },
        user: scope,
      },
    });

    // 2. Total Distance Covered today
    const distanceResult = await prisma.gpsPing.aggregate({
      where: {
        timestamp: { gte: todayStart, lte: todayEnd },
        user: scope,
      },
      _sum: {
        distanceFromPrev: true,
      },
    });
    const totalDistance = Number(distanceResult._sum.distanceFromPrev || 0);

    // 3. Total Visits Completed today
    const totalVisits = await prisma.visit.count({
      where: {
        checkinTime: { gte: todayStart, lte: todayEnd },
        checkoutTime: { not: null },
        user: scope,
      },
    });

    // 4. Sales Generated today
    const salesResult = await prisma.visit.aggregate({
      where: {
        checkinTime: { gte: todayStart, lte: todayEnd },
        checkoutTime: { not: null },
        user: scope,
      },
      _sum: {
        salesValue: true,
      },
    });
    const totalSales = Number(salesResult._sum.salesValue || 0);

    // 5. Leads Created today
    const leadsCreated = await prisma.lead.count({
      where: {
        createdAt: { gte: todayStart, lte: todayEnd },
        user: scope,
      },
    });

    // 6. Leads Converted today
    const leadsConverted = await prisma.lead.count({
      where: {
        createdAt: { gte: todayStart, lte: todayEnd },
        leadStatus: LeadStatus.CONVERTED,
        user: scope,
      },
    });

    // 7. Open Incident Count (OPEN or IN_PROGRESS)
    const incidentCount = await prisma.incident.count({
      where: {
        resolutionStatus: { in: [ResolutionStatus.OPEN, ResolutionStatus.IN_PROGRESS] },
        user: scope,
      },
    });

    // 8. Average Outlet Rating (Daily, all time)
    const ratingResult = await prisma.outlet.aggregate({
      _avg: {
        overallRating: true,
      },
    });
    const avgOutletRating = Number(ratingResult._avg.overallRating || 0);

    res.status(200).json({
      activeExecutives,
      totalDistanceCoveredKm: Number(totalDistance.toFixed(2)),
      totalVisitsCompleted: totalVisits,
      salesGenerated: Number(totalSales.toFixed(2)),
      leadsCreated,
      leadsConverted,
      openIncidents: incidentCount,
      avgOutletRating: Number(avgOutletRating.toFixed(2)),
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
};

export const getReports = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const { reportType } = req.params;
  const from = req.query.from ? new Date(req.query.from as string) : new Date(Date.now() - 30 * 24 * 60 * 60 * 1000); // Default 30 days
  const to = req.query.to ? new Date(req.query.to as string) : new Date();
  const userIdFilter = req.query.userId as string;
  const regionIdFilter = req.query.regionId as string;

  try {
    const scope = getRoleScopeFilter(req.user);

    // Combine manual filters with role scopes
    const userFilter: any = { ...scope };
    if (userIdFilter) userFilter.id = userIdFilter;
    if (regionIdFilter) userFilter.region = regionIdFilter;

    switch (reportType) {
      case "attendance": {
        const data = await prisma.attendance.findMany({
          where: {
            loginTime: { gte: from, lte: to },
            user: userFilter,
          },
          include: {
            user: { select: { id: true, email: true, phone: true, region: true } },
          },
          orderBy: { loginTime: "desc" },
        });
        res.status(200).json({ reportType, data });
        break;
      }

      case "breaks": {
        const data = await prisma.break.findMany({
          where: {
            breakStartTime: { gte: from, lte: to },
            user: userFilter,
          },
          include: {
            user: { select: { id: true, email: true, region: true } },
          },
          orderBy: { breakStartTime: "desc" },
        });
        res.status(200).json({ reportType, data });
        break;
      }

      case "gps": {
        const data = await prisma.gpsPing.findMany({
          where: {
            timestamp: { gte: from, lte: to },
            user: userFilter,
          },
          include: {
            user: { select: { id: true, email: true, region: true } },
          },
          orderBy: { timestamp: "desc" },
        });
        res.status(200).json({ reportType, data });
        break;
      }

      case "visits": {
        const data = await prisma.visit.findMany({
          where: {
            checkinTime: { gte: from, lte: to },
            user: userFilter,
          },
          include: {
            user: { select: { id: true, email: true, region: true } },
            outlet: true,
          },
          orderBy: { checkinTime: "desc" },
        });
        res.status(200).json({ reportType, data });
        break;
      }

      case "sales": {
        const data = await prisma.visit.findMany({
          where: {
            checkinTime: { gte: from, lte: to },
            checkoutTime: { not: null },
            salesValue: { gt: 0 },
            user: userFilter,
          },
          include: {
            user: { select: { id: true, email: true, region: true } },
            outlet: true,
          },
          orderBy: { checkinTime: "desc" },
        });
        res.status(200).json({ reportType, data });
        break;
      }

      case "incidents": {
        const data = await prisma.incident.findMany({
          where: {
            createdAt: { gte: from, lte: to },
            user: userFilter,
          },
          include: {
            user: { select: { id: true, email: true, region: true } },
            manager: { select: { id: true, email: true } },
          },
          orderBy: { createdAt: "desc" },
        });
        res.status(200).json({ reportType, data });
        break;
      }

      case "lead-conversion": {
        const data = await prisma.lead.findMany({
          where: {
            createdAt: { gte: from, lte: to },
            user: userFilter,
          },
          include: {
            user: { select: { id: true, email: true, region: true } },
            convertedOutlet: true,
          },
          orderBy: { createdAt: "desc" },
        });
        res.status(200).json({ reportType, data });
        break;
      }

      case "outlet-grading": {
        const data = await prisma.rating.findMany({
          where: {
            reviewDate: { gte: from, lte: to },
            reviewer: userFilter,
          },
          include: {
            reviewer: { select: { id: true, email: true } },
            outlet: true,
          },
          orderBy: { reviewDate: "desc" },
        });
        res.status(200).json({ reportType, data });
        break;
      }

      case "route-efficiency": {
        const data = await prisma.dailyPlan.findMany({
          where: {
            planDate: { gte: from, lte: to },
            user: userFilter,
          },
          include: {
            user: { select: { id: true, email: true, region: true } },
          },
          orderBy: { planDate: "desc" },
        });
        res.status(200).json({ reportType, data });
        break;
      }

      default:
        res.status(400).json({ error: `Invalid reportType: ${reportType}` });
    }
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
};

export const getUsers = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    const scope = getRoleScopeFilter(req.user);

    const users = await prisma.user.findMany({
      where: scope,
      select: {
        id: true,
        email: true,
        phone: true,
        role: true,
        region: true,
        status: true,
        createdAt: true,
      },
      orderBy: { email: "asc" },
    });

    res.status(200).json({ users });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
};

export const createUser = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const { email, password, phone, name, role, region } = req.body;

  try {
    if (!email || !password) {
      res.status(400).json({ error: "Email and password are required." });
      return;
    }

    const existingUser = await prisma.user.findUnique({ where: { email } });
    if (existingUser) {
      res.status(400).json({ error: "User already exists with this email." });
      return;
    }

    const passwordHash = await bcrypt.hash(password, 10);

    let resolvedRole: Role = Role.SALES_EXECUTIVE;
    if (role) {
      const normalized = String(role).toUpperCase().replace(/ /g, "_");
      if (normalized === "EXECUTIVE" || normalized === "SALES_EXECUTIVE") {
        resolvedRole = Role.SALES_EXECUTIVE;
      } else if (Object.values(Role).includes(normalized as Role)) {
        resolvedRole = normalized as Role;
      } else {
        res.status(400).json({ error: `Invalid role. Use SALES_EXECUTIVE, SALES_MANAGER, etc.` });
        return;
      }
    }

    const user = await prisma.user.create({
      data: {
        email,
        passwordHash,
        phone,
        name,
        role: resolvedRole,
        region,
      },
      select: {
        id: true,
        email: true,
        phone: true,
        name: true,
        role: true,
        region: true,
        status: true,
        createdAt: true,
      },
    });

    res.status(201).json({ message: "User account created", user });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
};

export const updateUser = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const userId = req.params.userId as string;
  const { role, region, status } = req.body;

  try {
    const user = await prisma.user.findUnique({
      where: { id: userId },
    });

    if (!user) {
      res.status(404).json({ error: "User not found." });
      return;
    }

    if (role && !Object.values(Role).includes(role)) {
      res.status(400).json({ error: `Invalid role. Must be one of: ${Object.values(Role).join(", ")}` });
      return;
    }

    const updatedUser = await prisma.user.update({
      where: { id: userId },
      data: {
        role: role ? (role as Role) : undefined,
        region,
        status,
      },
      select: {
        id: true,
        email: true,
        phone: true,
        role: true,
        region: true,
        status: true,
      },
    });

    res.status(200).json({
      message: "User updated successfully",
      user: updatedUser,
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
};

/** Live field check-ins for managers: who, where, selfie, GPS, times. */
export const getLiveVisits = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    const scope = getRoleScopeFilter(req.user);
    const days = Math.min(Math.max(parseInt(String(req.query.days || "1"), 10) || 1, 1), 30);
    const since = new Date();
    since.setHours(0, 0, 0, 0);
    if (days > 1) {
      since.setDate(since.getDate() - (days - 1));
    }

    const visits = await prisma.visit.findMany({
      where: {
        checkinTime: { gte: since },
        user: scope,
      },
      include: {
        user: { select: { id: true, email: true, phone: true, name: true, region: true, role: true } },
        outlet: true,
      },
      orderBy: { checkinTime: "desc" },
      take: 200,
    });

    res.status(200).json({
      visits: visits.map((v) => ({
        id: v.id,
        executiveId: v.userId,
        executiveName: v.user.name || v.user.email,
        executiveEmail: v.user.email,
        executivePhone: v.user.phone,
        region: v.user.region,
        outletId: v.outletId,
        outletName: v.outlet.name,
        outletAddress: v.outlet.address,
        checkInTime: v.checkinTime,
        checkOutTime: v.checkoutTime,
        gpsLat: Number(v.gpsLat),
        gpsLng: Number(v.gpsLng),
        selfieUrl: v.selfieUrl,
        salesValue: Number(v.salesValue),
        remarks: v.remarks,
        status: v.checkoutTime ? "COMPLETED" : "IN_VISIT",
      })),
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
};

async function ensureAppSettings() {
  return prisma.appSetting.upsert({
    where: { id: "default" },
    create: {
      id: "default",
      selfieRequired: false,
      minVisitDurationMinutes: 3,
    },
    update: {},
  });
}

/** Field policy: selfie required Yes/No + auto-visit dwell minutes. */
export const getAppSettings = async (_req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    const settings = await ensureAppSettings();
    res.status(200).json({
      selfieRequired: settings.selfieRequired,
      minVisitDurationMinutes: settings.minVisitDurationMinutes,
      updatedAt: settings.updatedAt,
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
};

export const updateAppSettings = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    await ensureAppSettings();
    const { selfieRequired, minVisitDurationMinutes } = req.body;

    const data: { selfieRequired?: boolean; minVisitDurationMinutes?: number } = {};
    if (typeof selfieRequired === "boolean") data.selfieRequired = selfieRequired;
    if (minVisitDurationMinutes !== undefined) {
      const minutes = Number(minVisitDurationMinutes);
      if (!Number.isFinite(minutes) || minutes < 1 || minutes > 120) {
        res.status(400).json({ error: "minVisitDurationMinutes must be between 1 and 120." });
        return;
      }
      data.minVisitDurationMinutes = Math.round(minutes);
    }

    const settings = await prisma.appSetting.update({
      where: { id: "default" },
      data,
    });

    res.status(200).json({
      message: "Settings updated",
      selfieRequired: settings.selfieRequired,
      minVisitDurationMinutes: settings.minVisitDurationMinutes,
      updatedAt: settings.updatedAt,
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
};
