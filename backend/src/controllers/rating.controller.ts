import { Response } from "express";
import { prisma } from "../config/prisma";
import { AuthenticatedRequest } from "../middlewares/auth";
import { Grade } from "@prisma/client";

const computeGrade = (rating: number): Grade => {
  if (rating >= 4.0) return Grade.A;
  if (rating >= 3.0) return Grade.B;
  if (rating >= 2.0) return Grade.C;
  return Grade.D;
};

export const submitRating = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const outletId = req.params.outletId as string;
  const reviewerId = req.user?.id;
  const { paymentScore, volumeScore, cooperationScore, consistencyScore, relationshipScore, reviewDate } = req.body;

  if (
    !reviewerId ||
    paymentScore === undefined ||
    volumeScore === undefined ||
    cooperationScore === undefined ||
    consistencyScore === undefined ||
    relationshipScore === undefined
  ) {
    res.status(400).json({ error: "All scores (1-5) are required to rate the outlet." });
    return;
  }

  // Validate scores are integers between 1 and 5
  const scores = [paymentScore, volumeScore, cooperationScore, consistencyScore, relationshipScore];
  for (const score of scores) {
    if (!Number.isInteger(score) || score < 1 || score > 5) {
      res.status(400).json({ error: "Scores must be integer values between 1 and 5." });
      return;
    }
  }

  try {
    const outlet = await prisma.outlet.findUnique({
      where: { id: outletId },
    });

    if (!outlet) {
      res.status(404).json({ error: "Outlet not found." });
      return;
    }

    // Compute average overall rating
    const overallRating = scores.reduce((sum, score) => sum + score, 0) / 5;
    const grade = computeGrade(overallRating);

    const submissionDate = reviewDate ? new Date(reviewDate) : new Date();

    const rating = await prisma.rating.create({
      data: {
        outletId,
        reviewerId,
        paymentScore,
        volumeScore,
        cooperationScore,
        consistencyScore,
        relationshipScore,
        overallRating,
        grade,
        reviewDate: submissionDate,
      },
    });

    // Update Outlet Master overall rating & grade
    await prisma.outlet.update({
      where: { id: outletId },
      data: {
        overallRating,
        grade,
      },
    });

    res.status(201).json({
      message: "Outlet evaluation submitted successfully",
      rating,
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
};

export const getRatingHistory = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const outletId = req.params.outletId as string;

  try {
    const ratings = await prisma.rating.findMany({
      where: { outletId },
      include: {
        reviewer: {
          select: { id: true, email: true, role: true },
        },
      },
      orderBy: { reviewDate: "desc" },
    });

    // Create trend data: array of { date, rating }
    const trend = ratings
      .map((r) => ({
        date: r.reviewDate.toISOString().split("T")[0],
        rating: Number(r.overallRating),
        grade: r.grade,
      }))
      .reverse(); // Chronological order for trend graphs

    res.status(200).json({
      history: ratings,
      trend,
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
};

export const getCurrentGrade = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const outletId = req.params.outletId as string;

  try {
    const outlet = await prisma.outlet.findUnique({
      where: { id: outletId },
      select: {
        id: true,
        name: true,
        grade: true,
        overallRating: true,
      },
    });

    if (!outlet) {
      res.status(404).json({ error: "Outlet not found." });
      return;
    }

    res.status(200).json({
      outletId: outlet.id,
      name: outlet.name,
      grade: outlet.grade,
      overallRating: outlet.overallRating ? Number(outlet.overallRating) : null,
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
};
