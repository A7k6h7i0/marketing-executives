import { Router } from "express";
import { getNearbyLeads, saveLead, updateLead, convertLeadToOutlet, getLeads } from "../controllers/lead.controller";
import { authenticateJWT } from "../middlewares/auth";

const router = Router();

router.use(authenticateJWT);

router.get("/leads/nearby", getNearbyLeads);
router.post("/leads", saveLead);
router.patch("/leads/:leadId", updateLead);
router.post("/leads/:leadId/convert", convertLeadToOutlet);
router.get("/leads", getLeads);

export default router;
