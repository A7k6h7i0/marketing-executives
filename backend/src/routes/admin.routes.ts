import { Router } from "express";
import { getKpis, getReports, getUsers, createUser, updateUser } from "../controllers/admin.controller";
import { authenticateJWT, authorizeRoles } from "../middlewares/auth";
import { Role } from "@prisma/client";

const router = Router();

router.use(authenticateJWT);
router.use(authorizeRoles(Role.SUPER_ADMIN, Role.REGIONAL_MANAGER, Role.SALES_MANAGER));

router.get("/admin/kpis", getKpis);
router.get("/admin/reports/:reportType", getReports);
router.get("/admin/users", getUsers);
router.post("/admin/users", createUser);
router.patch("/admin/users/:userId", updateUser);

export default router;
