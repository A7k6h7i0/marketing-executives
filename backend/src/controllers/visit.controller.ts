import { Response } from "express";
import { prisma } from "../config/prisma";
import { AuthenticatedRequest } from "../middlewares/auth";
import { calculateDistanceKM } from "../utils/distance";
import { SyncStatus } from "@prisma/client";

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const isUuid = (value: unknown): value is string =>
  typeof value === "string" && UUID_RE.test(value);

type OutletPayload = {
  name?: string;
  address?: string;
  contactPhone?: string;
  contactEmail?: string;
  gpsLat?: number;
  gpsLng?: number;
  latitude?: number;
  longitude?: number;
};

async function resolveOutletId(
  outletId: unknown,
  outletPayload: OutletPayload | undefined,
  checkInLat: number,
  checkInLng: number
) {
  if (isUuid(outletId)) {
    const existing = await prisma.outlet.findUnique({ where: { id: outletId } });
    if (existing) return existing.id;
  }

  const name = outletPayload?.name?.trim();
  const lat = Number(outletPayload?.gpsLat ?? outletPayload?.latitude ?? checkInLat);
  const lng = Number(outletPayload?.gpsLng ?? outletPayload?.longitude ?? checkInLng);

  if (!name || Number.isNaN(lat) || Number.isNaN(lng)) {
    return null;
  }

  const candidates = await prisma.outlet.findMany({
    where: { name: { equals: name, mode: "insensitive" } },
    take: 20,
  });

  const match = candidates.find((o) => {
    const dLat = Math.abs(Number(o.gpsLat) - lat);
    const dLng = Math.abs(Number(o.gpsLng) - lng);
    return dLat < 0.001 && dLng < 0.001;
  });
  if (match) return match.id;

  const created = await prisma.outlet.create({
    data: {
      name,
      address: outletPayload?.address || name,
      contactPhone: outletPayload?.contactPhone || null,
      contactEmail: outletPayload?.contactEmail || null,
      gpsLat: lat,
      gpsLng: lng,
    },
  });
  return created.id;
}

