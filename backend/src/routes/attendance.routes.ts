import { Router } from "express";
import { getAttendanceHistory, getTodayLiveSummary } from "../controllers/attendance.controller";
import { authenticateJWT } from "../middlewares/auth";

const router = Router();

router.use(authenticateJWT);

router.get("/:userId", getAttendanceHistory);
router.get("/today/:userId", getTodayLiveSummary);

export default router;
