import { Router } from "express";
import { checkIn, placeOrder, checkOut, getVisits, getProducts } from "../controllers/visit.controller";
import { authenticateJWT } from "../middlewares/auth";

const router = Router();

router.use(authenticateJWT);

router.get("/products", getProducts);
router.post("/visits/checkin", checkIn);
router.post("/visits/:visitId/order", placeOrder);
router.patch("/visits/:visitId/checkout", checkOut);
router.get("/visits/:userId/:date", getVisits);

export default router;
