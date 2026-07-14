import { Response } from "express";
import { prisma } from "../config/prisma";
import { AuthenticatedRequest } from "../middlewares/auth";
import { IncidentType, ResolutionStatus, Role } from "@prisma/client";

// Mock FCM push notification helper
const sendFcmNotification = (managerId: string, title: string, body: string) => {
  console.log(`[FCM Notification sent to Manager ID: ${managerId}]: ${title} - ${body}`);
};

export const createIncident = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const userId = req.user?.id;
  const { incidentType, description, imageUrls, videoUrls } = req.body;

  if (!userId || !incidentType || !description) {
    res.status(400).json({ error: "incidentType and description are required." });
    return;
  }

  // Validate incidentType is a valid enum value
  if (!Object.values(IncidentType).includes(incidentType)) {
    res.status(400).json({
      error: `Invalid incidentType. Must be one of: ${Object.values(IncidentType).join(", ")}`,
    });
    return;
  }

  // Validate description is at least 20 characters
  if (description.length < 20) {
    res.status(400).json({ error: "Description must be at least 20 characters long." });
    return;
  }

  try {
    const incident = await prisma.incident.create({
      data: {
        userId,
        incidentType: incidentType as IncidentType,
        description,
        imageUrls: imageUrls || [],
        videoUrls: videoUrls || [],
        resolutionStatus: ResolutionStatus.OPEN,
      },
      include: {
        user: {
          select: { id: true, email: true, role: true, region: true },
        },
      },
    });

    // Notify Managers: fetch regional/sales managers for this user's region
    const managers = await prisma.user.findMany({
      where: {
        role: { in: [Role.SALES_MANAGER, Role.REGIONAL_MANAGER, Role.SUPER_ADMIN] },
        region: req.user?.region || undefined,
      },
    });

    for (const m of managers) {
      sendFcmNotification(
        m.id,
        `New Incident: ${incidentType}`,
        `Executive ${incident.user.email} reported an incident: ${description.substring(0, 50)}...`
      );
    }

    res.status(201).json({
      message: "Incident logged successfully and managers notified.",
      incident,
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
};

export const getUserIncidents = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const userId = req.params.userId as string;

  try {
    if (req.user?.id !== userId && req.user?.role === Role.SALES_EXECUTIVE) {
      res.status(403).json({ error: "Access denied." });
      return;
    }

    const incidents = await prisma.incident.findMany({
      where: { userId },
      orderBy: { createdAt: "desc" },
    });

    res.status(200).json({ incidents });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
};

export const resolveIncident = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const incidentId = req.params.incidentId as string;
  const managerId = req.user?.id;

  try {
    const incident = await prisma.incident.findUnique({
      where: { id: incidentId },
    });

    if (!incident) {
      res.status(404).json({ error: "Incident not found." });
      return;
    }

    const updatedIncident = await prisma.incident.update({
      where: { id: incidentId },
      data: {
        resolutionStatus: ResolutionStatus.RESOLVED,
        resolvedBy: managerId,
        resolvedAt: new Date(),
      },
    });

    res.status(200).json({
      message: "Incident marked as Resolved",
      incident: updatedIncident,
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
};

export const getAllIncidents = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const type = req.query.type as string;
  const status = req.query.status as string;

  try {
    // Only Managers and Admins can fetch all incidents
    if (req.user?.role === Role.SALES_EXECUTIVE) {
      res.status(403).json({ error: "Forbidden: Admins or Managers only." });
      return;
    }

    const incidents = await prisma.incident.findMany({
      where: {
        incidentType: type ? (type as IncidentType) : undefined,
        resolutionStatus: status ? (status as ResolutionStatus) : undefined,
        // If Regional Manager, limit to their region
        user: req.user?.role === Role.REGIONAL_MANAGER ? { region: req.user.region } : undefined,
      },
      include: {
        user: {
          select: { id: true, email: true, role: true, region: true },
        },
        manager: {
          select: { id: true, email: true, role: true },
        },
      },
      orderBy: { createdAt: "desc" },
    });

    res.status(200).json({ incidents });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
};
