import { Router } from "express";
import { login, logout, register } from "../controllers/auth.controller";
import { authenticateJWT, authorizeRoles } from "../middlewares/auth";
import { Role } from "@prisma/client";

const router = Router();

router.post("/login", login);
router.post("/logout", authenticateJWT, logout);

// Only Admins or Managers can register new users
router.post("/register", authenticateJWT, authorizeRoles(Role.SUPER_ADMIN, Role.REGIONAL_MANAGER), register);

// Public register endpoint for initial setup (or you can restrict it after first user)
router.post("/setup-register", register);

export default router;
