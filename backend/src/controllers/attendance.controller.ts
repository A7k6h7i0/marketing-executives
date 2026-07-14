import { Response } from "express";
import { prisma } from "../config/prisma";
import { AuthenticatedRequest } from "../middlewares/auth";
import { AttendanceStatus } from "@prisma/client";

export const getAttendanceHistory = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const userId = req.params.userId as string;
  const page = parseInt(req.query.page as string) || 1;
  const limit = parseInt(req.query.limit as string) || 10;
  const skip = (page - 1) * limit;

  try {
    // Check permissions: only allow users to view their own attendance unless they are managers/admins
    if (req.user?.id !== userId && req.user?.role === "SALES_EXECUTIVE") {
      res.status(403).json({ error: "Access denied. You can only view your own attendance." });
      return;
    }

    const [attendances, total] = await prisma.$transaction([
      prisma.attendance.findMany({
        where: { userId },
        orderBy: { loginTime: "desc" },
        skip,
        take: limit,
      }),
      prisma.attendance.count({ where: { userId } }),
    ]);

    res.status(200).json({
      data: attendances,
      pagination: {
        total,
        page,
        limit,
        totalPages: Math.ceil(total / limit),
      },
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
};

export const getTodayLiveSummary = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const userId = req.params.userId as string;

  try {
    if (req.user?.id !== userId && req.user?.role === "SALES_EXECUTIVE") {
      res.status(403).json({ error: "Access denied. You can only view your own summary." });
      return;
    }

    const now = new Date();
    const todayStart = new Date(now);
    todayStart.setHours(0, 0, 0, 0);
    const todayEnd = new Date(now);
    todayEnd.setHours(23, 59, 59, 999);

    // Find today's attendance session
    const attendance = await prisma.attendance.findFirst({
      where: {
        userId,
        loginTime: { gte: todayStart, lte: todayEnd },
      },
      orderBy: { loginTime: "desc" },
    });

    if (!attendance) {
      res.status(200).json({
        status: "ABSENT",
        loginTime: null,
        logoutTime: null,
        totalWorkingHours: 0,
        currentBreak: null,
        totalBreakMinutes: 0,
      });
      return;
    }

    // Fetch all breaks for today
    const breaks = await prisma.break.findMany({
      where: {
        userId,
        breakStartTime: { gte: todayStart, lte: todayEnd },
      },
    });

    let totalBreakMinutes = 0;
    let activeBreak = null;

    for (const b of breaks) {
      if (b.status === "CLOSED" && b.totalBreakDuration) {
        totalBreakMinutes += b.totalBreakDuration;
      } else if (b.status === "ACTIVE") {
        activeBreak = b;
        // Calculate active break duration so far in minutes
        const activeDuration = Math.floor((now.getTime() - b.breakStartTime.getTime()) / (1000 * 60));
        totalBreakMinutes += activeDuration;
      }
    }

    // Calculate live working hours
    const endTime = attendance.logoutTime || now;
    const grossMs = endTime.getTime() - attendance.loginTime.getTime();
    const grossHours = grossMs / (1000 * 60 * 60);
    const breakHours = totalBreakMinutes / 60;

    let netWorkingHours = grossHours - breakHours;
    if (netWorkingHours < 0) netWorkingHours = 0;

    res.status(200).json({
      attendanceId: attendance.id,
      status: attendance.logoutTime ? "LOGGED_OUT" : "LOGGED_IN",
      loginTime: attendance.loginTime,
      logoutTime: attendance.logoutTime,
      totalWorkingHours: Number(netWorkingHours.toFixed(2)),
      activeBreak,
      totalBreakMinutes,
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
};
