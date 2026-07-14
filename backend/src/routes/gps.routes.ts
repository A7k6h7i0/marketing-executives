import { Router } from "express";
import { pingGps, getRoute, getGpsSummary } from "../controllers/gps.controller";
import { authenticateJWT } from "../middlewares/auth";

const router = Router();

router.use(authenticateJWT);

router.post("/ping", pingGps);
router.get("/route/:userId/:date", getRoute);
router.get("/summary/:userId/:date", getGpsSummary);

export default router;
