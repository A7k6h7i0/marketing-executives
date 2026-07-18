import express from "express";
import cors from "cors";
import dotenv from "dotenv";
import path from "path";
import mainRouter from "./routes";
import { errorHandler } from "./middlewares/error";

// Load environment variables
dotenv.config();

const app = express();
const PORT = process.env.PORT || 5000;

// Set up middle wares
app.use(cors());
app.use(express.json());
app.use("/uploads", express.static(path.join(process.cwd(), "uploads")));

// API healthcheck endpoint
app.get("/health", (req, res) => {
  res.status(200).json({ status: "healthy", timestamp: new Date().toISOString() });
});

// Spec + mobile client both use /api/v1/*
app.use("/api/v1", mainRouter);
// Keep root mount for backward-compatible clients
app.use("/", mainRouter);

// Register custom error handler
app.use(errorHandler);

// Start server
app.listen(PORT, () => {
  console.log(`[Server] Sales Executive Tracking App is running on port ${PORT}`);
});
