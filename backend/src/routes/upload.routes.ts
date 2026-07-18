import { Router } from "express";
import multer from "multer";
import path from "path";
import fs from "fs/promises";
import { randomUUID } from "crypto";
import { Response } from "express";
import { authenticateJWT, AuthenticatedRequest } from "../middlewares/auth";

const router = Router();
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 8 * 1024 * 1024 },
});

router.use(authenticateJWT);

router.post("/selfie", upload.single("file"), async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    const file = req.file;
    if (!file?.buffer) {
      res.status(400).json({ error: "Selfie file is required (field name: file)." });
      return;
    }

    const uploadsDir = path.join(process.cwd(), "uploads", "selfies");
    await fs.mkdir(uploadsDir, { recursive: true });

    const ext = path.extname(file.originalname || "") || ".jpg";
    const filename = `${req.user?.id || "anon"}-${Date.now()}-${randomUUID()}${ext}`;
    await fs.writeFile(path.join(uploadsDir, filename), file.buffer);

    res.status(201).json({
      url: `/uploads/selfies/${filename}`,
      message: "Selfie uploaded",
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

export default router;
