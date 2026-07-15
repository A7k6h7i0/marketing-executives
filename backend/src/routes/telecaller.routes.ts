import { Router } from "express";
import multer from "multer";
import { Role } from "@prisma/client";
import { authenticateJWT, authorizeRoles } from "../middlewares/auth";
import {
  attachCallRecording,
  bulkDistributeLeads,
  bulkDistributeLeadsFromFile,
  createLead,
  downloadDailyReport,
  followupsDueToday,
  getLead,
  handleWebhook,
  initiateCall,
  listCalls,
  listLeads,
  listTelecallers,
  updateCallOutcome,
  updateLead,
} from "../controllers/telecaller.controller";

const router = Router();
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 10 * 1024 * 1024 } });
const recordingUpload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 50 * 1024 * 1024 },
});

const telecallerOrAdmin = authorizeRoles(
  Role.SUPER_ADMIN,
  Role.REGIONAL_MANAGER,
  Role.SALES_MANAGER,
  Role.TELECALLER
);
const telecallerAdmin = authorizeRoles(Role.SUPER_ADMIN, Role.REGIONAL_MANAGER, Role.SALES_MANAGER);

router.post("/telecaller/webhook", handleWebhook);

router.use(authenticateJWT);

router.get("/telecaller/leads", telecallerOrAdmin, listLeads);
router.get("/telecaller/leads/:id", telecallerOrAdmin, getLead);
router.post("/telecaller/leads", telecallerOrAdmin, createLead);
router.patch("/telecaller/leads/:id", telecallerOrAdmin, updateLead);
router.post("/telecaller/leads/:id/call", telecallerOrAdmin, initiateCall);
router.post("/telecaller/leads/bulk-distribute", telecallerAdmin, bulkDistributeLeads);
router.post(
  "/telecaller/leads/bulk-distribute-file",
  telecallerAdmin,
  upload.single("file"),
  bulkDistributeLeadsFromFile
);
router.get("/telecaller/calls", telecallerOrAdmin, listCalls);
router.patch("/telecaller/calls/:id/outcome", telecallerOrAdmin, updateCallOutcome);
router.post(
  "/telecaller/calls/:id/recording",
  telecallerOrAdmin,
  recordingUpload.single("file"),
  attachCallRecording
);
router.get("/telecaller/calls/daily-report.xlsx", telecallerAdmin, downloadDailyReport);
router.get("/telecaller/followups/today", telecallerOrAdmin, followupsDueToday);
router.get("/telecaller/users", telecallerAdmin, listTelecallers);

export default router;
