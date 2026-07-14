import { Router } from "express";
import { createIncident, getUserIncidents, resolveIncident, getAllIncidents } from "../controllers/incident.controller";
import { authenticateJWT, authorizeRoles } from "../middlewares/auth";
import { Role } from "@prisma/client";

const router = Router();

router.use(authenticateJWT);

router.post("/incidents", createIncident);
router.get("/incidents", getAllIncidents);
router.get("/incidents/:userId", getUserIncidents);
router.patch("/incidents/:incidentId/resolve", authorizeRoles(Role.SUPER_ADMIN, Role.REGIONAL_MANAGER, Role.SALES_MANAGER), resolveIncident);

export default router;
