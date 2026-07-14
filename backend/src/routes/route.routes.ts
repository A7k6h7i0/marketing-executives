import { Router } from "express";
import { optimizeRoute, getOptimizedRoute, skipStop } from "../controllers/route.controller";
import { authenticateJWT } from "../middlewares/auth";

const router = Router();

router.use(authenticateJWT);

router.post("/routes/optimize", optimizeRoute);
router.get("/routes/optimize/:routeId", getOptimizedRoute);
router.patch("/routes/optimize/:routeId/skip/:stopId", skipStop);

export default router;
