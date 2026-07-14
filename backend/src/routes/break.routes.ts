import { Router } from "express";
import { startBreak, endBreak, getTodayBreaks } from "../controllers/break.controller";
import { authenticateJWT } from "../middlewares/auth";

const router = Router();

router.use(authenticateJWT);

router.post("/start", startBreak);
router.patch("/:breakId/end", endBreak);
router.get("/:userId/today", getTodayBreaks);

export default router;