export const getProducts = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const query = ((req.query.q as string) || "").toLowerCase();
  try {
    const products = await prisma.product.findMany({
      where: query
        ? {
            OR: [
              { name: { contains: query, mode: "insensitive" } },
              { sku: { contains: query, mode: "insensitive" } },
            ],
          }
        : undefined,
      orderBy: { name: "asc" },
    });

    res.status(200).json({
      products: products.map((p) => ({
        id: p.id,
        sku: p.sku,
        name: p.name,
        unitPrice: Number(p.unitPrice),
      })),
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
};

export const checkIn = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const userId = req.user?.id;
  const { outletId, outlet, gpsLat, gpsLng, selfieUrl, managerOverrideFlag, autoComplete } = req.body;

  if (!userId || gpsLat === undefined || gpsLng === undefined) {
    res.status(400).json({ error: "gpsLat and gpsLng are required." });
    return;
  }

  try {
    const settings = await prisma.appSetting.upsert({
      where: { id: "default" },
      create: { id: "default", selfieRequired: false, minVisitDurationMinutes: 3 },
      update: {},
    });

    const resolvedSelfie =
      selfieUrl && String(selfieUrl).trim().length > 0
        ? String(selfieUrl)
        : "auto-detected";

    if (settings.selfieRequired && resolvedSelfie === "auto-detected" && !autoComplete) {
      res.status(400).json({ error: "Selfie is required for check-in (admin policy)." });
      return;
    }
    const openVisit = await prisma.visit.findFirst({
      where: { userId, checkoutTime: null },
    });
    if (openVisit) {
      res.status(409).json({
        error: "Another outlet visit is already active. Please check out first.",
        activeVisitId: openVisit.id,
        activeOutletId: openVisit.outletId,
      });
      return;
    }

    const resolvedOutletId = await resolveOutletId(
      outletId,
      outlet,
      Number(gpsLat),
      Number(gpsLng)
    );

    if (!resolvedOutletId) {
      res.status(400).json({
        error: "outletId (UUID) or outlet { name, gpsLat, gpsLng } is required.",
      });
      return;
    }

    const outletRecord = await prisma.outlet.findUnique({ where: { id: resolvedOutletId } });
    if (!outletRecord) {
      res.status(404).json({ error: "Outlet not found in master database." });
      return;
    }

    const distanceMeters =
      calculateDistanceKM(
        Number(outletRecord.gpsLat),
        Number(outletRecord.gpsLng),
        Number(gpsLat),
        Number(gpsLng)
      ) * 1000;

    const thresholdMeters = Number(process.env.GEOFENCE_THRESHOLD_METERS || 100);

    if (distanceMeters > thresholdMeters && !managerOverrideFlag) {
      res.status(400).json({
        error: "Geofence warning: You are too far from this outlet.",
        distanceMeters: Number(distanceMeters.toFixed(1)),
        thresholdMeters,
        requiresOverride: true,
      });
      return;
    }

    const visit = await prisma.visit.create({
      data: {
        userId,
        outletId: resolvedOutletId,
        gpsLat: Number(gpsLat),
        gpsLng: Number(gpsLng),
        selfieUrl: resolvedSelfie,
        checkinTime: new Date(),
        checkoutTime: autoComplete ? new Date() : null,
        remarks: autoComplete
          ? `Auto-completed after dwell at outlet (selfie policy: ${settings.selfieRequired ? "required" : "off"}).`
          : undefined,
        syncStatus: SyncStatus.SYNCED,
      },
    });

    if (autoComplete) {
      const today = new Date();
      today.setHours(0, 0, 0, 0);
      const plan = await prisma.dailyPlan.findFirst({
        where: { userId, planDate: today },
      });
      if (plan) {
        const todayEnd = new Date(today);
        todayEnd.setHours(23, 59, 59, 999);
        const completedVisitsCount = await prisma.visit.count({
          where: {
            userId,
            checkinTime: { gte: today, lte: todayEnd },
            checkoutTime: { not: null },
          },
        });
        await prisma.dailyPlan.update({
          where: { id: plan.id },
          data: { completedVisits: completedVisitsCount },
        });
      }
    }

    res.status(201).json({
      message: autoComplete ? "Visit auto-completed" : "Check-in successful",
      visit,
      distanceFromOutletMeters: Number(distanceMeters.toFixed(1)),
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
};

export const placeOrder = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const visitId = req.params.visitId as string;
  const { productsOrdered, remarks } = req.body;

  const hasProducts = Array.isArray(productsOrdered) && productsOrdered.length > 0;
  const hasRemarks = typeof remarks === "string" && remarks.trim().length > 0;

  if (!hasProducts && !hasRemarks) {
    res.status(400).json({ error: "Provide productsOrdered and/or remarks." });
    return;
  }

  if (remarks && remarks.length > 500) {
    res.status(400).json({ error: "Remarks cannot exceed 500 characters." });
    return;
  }

  try {
    const visit = await prisma.visit.findUnique({ where: { id: visitId } });
    if (!visit) {
      res.status(404).json({ error: "Visit record not found." });
      return;
    }

    let totalSalesValue = 0;
    const normalizedProducts: Array<{ sku: string; qty: number; unitPrice: number; name?: string }> = [];

    if (hasProducts) {
      for (const item of productsOrdered) {
        if (!item.sku || item.qty === undefined || item.unitPrice === undefined) {
          res.status(400).json({ error: "Each ordered product must contain sku, qty, and unitPrice." });
          return;
        }
        if (item.qty <= 0) {
          res.status(400).json({ error: "Quantity must be greater than 0." });
          return;
        }
        const line = {
          sku: String(item.sku),
          qty: Number(item.qty),
          unitPrice: Number(item.unitPrice),
          name: item.name ? String(item.name) : undefined,
        };
        totalSalesValue += line.qty * line.unitPrice;
        normalizedProducts.push(line);
      }
    }

    const updatedVisit = await prisma.visit.update({
      where: { id: visitId },
      data: {
        productsOrdered: hasProducts ? (normalizedProducts as any) : visit.productsOrdered,
        salesValue: hasProducts ? totalSalesValue : visit.salesValue,
        remarks: hasRemarks ? remarks.trim() : visit.remarks,
      },
    });

    res.status(200).json({
      message: "Visit notes/order submitted successfully",
      visit: updatedVisit,
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
};

export const checkOut = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const visitId = req.params.visitId as string;

  try {
    const visit = await prisma.visit.findUnique({ where: { id: visitId } });
    if (!visit) {
      res.status(404).json({ error: "Visit record not found." });
      return;
    }

    const checkoutTime = new Date();
    const updatedVisit = await prisma.visit.update({
      where: { id: visitId },
      data: { checkoutTime },
    });

    const today = new Date();
    today.setHours(0, 0, 0, 0);

    const plan = await prisma.dailyPlan.findFirst({
      where: { userId: visit.userId, planDate: today },
    });

    if (plan) {
      const todayStart = new Date(today);
      const todayEnd = new Date(today);
      todayEnd.setHours(23, 59, 59, 999);

      const completedVisitsCount = await prisma.visit.count({
        where: {
          userId: visit.userId,
          checkinTime: { gte: todayStart, lte: todayEnd },
          checkoutTime: { not: null },
        },
      });

      await prisma.dailyPlan.update({
        where: { id: plan.id },
        data: { completedVisits: completedVisitsCount },
      });
    }

    res.status(200).json({
      message: "Check-out finalized",
      visit: updatedVisit,
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
};

export const getVisits = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
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

    const visits = await prisma.visit.findMany({
      where: {
        userId,
        checkinTime: { gte: startOfDay, lte: endOfDay },
      },
      include: { outlet: true },
      orderBy: { checkinTime: "desc" },
    });

    res.status(200).json({ visits });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
};
