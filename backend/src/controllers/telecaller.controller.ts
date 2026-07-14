import { Response } from "express";
import { Role, TelecallerLeadStatus } from "@prisma/client";
import { AuthenticatedRequest } from "../middlewares/auth";
import * as telecallerService from "../services/telecaller.service";
import { HttpError } from "../services/telecaller.service";
import { prisma } from "../config/prisma";

function paramId(value: string | string[] | undefined): string {
  if (Array.isArray(value)) return value[0] ?? "";
  return value ?? "";
}

function handleError(res: Response, error: unknown) {
  if (error instanceof HttpError) {
    res.status(error.status).json({ error: { message: error.message } });
    return;
  }
  const message = error instanceof Error ? error.message : "Internal server error";
  res.status(500).json({ error: { message } });
}

async function withAgentPhone(req: AuthenticatedRequest) {
  if (!req.user) throw new HttpError(401, "Unauthorized");
  const user = await prisma.user.findUnique({
    where: { id: req.user.id },
    select: { id: true, email: true, role: true, region: true, phone: true },
  });
  if (!user) throw new HttpError(401, "Unauthorized");
  return user;
}

export const handleWebhook = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    await telecallerService.handleWebhook(req.body || {});
    res.status(200).send("OK");
  } catch (error) {
    handleError(res, error);
  }
};

export const listLeads = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    const user = await withAgentPhone(req);
    const page = req.query.page ? Number(req.query.page) : 1;
    const pageSize = req.query.pageSize ? Number(req.query.pageSize) : 25;
    const status = req.query.status as TelecallerLeadStatus | undefined;
    const result = await telecallerService.listLeads({
      user,
      q: String(req.query.q || ""),
      status,
      ownerId: req.query.ownerId ? String(req.query.ownerId) : undefined,
      assignedDate: req.query.assignedDate ? String(req.query.assignedDate) : undefined,
      page,
      pageSize,
    });
    res.json(result);
  } catch (error) {
    handleError(res, error);
  }
};

export const getLead = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    const user = await withAgentPhone(req);
    const lead = await telecallerService.getLead(paramId(req.params.id), user);
    res.json(lead);
  } catch (error) {
    handleError(res, error);
  }
};

export const createLead = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    const user = await withAgentPhone(req);
    const lead = await telecallerService.createLead(req.body, user);
    res.status(201).json(lead);
  } catch (error) {
    handleError(res, error);
  }
};

export const updateLead = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    const user = await withAgentPhone(req);
    const lead = await telecallerService.updateLead(paramId(req.params.id), req.body, user);
    res.json(lead);
  } catch (error) {
    handleError(res, error);
  }
};

export const bulkDistributeLeads = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    const user = await withAgentPhone(req);
    const result = await telecallerService.bulkDistributeLeads(req.body, user);
    res.status(201).json(result);
  } catch (error) {
    handleError(res, error);
  }
};

export const bulkDistributeLeadsFromFile = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    const user = await withAgentPhone(req);
    const result = await telecallerService.bulkDistributeLeadsFromFile({
      file: req.file,
      input: req.body || {},
      creator: user,
    });
    res.status(201).json(result);
  } catch (error) {
    handleError(res, error);
  }
};

export const initiateCall = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    const user = await withAgentPhone(req);
    const leadId = paramId(req.params.id);
    const payload = { leadId, agent: user };
    if (req.body?.mode === "PHONE") {
      res.json(await telecallerService.logPhoneDial(payload));
      return;
    }
    res.json(await telecallerService.clickToCall(payload));
  } catch (error) {
    handleError(res, error);
  }
};

export const listCalls = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    const user = await withAgentPhone(req);
    const page = req.query.page ? Number(req.query.page) : 1;
    const pageSize = req.query.pageSize ? Number(req.query.pageSize) : 50;
    res.json(await telecallerService.callHistory({ user, page, pageSize }));
  } catch (error) {
    handleError(res, error);
  }
};

export const updateCallOutcome = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    const user = await withAgentPhone(req);
    const updated = await telecallerService.updateCallOutcome(paramId(req.params.id), req.body, user);
    res.json(updated);
  } catch (error) {
    handleError(res, error);
  }
};

export const attachCallRecording = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    const user = await withAgentPhone(req);
    const updated = await telecallerService.attachCallRecording(paramId(req.params.id), req.body, user);
    res.json({ ok: true, recordingUrl: updated.recordingUrl });
  } catch (error) {
    handleError(res, error);
  }
};

export const downloadDailyReport = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    const user = await withAgentPhone(req);
    const report = await telecallerService.buildDailyReport({
      user,
      date: req.query.date ? String(req.query.date) : undefined,
    });
    res.setHeader("Content-Type", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");
    res.setHeader("Content-Disposition", `attachment; filename="${report.filename}"`);
    res.setHeader("X-Report-Call-Count", String(report.calls));
    res.send(report.buffer);
  } catch (error) {
    handleError(res, error);
  }
};

export const followupsDueToday = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    const user = await withAgentPhone(req);
    const items = await telecallerService.followupsDueToday(user);
    res.json({ items });
  } catch (error) {
    handleError(res, error);
  }
};

export const listTelecallers = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    await withAgentPhone(req);
    res.json(await telecallerService.listTelecallers());
  } catch (error) {
    handleError(res, error);
  }
};
