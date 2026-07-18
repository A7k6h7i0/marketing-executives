import { Router, Response } from "express";
import { prisma } from "../config/prisma";
import { authenticateJWT, AuthenticatedRequest } from "../middlewares/auth";
import { submitRating, getRatingHistory, getCurrentGrade } from "../controllers/rating.controller";

const router = Router();
router.use(authenticateJWT);

// Spec module 9 — mount under /outlets
router.post("/:outletId/ratings", submitRating);
router.get("/:outletId/ratings", getRatingHistory);
router.get("/:outletId/grade", getCurrentGrade);

/** Upsert / ensure an outlet exists in master DB (needed before visit check-in). */
router.post("/", async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const { name, address, contactPhone, contactEmail, gpsLat, gpsLng } = req.body;

  if (!name || gpsLat === undefined || gpsLng === undefined) {
    res.status(400).json({ error: "name, gpsLat, and gpsLng are required." });
    return;
  }

  try {
    const lat = Number(gpsLat);
    const lng = Number(gpsLng);

    const candidates = await prisma.outlet.findMany({
      where: { name: { equals: name, mode: "insensitive" } },
      take: 20,
    });

    const match = candidates.find((o) => {
      const dLat = Math.abs(Number(o.gpsLat) - lat);
      const dLng = Math.abs(Number(o.gpsLng) - lng);
      return dLat < 0.001 && dLng < 0.001;
    });

    if (match) {
      res.status(200).json({ outlet: match, created: false });
      return;
    }

    const outlet = await prisma.outlet.create({
      data: {
        name,
        address: address || name,
        contactPhone: contactPhone || null,
        contactEmail: contactEmail || null,
        gpsLat: lat,
        gpsLng: lng,
      },
    });

    res.status(201).json({ outlet, created: true });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

router.get("/", async (_req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    const outlets = await prisma.outlet.findMany({ orderBy: { name: "asc" } });
    res.status(200).json({ outlets });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

export default router;
