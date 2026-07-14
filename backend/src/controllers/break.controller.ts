import { Response } from "express";
import { prisma } from "../config/prisma";
import { AuthenticatedRequest } from "../middlewares/auth";
import { BreakType, BreakStatus } from "@prisma/client";

export const startBreak = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const userId = req.user?.id;
  const { breakType } = req.body;

  if (!userId || !breakType) {
    res.status(400).json({ error: "User ID and breakType are required." });
    return;
  }

  try {
    // Validate breakType is valid enum value
    if (!Object.values(BreakType).includes(breakType)) {
      res.status(400).json({ error: `Invalid break type. Must be one of: ${Object.values(BreakType).join(", ")}` });
      return;
    }

    // Check if there is already an active break for this user
    const activeBreak = await prisma.break.findFirst({
      where: {
        userId,
        status: BreakStatus.ACTIVE,
      },
    });

    if (activeBreak) {
      res.status(400).json({ error: "You already have an active break session." });
      return;
    }

    // Verify user is logged in (has an active attendance session today)
    const now = new Date();
    const todayStart = new Date(now);
    todayStart.setHours(0, 0, 0, 0);
    const todayEnd = new Date(now);
    todayEnd.setHours(23, 59, 59, 999);

    const activeAttendance = await prisma.attendance.findFirst({
      where: {
        userId,
        loginTime: { gte: todayStart, lte: todayEnd },
        logoutTime: null,
      },
    });

    if (!activeAttendance) {
      res.status(400).json({ error: "You must be logged in/present to start a break." });
      return;
    }

    const newBreak = await prisma.break.create({
      data: {
        userId,
        breakType,
        breakStartTime: now,
        status: BreakStatus.ACTIVE,
      },
    });

    res.status(201).json({
      message: "Break started successfully",
      break: newBreak,
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
};

export const endBreak = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const userId = req.user?.id;
  const breakId = req.params.breakId as string;

  if (!userId || !breakId) {
    res.status(400).json({ error: "User ID and breakId are required." });
    return;
  }

  try {
    const breakRecord = await prisma.break.findUnique({
      where: { id: breakId },
    });

    if (!breakRecord) {
      res.status(404).json({ error: "Break record not found." });
      return;
    }

    if (breakRecord.userId !== userId) {
      res.status(403).json({ error: "Access denied. This is not your break record." });
      return;
    }

    if (breakRecord.status !== BreakStatus.ACTIVE) {
      res.status(400).json({ error: "This break is already closed." });
      return;
    }

    const now = new Date();
    const durationMinutes = Math.floor((now.getTime() - breakRecord.breakStartTime.getTime()) / (1000 * 60));

    const updatedBreak = await prisma.break.update({
      where: { id: breakId },
      data: {
        breakEndTime: now,
        totalBreakDuration: durationMinutes,
        status: BreakStatus.CLOSED,
      },
    });

    res.status(200).json({
      message: "Break ended successfully",
      break: updatedBreak,
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
};

export const getTodayBreaks = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const userId = req.params.userId as string;

  try {
    if (req.user?.id !== userId && req.user?.role === "SALES_EXECUTIVE") {
      res.status(403).json({ error: "Access denied. You can only view your own break history." });
      return;
    }

    const now = new Date();
    const todayStart = new Date(now);
    todayStart.setHours(0, 0, 0, 0);
    const todayEnd = new Date(now);
    todayEnd.setHours(23, 59, 59, 999);

    const breaks = await prisma.break.findMany({
      where: {
        userId,
        breakStartTime: { gte: todayStart, lte: todayEnd },
      },
      orderBy: { breakStartTime: "desc" },
    });

    // Format durations as HH:MM for reporting helper
    const formattedBreaks = breaks.map((b) => {
      let durationStr = "00:00";
      let durationMinutes = b.totalBreakDuration || 0;

      if (b.status === BreakStatus.ACTIVE) {
        durationMinutes = Math.floor((now.getTime() - b.breakStartTime.getTime()) / (1000 * 60));
      }

      const hrs = Math.floor(durationMinutes / 60);
      const mins = durationMinutes % 60;
      durationStr = `${hrs.toString().padStart(2, "0")}:${mins.toString().padStart(2, "0")}`;

      return {
        ...b,
        durationFormatted: durationStr,
        currentDurationMinutes: durationMinutes,
      };
    });

    const totalDurationMinutes = formattedBreaks.reduce((acc, b) => acc + b.currentDurationMinutes, 0);
    const totalHrs = Math.floor(totalDurationMinutes / 60);
    const totalMins = totalDurationMinutes % 60;
    const totalDurationFormatted = `${totalHrs.toString().padStart(2, "0")}:${totalMins.toString().padStart(2, "0")}`;

    res.status(200).json({
      breaks: formattedBreaks,
      summary: {
        totalDurationMinutes,
        totalDurationFormatted,
      },
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
};
