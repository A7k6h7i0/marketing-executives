import { Router } from "express";
import { submitRating, getRatingHistory, getCurrentGrade } from "../controllers/rating.controller";
import { authenticateJWT } from "../middlewares/auth";

const router = Router();

router.use(authenticateJWT);

router.post("/outlets/:outletId/ratings", submitRating);
router.get("/outlets/:outletId/ratings", getRatingHistory);
router.get("/outlets/:outletId/grade", getCurrentGrade);

export default router;
