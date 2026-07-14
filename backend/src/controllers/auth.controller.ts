import { Response } from "express";
import bcrypt from "bcryptjs";
import jwt from "jsonwebtoken";
import { prisma } from "../config/prisma";
import { AuthenticatedRequest } from "../middlewares/auth";
import { Role, AttendanceStatus } from "@prisma/client";

// Helper to generate JWT
const generateToken = (user: { id: string; email: string; role: Role; region: string | null }) => {
  return jwt.sign(
    { id: user.id, email: user.email, role: user.role, region: user.region },
    process.env.JWT_SECRET || "supersecretkey",
    { expiresIn: "12h" } // Expiration in 12 hours as per spec
  );
};

export const register = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const { email, password, phone, role, region } = req.body;

  try {
    if (!email || !password) {
      res.status(400).json({ error: "Email and password are required." });
      return;
    }

    const existingUser = await prisma.user.findUnique({ where: { email } });
    if (existingUser) {
      res.status(400).json({ error: "User already exists with this email." });
      return;
    }

    const passwordHash = await bcrypt.hash(password, 10);

    const user = await prisma.user.create({
      data: {
        email,
        passwordHash,
        phone,
        role: role || Role.SALES_EXECUTIVE,
        region,
      },
      select: {
        id: true,
        email: true,
        phone: true,
        role: true,
        region: true,
        status: true,
        createdAt: true,
      },
    });

    res.status(211).json({ message: "User registered successfully", user });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
};

export const login = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const { email, phone, password, deviceId } = req.body;

  try {
    if ((!email && !phone) || !password || !deviceId) {
      res.status(400).json({ error: "Email/Phone, password, and deviceId are required." });
      return;
    }

    const user = await prisma.user.findFirst({
      where: email ? { email } : { phone },
    });

    if (!user || user.status !== "ACTIVE") {
      res.status(401).json({ error: "Invalid credentials or user is inactive." });
      return;
    }

    const isPasswordValid = await bcrypt.compare(password, user.passwordHash);
    if (!isPasswordValid) {
      res.status(401).json({ error: "Invalid credentials." });
      return;
    }

    // Check if there is an active session on another device (Multiple simultaneous logins blocked)
    const activeAttendanceOnOtherDevice = await prisma.attendance.findFirst({
      where: {
        userId: user.id,
        logoutTime: null,
        deviceId: { not: deviceId },
      },
    });

    if (activeAttendanceOnOtherDevice) {
      res.status(403).json({
        error: "Simultaneous login blocked. This account is already active on another device.",
      });
      return;
    }

    // Check if there's an unclosed session on the SAME device
    let attendance = await prisma.attendance.findFirst({
      where: {
        userId: user.id,
        logoutTime: null,
        deviceId: deviceId,
      },
    });

    const now = new Date();

    if (!attendance) {
      // Create a new attendance session
      attendance = await prisma.attendance.create({
        data: {
          userId: user.id,
          loginTime: now,
          attendanceStatus: AttendanceStatus.INCOMPLETE, // Marked as incomplete until logout
          deviceId,
        },
      });
    }

    const token = generateToken(user);

    res.status(200).json({
      message: "Login successful",
      token,
      user: {
        id: user.id,
        email: user.email,
        phone: user.phone,
        role: user.role,
        region: user.region,
      },
      attendanceId: attendance.id,
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
};

export const logout = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const userId = req.user?.id;
  const { deviceId } = req.body;

  if (!userId || !deviceId) {
    res.status(400).json({ error: "User ID and deviceId are required." });
    return;
  }

  try {
    // Find active attendance record
    const attendance = await prisma.attendance.findFirst({
      where: {
        userId,
        deviceId,
        logoutTime: null,
      },
    });

    if (!attendance) {
      res.status(404).json({ error: "No active session found for this device." });
      return;
    }

    const logoutTime = new Date();
    const loginTime = attendance.loginTime;

    // Calculate total break duration for this user today
    const todayStart = new Date(loginTime);
    todayStart.setHours(0, 0, 0, 0);
    const todayEnd = new Date(logoutTime);
    todayEnd.setHours(23, 59, 59, 999);

    const breaks = await prisma.break.findMany({
      where: {
        userId,
        breakStartTime: { gte: todayStart, lte: todayEnd },
        status: "CLOSED",
      },
    });

    const totalBreakMinutes = breaks.reduce((acc, b) => acc + (b.totalBreakDuration || 0), 0);

    // Calculate gross working hours in milliseconds
    const grossMs = logoutTime.getTime() - loginTime.getTime();
    const grossHours = grossMs / (1000 * 60 * 60);
    const breakHours = totalBreakMinutes / 60;

    // Net working hours = gross hours - break hours
    let netWorkingHours = grossHours - breakHours;
    if (netWorkingHours < 0) netWorkingHours = 0;

    // Update attendance record
    const updatedAttendance = await prisma.attendance.update({
      where: { id: attendance.id },
      data: {
        logoutTime,
        totalWorkingHours: Number(netWorkingHours.toFixed(2)),
        attendanceStatus: AttendanceStatus.PRESENT,
      },
    });

    res.status(200).json({
      message: "Logout successful",
      attendance: updatedAttendance,
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
};
