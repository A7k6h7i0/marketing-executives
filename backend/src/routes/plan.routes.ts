import { Router } from "express";
import { getRoutes, getRouteOutlets, createOrUpdatePlan, getTodayPlan } from "../controllers/plan.controller";
import { authenticateJWT } from "../middlewares/auth";

const router = Router();

router.use(authenticateJWT);

router.get("/routes", getRoutes);
router.get("/routes/:routeId/outlets", getRouteOutlets);
router.post("/plans", createOrUpdatePlan);
router.get("/plans/:userId/today", getTodayPlan);

export default router;
