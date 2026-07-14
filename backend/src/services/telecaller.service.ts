import ExcelJS from "exceljs";
import { Role, TelecallerLeadStatus } from "@prisma/client";
import { prisma } from "../config/prisma";

const CALL_OUTCOMES = new Set([
  "REACHABLE",
  "NO_ANSWER",
  "NOT_RESPONDED",
  "BUSY",
  "SWITCHED_OFF",
  "FOLLOWUP_REQUIRED",
  "WRONG_NUMBER",
  "NOT_INTERESTED",
]);

type AuthUser = {
  id: string;
  email: string;
  role: Role;
  region: string | null;
  phone?: string | null;
};

export class HttpError extends Error {
  status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

function normalizePhoneNumber(value: string | null | undefined) {
  return String(value || "")
    .trim()
    .replace(/[^\d+]/g, "");
}

function leadStatusForOutcome(outcome: string, currentStatus: TelecallerLeadStatus) {
  if (outcome === "REACHABLE") return currentStatus === "NEW" ? "CONTACTED" : currentStatus;
  if (outcome === "FOLLOWUP_REQUIRED") return "FOLLOWUP";
  if (outcome === "NOT_INTERESTED" || outcome === "WRONG_NUMBER") return "LOST";
  if (["NO_ANSWER", "NOT_RESPONDED", "BUSY", "SWITCHED_OFF"].includes(outcome)) {
    return currentStatus === "NEW" ? "CONTACTED" : currentStatus;
  }
  return currentStatus;
}

function startOfUtcDay(dateLabel: string) {
  const [year, month, day] = String(dateLabel).split("-").map(Number);
  if (!year || !month || !day) throw new HttpError(400, "Invalid date");
  return new Date(Date.UTC(year, month - 1, day));
}

function workingDates({
  startDate,
  endDate,
  workingDays,
}: {
  startDate: string;
  endDate: string;
  workingDays?: number[];
}) {
  const days = new Set((workingDays || [1, 2, 3, 4, 5, 6]).map(Number));
  const start = startOfUtcDay(startDate);
  const end = startOfUtcDay(endDate);
  if (end < start) throw new HttpError(400, "End date must be after start date");

  const dates: Date[] = [];
  for (const cursor = new Date(start); cursor <= end; cursor.setUTCDate(cursor.getUTCDate() + 1)) {
    if (days.has(cursor.getUTCDay())) dates.push(new Date(cursor));
  }
  return dates;
}

function cellText(value: unknown): string {
  if (value == null) return "";
  if (typeof value === "object" && value !== null) {
    const obj = value as Record<string, unknown>;
    if (typeof obj.text === "string") return obj.text.trim();
    if (Array.isArray(obj.richText)) {
      return obj.richText.map((part) => (part as { text?: string }).text || "").join("").trim();
    }
    if (obj.result != null) return String(obj.result).trim();
  }
  return String(value).trim();
}

function splitCsvLine(line: string) {
  const out: string[] = [];
  let current = "";
  let quoted = false;
  for (let i = 0; i < line.length; i += 1) {
    const char = line[i];
    if (char === '"' && line[i + 1] === '"') {
      current += '"';
      i += 1;
    } else if (char === '"') {
      quoted = !quoted;
    } else if (char === "," && !quoted) {
      out.push(current.trim());
      current = "";
    } else {
      current += char;
    }
  }
  out.push(current.trim());
  return out;
}

function rowToRecord(values: string[], headers: string[] | null = null) {
  const normalizedHeaders = headers?.map((h) => String(h || "").trim().toLowerCase());
  const at = (name: string, fallbackIndex: number) => {
    if (normalizedHeaders) {
      const index = normalizedHeaders.findIndex((header) => header === name);
      if (index >= 0) return values[index] || "";
    }
    return values[fallbackIndex] || "";
  };

  return {
    name: at("name", 0) || at("customer name", 0) || at("lead name", 0),
    phone: at("phone", 1) || at("mobile", 1) || at("phone number", 1),
    company: at("company", 2),
    email: at("email", 3),
    source: at("source", 5),
    notes: at("notes", 4) || at("remark", 4) || at("remarks", 4),
  };
}

function fileExtension(file?: Express.Multer.File) {
  const originalName = String(file?.originalname || "").toLowerCase();
  const match = originalName.match(/\.([a-z0-9]+)$/);
  return match ? match[1] : "";
}

function isCsvUpload(file: Express.Multer.File) {
  const ext = fileExtension(file);
  const mimetype = String(file?.mimetype || "").toLowerCase();
  return ext === "csv" || mimetype === "text/csv" || mimetype === "application/csv";
}

function isOpenXmlExcelUpload(file: Express.Multer.File) {
  const ext = fileExtension(file);
  const mimetype = String(file?.mimetype || "").toLowerCase();
  const buffer = file?.buffer;
  const hasZipSignature =
    Buffer.isBuffer(buffer) &&
    buffer.length >= 4 &&
    buffer[0] === 0x50 &&
    buffer[1] === 0x4b &&
    (buffer[2] === 0x03 || buffer[2] === 0x05 || buffer[2] === 0x07) &&
    (buffer[3] === 0x04 || buffer[3] === 0x06 || buffer[3] === 0x08);

  return (
    ext === "xlsx" ||
    ext === "xlsm" ||
    mimetype === "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" ||
    mimetype === "application/vnd.ms-excel.sheet.macroenabled.12" ||
    hasZipSignature
  );
}

async function parseLeadUpload(file: Express.Multer.File) {
  if (!file?.buffer) throw new HttpError(400, "No file uploaded");
  const records: Array<{
    name: string;
    phone: string;
    company: string | null;
    email: string | null;
    source: string | null;
    notes: string | null;
  }> = [];

  if (isCsvUpload(file)) {
    const lines = file.buffer
      .toString("utf8")
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter(Boolean);
    if (!lines.length) throw new HttpError(400, "Uploaded file is empty");
    const first = splitCsvLine(lines[0]);
    const hasHeader = first.some((cell) => ["name", "phone", "mobile"].includes(cell.trim().toLowerCase()));
    const headers = hasHeader ? first : null;
    for (const line of hasHeader ? lines.slice(1) : lines) {
      records.push(rowToRecord(splitCsvLine(line), headers));
    }
  } else if (isOpenXmlExcelUpload(file)) {
    const workbook = new ExcelJS.Workbook();
    try {
      await workbook.xlsx.load(file.buffer as unknown as ExcelJS.Buffer);
    } catch {
      throw new HttpError(
        400,
        "Could not read Excel file. Please upload a valid .xlsx file exported from Excel or Google Sheets."
      );
    }
    const sheet = workbook.worksheets[0];
    if (!sheet) throw new HttpError(400, "Excel file has no sheets");
    const rowValues = sheet.getRow(1).values;
    const firstRow = (Array.isArray(rowValues) ? rowValues.slice(1) : []).map(cellText);
    const hasHeader = firstRow.some((cell) => ["name", "phone", "mobile"].includes(cell.trim().toLowerCase()));
    const headers = hasHeader ? firstRow : null;
    const start = hasHeader ? 2 : 1;
    for (let rowNumber = start; rowNumber <= sheet.rowCount; rowNumber += 1) {
      const valuesRaw = sheet.getRow(rowNumber).values;
      const values = (Array.isArray(valuesRaw) ? valuesRaw.slice(1) : []).map(cellText);
      if (values.every((value: string) => !value)) continue;
      records.push(rowToRecord(values, headers));
    }
  } else {
    throw new HttpError(400, "Upload an Excel .xlsx/.xlsm or CSV .csv file");
  }

  const cleaned = records
    .map((record) => ({
      name: String(record.name || "").trim(),
      phone: String(record.phone || "").trim(),
      company: record.company ? String(record.company).trim() : null,
      email: record.email ? String(record.email).trim() : null,
      source: record.source ? String(record.source).trim() : null,
      notes: record.notes ? String(record.notes).trim() : null,
    }))
    .filter((record) => record.name && record.phone);

  if (!cleaned.length) {
    throw new HttpError(400, "No valid leads found. Expected columns: name, phone, company, email, notes");
  }
  return cleaned;
}

function parseWorkingDays(value: unknown): number[] | undefined {
  if (Array.isArray(value)) return value.map(Number);
  if (!value) return undefined;
  try {
    const parsed = JSON.parse(String(value));
    if (Array.isArray(parsed)) return parsed.map(Number);
  } catch {
    /* ignore */
  }
  return String(value)
    .split(",")
    .map((part) => Number(part.trim()))
    .filter((part) => !Number.isNaN(part));
}

function assertExotelConfigured() {
  const missing: string[] = [];
  if (!process.env.EXOTEL_SID) missing.push("EXOTEL_SID");
  if (!process.env.EXOTEL_API_KEY) missing.push("EXOTEL_API_KEY");
  if (!process.env.EXOTEL_API_TOKEN) missing.push("EXOTEL_API_TOKEN");
  if (!process.env.EXOTEL_VIRTUAL_NUMBER) missing.push("EXOTEL_VIRTUAL_NUMBER");
  if (missing.length) {
    throw new HttpError(400, `Exotel is not configured. Missing ${missing.join(", ")}`);
  }
}

async function getAgentPhone(userId: string) {
  const user = await prisma.user.findUnique({ where: { id: userId }, select: { phone: true } });
  return user?.phone || null;
}

export async function listLeads({
  user,
  q,
  status,
  ownerId,
  assignedDate,
  page = 1,
  pageSize = 25,
}: {
  user: AuthUser;
  q?: string;
  status?: TelecallerLeadStatus;
  ownerId?: string;
  assignedDate?: string;
  page?: number;
  pageSize?: number;
}) {
  const assignedFor = assignedDate
    ? {
        gte: startOfUtcDay(assignedDate),
        lt: new Date(startOfUtcDay(assignedDate).getTime() + 24 * 60 * 60 * 1000),
      }
    : undefined;

  const where = {
    ...(status ? { status } : {}),
    ...(ownerId ? { ownerId } : {}),
    ...(assignedFor ? { assignedFor } : {}),
    ...(user.role === Role.TELECALLER ? { ownerId: user.id } : {}),
    ...(q
      ? {
          OR: [
            { name: { contains: q, mode: "insensitive" as const } },
            { phone: { contains: q } },
            { company: { contains: q, mode: "insensitive" as const } },
          ],
        }
      : {}),
  };

  const [total, items] = await prisma.$transaction([
    prisma.telecallerLead.count({ where }),
    prisma.telecallerLead.findMany({
      where,
      orderBy: [{ nextFollowAt: "asc" }, { updatedAt: "desc" }],
      skip: (page - 1) * pageSize,
      take: pageSize,
      include: {
        owner: { select: { id: true, name: true, email: true, phone: true } },
      },
    }),
  ]);

  return { total, page, pageSize, items };
}

export async function getLead(id: string, user: AuthUser) {
  const lead = await prisma.telecallerLead.findUnique({
    where: { id },
    include: {
      owner: { select: { id: true, name: true, email: true, phone: true } },
      calls: { orderBy: { createdAt: "desc" }, take: 50 },
    },
  });
  if (!lead) throw new HttpError(404, "Lead not found");
  if (user.role === Role.TELECALLER && lead.ownerId !== user.id) {
    throw new HttpError(403, "Forbidden");
  }
  return lead;
}

export async function createLead(
  input: {
    name: string;
    phone: string;
    company?: string | null;
    email?: string | null;
    status?: TelecallerLeadStatus;
    ownerId?: string;
    source?: string | null;
    notes?: string | null;
    tags?: string[];
    nextFollowAt?: string;
    assignedFor?: string;
  },
  creator: AuthUser
) {
  const ownerId = input.ownerId || creator.id;
  return prisma.telecallerLead.create({
    data: {
      name: input.name,
      phone: input.phone,
      company: input.company || null,
      email: input.email || null,
      status: input.status || "NEW",
      ownerId,
      source: input.source || null,
      notes: input.notes || null,
      tags: input.tags || [],
      nextFollowAt: input.nextFollowAt ? new Date(input.nextFollowAt) : null,
      assignedFor: input.assignedFor ? startOfUtcDay(input.assignedFor) : null,
    },
    include: {
      owner: { select: { id: true, name: true, email: true, phone: true } },
    },
  });
}

export async function bulkDistributeLeads(
  input: {
    telecallerIds: string[];
    startDate: string;
    endDate: string;
    recordsPerTelecallerPerDay?: number;
    workingDays?: number[];
    source?: string | null;
    records: Array<{
      name: string;
      phone: string;
      company?: string | null;
      email?: string | null;
      source?: string | null;
      notes?: string | null;
    }>;
  },
  _creator: AuthUser
) {
  const telecallerIds = Array.from(new Set(input.telecallerIds || []));
  if (!telecallerIds.length) throw new HttpError(400, "Select at least one telecaller");
  if (!input.records?.length) throw new HttpError(400, "Add at least one customer record");

  const telecallers = await prisma.user.findMany({
    where: {
      id: { in: telecallerIds },
      role: Role.TELECALLER,
      status: "ACTIVE",
    },
    select: { id: true },
  });
  if (telecallers.length !== telecallerIds.length) {
    throw new HttpError(400, "One or more selected users are not active telecallers");
  }

  const dates = workingDates({
    startDate: input.startDate,
    endDate: input.endDate,
    workingDays: input.workingDays,
  });
  if (!dates.length) throw new HttpError(400, "No working days in the selected date range");

  const perTelecallerPerDay = Math.max(1, Math.min(Number(input.recordsPerTelecallerPerDay || 100), 500));
  const capacity = dates.length * telecallerIds.length * perTelecallerPerDay;
  const records = input.records.slice(0, capacity);
  if (!records.length) throw new HttpError(400, "No records fit the selected distribution capacity");

  const data = [];
  let index = 0;
  for (const assignedFor of dates) {
    for (const ownerId of telecallerIds) {
      for (let count = 0; count < perTelecallerPerDay && index < records.length; count += 1) {
        const record = records[index];
        index += 1;
        data.push({
          name: record.name,
          phone: record.phone,
          company: record.company || null,
          email: record.email || null,
          source: record.source || input.source || "bulk-distribution",
          notes: record.notes || null,
          status: "NEW" as const,
          ownerId,
          assignedFor,
          tags: ["bulk-assigned"],
        });
      }
    }
  }

  await prisma.telecallerLead.createMany({ data, skipDuplicates: true });
  return {
    assigned: data.length,
    skipped: input.records.length - data.length,
    telecallers: telecallerIds.length,
    workingDays: dates.length,
    recordsPerTelecallerPerDay: perTelecallerPerDay,
  };
}

export async function bulkDistributeLeadsFromFile({
  file,
  input,
  creator,
}: {
  file?: Express.Multer.File;
  input: Record<string, unknown>;
  creator: AuthUser;
}) {
  if (!file) throw new HttpError(400, "No file uploaded");
  const records = await parseLeadUpload(file);
  const telecallerIds = Array.isArray(input.telecallerIds)
    ? (input.telecallerIds as string[])
    : String(input.telecallerIds || "")
        .split(",")
        .map((id) => id.trim())
        .filter(Boolean);

  return bulkDistributeLeads(
    {
      telecallerIds,
      startDate: String(input.startDate || ""),
      endDate: String(input.endDate || ""),
      recordsPerTelecallerPerDay: Number(input.recordsPerTelecallerPerDay || 100),
      workingDays: parseWorkingDays(input.workingDays),
      source: input.source ? String(input.source) : null,
      records,
    },
    creator
  );
}

export async function updateLead(
  id: string,
  input: {
    name?: string;
    phone?: string;
    company?: string | null;
    email?: string | null;
    status?: TelecallerLeadStatus;
    ownerId?: string;
    notes?: string | null;
    tags?: string[];
    nextFollowAt?: string | null;
  },
  user: AuthUser
) {
  const lead = await getLead(id, user);
  if (user.role === Role.TELECALLER && lead.ownerId !== user.id) {
    throw new HttpError(403, "Forbidden");
  }

  const data: Record<string, unknown> = { ...input };
  if (data.nextFollowAt) data.nextFollowAt = new Date(String(data.nextFollowAt));
  if (data.nextFollowAt === null) data.nextFollowAt = null;

  return prisma.telecallerLead.update({
    where: { id },
    data,
    include: {
      owner: { select: { id: true, name: true, email: true, phone: true } },
    },
  });
}

export async function clickToCall({ leadId, agent }: { leadId: string; agent: AuthUser }) {
  const lead = await getLead(leadId, agent);
  if (!lead.phone) throw new HttpError(400, "Lead has no phone number");

  const agentPhone = agent.phone || (await getAgentPhone(agent.id));
  if (!agentPhone) {
    throw new HttpError(400, "Add your calling phone number in Profile before making telecaller calls");
  }
  assertExotelConfigured();

  const fromNumber = normalizePhoneNumber(agentPhone);
  const toNumber = normalizePhoneNumber(lead.phone);
  if (!fromNumber) throw new HttpError(400, "Your calling phone number is invalid");
  if (!toNumber) throw new HttpError(400, "Lead phone number is invalid");

  const { connectCall } = await import("./exotel");
  const result = await connectCall({
    from: fromNumber,
    to: toNumber,
    callerId: process.env.EXOTEL_VIRTUAL_NUMBER,
    statusCallback: process.env.EXOTEL_CALLBACK_URL,
  });

  const call = await prisma.telecallerCall.create({
    data: {
      leadId,
      agentId: agent.id,
      direction: "OUTBOUND",
      externalCallId: result.Sid || result.sid || null,
      fromNumber,
      toNumber,
      status: result.Status || result.status || "queued",
    },
  });

  await prisma.telecallerLead.update({
    where: { id: leadId },
    data: { status: lead.status === "NEW" ? "CONTACTED" : lead.status },
  });

  return { call, exotel: result };
}

export async function logPhoneDial({ leadId, agent }: { leadId: string; agent: AuthUser }) {
  const lead = await getLead(leadId, agent);
  if (!lead.phone) throw new HttpError(400, "Lead has no phone number");

  const agentPhone = agent.phone || (await getAgentPhone(agent.id));
  if (!agentPhone) {
    throw new HttpError(400, "Add your calling phone number in Profile before making telecaller calls");
  }

  const fromNumber = normalizePhoneNumber(agentPhone);
  const toNumber = normalizePhoneNumber(lead.phone);
  if (!fromNumber) throw new HttpError(400, "Your calling phone number is invalid");
  if (!toNumber) throw new HttpError(400, "Lead phone number is invalid");

  const call = await prisma.telecallerCall.create({
    data: {
      leadId,
      agentId: agent.id,
      direction: "OUTBOUND",
      fromNumber,
      toNumber,
      status: "dialer_opened",
    },
  });

  await prisma.telecallerLead.update({
    where: { id: leadId },
    data: { status: lead.status === "NEW" ? "CONTACTED" : lead.status },
  });

  return { call, phone: { to: toNumber } };
}

export async function updateCallOutcome(
  callId: string,
  input: { outcome: string; notes?: string | null },
  user: AuthUser
) {
  const outcome = String(input.outcome || "")
    .trim()
    .toUpperCase();
  if (!CALL_OUTCOMES.has(outcome)) throw new HttpError(400, "Invalid call outcome");

  const call = await prisma.telecallerCall.findUnique({
    where: { id: callId },
    include: { lead: true },
  });
  if (!call) throw new HttpError(404, "Call not found");
  if (user.role === Role.TELECALLER && call.agentId !== user.id) {
    throw new HttpError(403, "Forbidden");
  }

  const updated = await prisma.$transaction(async (tx) => {
    const saved = await tx.telecallerCall.update({
      where: { id: callId },
      data: {
        status: outcome,
        notes: input.notes || null,
        endedAt: new Date(),
      },
      include: {
        lead: { select: { id: true, name: true, phone: true, status: true } },
        agent: { select: { id: true, name: true, email: true } },
      },
    });

    if (call.lead) {
      await tx.telecallerLead.update({
        where: { id: call.lead.id },
        data: { status: leadStatusForOutcome(outcome, call.lead.status) },
      });
    }
    return saved;
  });

  return updated;
}

export async function handleWebhook(payload: Record<string, unknown>) {
  const sid = (payload.CallSid || payload.sid) as string | undefined;
  if (!sid) return null;
  return prisma.telecallerCall.updateMany({
    where: { externalCallId: sid },
    data: {
      status: (payload.Status || payload.status) as string | undefined,
      durationSec: payload.Duration ? parseInt(String(payload.Duration), 10) : undefined,
      recordingUrl: (payload.RecordingUrl as string | undefined) || undefined,
      startedAt: payload.StartTime ? new Date(String(payload.StartTime)) : undefined,
      endedAt: payload.EndTime ? new Date(String(payload.EndTime)) : undefined,
    },
  });
}

export async function callHistory({
  user,
  page = 1,
  pageSize = 50,
}: {
  user: AuthUser;
  page?: number;
  pageSize?: number;
}) {
  const where = user.role === Role.TELECALLER ? { agentId: user.id } : {};
  const [total, items] = await prisma.$transaction([
    prisma.telecallerCall.count({ where }),
    prisma.telecallerCall.findMany({
      where,
      orderBy: { createdAt: "desc" },
      skip: (page - 1) * pageSize,
      take: pageSize,
      include: {
        lead: { select: { id: true, name: true, company: true } },
        agent: { select: { id: true, name: true, email: true } },
      },
    }),
  ]);
  return { total, page, pageSize, items };
}

export async function followupsDueToday(user: AuthUser) {
  const start = new Date();
  start.setHours(0, 0, 0, 0);
  const end = new Date();
  end.setHours(23, 59, 59, 999);
  return prisma.telecallerLead.findMany({
    where: {
      ...(user.role === Role.TELECALLER ? { ownerId: user.id } : {}),
      nextFollowAt: { gte: start, lte: end },
    },
    orderBy: { nextFollowAt: "asc" },
  });
}

export async function attachCallRecording(
  callId: string,
  input: { url?: string | null },
  user: AuthUser
) {
  const call = await prisma.telecallerCall.findUnique({ where: { id: callId } });
  if (!call) throw new HttpError(404, "Call not found");
  if (user.role === Role.TELECALLER && call.agentId !== user.id) {
    throw new HttpError(403, "Forbidden");
  }

  const url = input.url || null;
  if (!url) throw new HttpError(400, "Recording url required");

  return prisma.telecallerCall.update({
    where: { id: callId },
    data: { recordingUrl: url },
  });
}

export async function buildDailyReport({
  user,
  date,
}: {
  user: AuthUser;
  date?: string;
}) {
  const dateLabel =
    date ||
    new Date().toLocaleDateString("en-CA", { timeZone: "Asia/Kolkata" });
  const dayStart = startOfUtcDay(dateLabel);
  const dayEnd = new Date(dayStart.getTime() + 24 * 60 * 60 * 1000);

  const where =
    user.role === Role.TELECALLER
      ? { agentId: user.id, createdAt: { gte: dayStart, lt: dayEnd } }
      : { createdAt: { gte: dayStart, lt: dayEnd } };

  const calls = await prisma.telecallerCall.findMany({
    where,
    orderBy: { createdAt: "asc" },
    include: {
      lead: { select: { name: true, phone: true, company: true } },
      agent: { select: { name: true, email: true, phone: true } },
    },
  });

  const workbook = new ExcelJS.Workbook();
  const sheet = workbook.addWorksheet("Telecaller Calls");
  sheet.columns = [
    { header: "Agent", key: "agent", width: 24 },
    { header: "Lead", key: "lead", width: 24 },
    { header: "Phone", key: "phone", width: 16 },
    { header: "Company", key: "company", width: 20 },
    { header: "Status", key: "status", width: 18 },
    { header: "Duration (sec)", key: "duration", width: 14 },
    { header: "Started At (IST)", key: "started", width: 22 },
    { header: "Notes", key: "notes", width: 30 },
  ];

  for (const call of calls) {
    sheet.addRow({
      agent: call.agent.name || call.agent.email,
      lead: call.lead?.name || "",
      phone: call.lead?.phone || call.toNumber || "",
      company: call.lead?.company || "",
      status: call.status || "",
      duration: call.durationSec ?? "",
      started: (call.startedAt || call.createdAt).toLocaleString("en-IN", { timeZone: "Asia/Kolkata" }),
      notes: call.notes || "",
    });
  }

  const buffer = Buffer.from(await workbook.xlsx.writeBuffer());
  return {
    buffer,
    filename: `telecaller-calls-${dateLabel}.xlsx`,
    calls: calls.length,
  };
}

export async function listTelecallers() {
  const items = await prisma.user.findMany({
    where: { role: Role.TELECALLER, status: "ACTIVE" },
    select: { id: true, name: true, email: true, phone: true, role: true },
    orderBy: { name: "asc" },
  });
  return { items };
}
