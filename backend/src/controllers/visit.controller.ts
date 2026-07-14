import { Response } from "express";
import { prisma } from "../config/prisma";
import { AuthenticatedRequest } from "../middlewares/auth";
import { calculateDistanceKM } from "../utils/distance";
import { SyncStatus } from "@prisma/client";

// Mock Product Catalog
export const MOCK_PRODUCTS = [
  { sku: "SKU-SODA-01", name: "Classic Cola 500ml", unitPrice: 1.50 },
  { sku: "SKU-SODA-02", name: "Diet Lemon-Lime 500ml", unitPrice: 1.60 },
  { sku: "SKU-JUICE-01", name: "100% Orange Juice 1L", unitPrice: 3.20 },
  { sku: "SKU-JUICE-02", name: "Apple Nectar 1L", unitPrice: 2.80 },
  { sku: "SKU-CHIP-01", name: "Barbecue Potato Chips 150g", unitPrice: 2.00 },
  { sku: "SKU-CHIP-02", name: "Sour Cream & Onion 150g", unitPrice: 2.00 },
  { sku: "SKU-WATER-01", name: "Mineral Water 1.5L", unitPrice: 0.80 },
];

export const getProducts = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const query = (req.query.q as string || "").toLowerCase();
  try {
    const filtered = MOCK_PRODUCTS.filter(
      (p) => p.name.toLowerCase().includes(query) || p.sku.toLowerCase().includes(query)
    );
    res.status(200).json({ products: filtered });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
};

export const checkIn = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const userId = req.user?.id;
  const { outletId, gpsLat, gpsLng, selfieUrl, managerOverrideFlag } = req.body;

  if (!userId || !outletId || gpsLat === undefined || gpsLng === undefined || !selfieUrl) {
    res.status(400).json({ error: "outletId, gpsLat, gpsLng, and selfieUrl are required." });
    return;
  }

  try {
    // 1. Fetch Outlet's registered coordinates
    const outlet = await prisma.outlet.findUnique({
      where: { id: outletId },
    });

    if (!outlet) {
      res.status(404).json({ error: "Outlet not found in master database." });
      return;
    }

    // 2. Check distance
    const distanceMeters = calculateDistanceKM(
      Number(outlet.gpsLat),
      Number(outlet.gpsLng),
      Number(gpsLat),
      Number(gpsLng)
    ) * 1000;

    const THRESHOLD_METERS = 100;

    if (distanceMeters > THRESHOLD_METERS && !managerOverrideFlag) {
      res.status(400).json({
        error: "Geofence warning: You are too far from this outlet.",
        distanceMeters: Number(distanceMeters.toFixed(1)),
        thresholdMeters: THRESHOLD_METERS,
        requiresOverride: true,
      });
      return;
    }

    // Create the visit check-in record
    const visit = await prisma.visit.create({
      data: {
        userId,
        outletId,
        gpsLat: Number(gpsLat),
        gpsLng: Number(gpsLng),
        selfieUrl,
        checkinTime: new Date(),
        syncStatus: SyncStatus.SYNCED,
      },
    });

    res.status(201).json({
      message: "Check-in successful",
      visit,
      distanceFromOutletMeters: Number(distanceMeters.toFixed(1)),
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
};

export const placeOrder = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const visitId = req.params.visitId as string;
  const { productsOrdered, remarks } = req.body; // productsOrdered: Array of { sku, qty, unitPrice }

  if (!productsOrdered || !Array.isArray(productsOrdered) || productsOrdered.length === 0) {
    res.status(400).json({ error: "productsOrdered array is required and cannot be empty." });
    return;
  }

  try {
    const visit = await prisma.visit.findUnique({
      where: { id: visitId },
    });

    if (!visit) {
      res.status(404).json({ error: "Visit record not found." });
      return;
    }

    // Calculate sales value
    let totalSalesValue = 0;
    for (const item of productsOrdered) {
      if (!item.sku || !item.qty || !item.unitPrice) {
        res.status(400).json({ error: "Each ordered product must contain sku, qty, and unitPrice." });
        return;
      }
      if (item.qty <= 0) {
        res.status(400).json({ error: "Quantity must be greater than 0." });
        return;
      }
      totalSalesValue += item.qty * item.unitPrice;
    }

    if (totalSalesValue <= 0) {
      res.status(400).json({ error: "Order value must be greater than 0." });
      return;
    }

    // Check remarks length
    if (remarks && remarks.length > 500) {
      res.status(400).json({ error: "Remarks cannot exceed 500 characters." });
      return;
    }

    const updatedVisit = await prisma.visit.update({
      where: { id: visitId },
      data: {
        productsOrdered: productsOrdered as any,
        salesValue: totalSalesValue,
        remarks,
      },
    });

    res.status(200).json({
      message: "Order items submitted successfully",
      visit: updatedVisit,
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
};

export const checkOut = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const visitId = req.params.visitId as string;
  const userId = req.user?.id;

  try {
    const visit = await prisma.visit.findUnique({
      where: { id: visitId },
    });

    if (!visit) {
      res.status(404).json({ error: "Visit record not found." });
      return;
    }

    const checkoutTime = new Date();

    const updatedVisit = await prisma.visit.update({
      where: { id: visitId },
      data: {
        checkoutTime,
      },
    });

    // On checkout, let's update the today's Completed Visits in DailyPlan
    const today = new Date();
    today.setHours(0, 0, 0, 0);

    const plan = await prisma.dailyPlan.findFirst({
      where: {
        userId: visit.userId,
        planDate: today,
      },
    });

    if (plan) {
      // Count total checked out visits today
      const todayStart = new Date(today);
      todayStart.setHours(0, 0, 0, 0);
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
        data: {
          completedVisits: completedVisitsCount,
        },
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
      include: {
        outlet: true,
      },
      orderBy: { checkinTime: "desc" },
    });

    res.status(200).json({ visits });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
};
