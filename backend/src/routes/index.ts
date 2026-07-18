import { Router } from "express";
import authRoutes from "./auth.routes";
import attendanceRoutes from "./attendance.routes";
import breakRoutes from "./break.routes";
import gpsRoutes from "./gps.routes";
import planRoutes from "./plan.routes";
import visitRoutes from "./visit.routes";
import incidentRoutes from "./incident.routes";
import leadRoutes from "./lead.routes";
import routeRoutes from "./route.routes";
import adminRoutes from "./admin.routes";
import telecallerRoutes from "./telecaller.routes";
import uploadRoutes from "./upload.routes";
import outletRoutes from "./outlet.routes";

const router = Router();

router.use("/auth", authRoutes);
router.use("/attendance", attendanceRoutes);
router.use("/breaks", breakRoutes);
router.use("/gps", gpsRoutes);
router.use("/uploads", uploadRoutes);
router.use("/outlets", outletRoutes);
router.use("/", planRoutes); // Matches /routes and /plans in spec
router.use("/", visitRoutes); // Matches /visits
router.use("/", incidentRoutes); // Matches /incidents
router.use("/", leadRoutes); // Matches /leads/nearby and /leads
router.use("/", routeRoutes); // Matches /routes/optimize
router.use("/", adminRoutes); // Matches /admin/kpis, /admin/reports, /admin/users
router.use("/", telecallerRoutes); // Matches /telecaller/*

export default router;
