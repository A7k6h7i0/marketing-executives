import express from "express";
import cors from "cors";
import dotenv from "dotenv";
import mainRouter from "./routes";
import { errorHandler } from "./middlewares/error";

// Load environment variables
dotenv.config();

const app = express();
const PORT = process.env.PORT || 5000;

// Set up middle wares
app.use(cors());
app.use(express.json());

// API healthcheck endpoint
app.get("/health", (req, res) => {
  res.status(200).json({ status: "healthy", timestamp: new Date().toISOString() });
});

// Register main application routes
app.use("/", mainRouter);

// Register custom error handler
app.use(errorHandler);

// Start server
app.listen(PORT, () => {
  console.log(`[Server] Sales Executive Tracking App is running on port ${PORT}`);
});
